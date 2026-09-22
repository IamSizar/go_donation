// engagement.go — like/comment/share on marriage-seeker profile cards
// (client note, 2026-09-22, confirmed with the owner given the privacy
// angle on real people's profiles: "Yes, add all three").
//
// Deliberately its own small store rather than reusing internal/postengagement
// wholesale: that package's queries are hardcoded to media_posts (author id,
// post title, post_type for the activity feed) in ways that do not apply to a
// marriage profile. The SHAPE is copied on purpose — same toggle-like,
// same pending/approved/hidden comment moderation gated by the same
// banned-words check, same privacy-aware name masking (OPOS #26603's
// one-profile-per-commenter fix and K8's "hid their name" fallback) — so one
// moderation mental model covers both feeds.
package marriage

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/privacy"
)

// ProfileComment is one user comment on a marriage profile.
type ProfileComment struct {
	ID        int64     `json:"id"`
	ProfileID int64     `json:"profile_id"`
	UserID    int64     `json:"user_id"`
	UserName  string    `json:"user_name"`
	Body      string    `json:"body"`
	Status    string    `json:"status"`
	Flagged   bool      `json:"flagged"`
	CreatedAt time.Time `json:"created_at"`
}

type EngagementStore struct{ Pool *pgxpool.Pool }

func NewEngagementStore(pool *pgxpool.Pool) *EngagementStore { return &EngagementStore{Pool: pool} }

// ProfileExists is the existence check the like/comment/share handlers use —
// ErrNoRows means the profile id is not real.
func (s *EngagementStore) ProfileExists(ctx context.Context, profileID int64) error {
	var id int64
	return s.Pool.QueryRow(ctx, `SELECT id FROM marriage_profiles WHERE id = $1`, profileID).Scan(&id)
}

// ToggleLike flips the like for (profile, user). Mirrors
// postengagement.Store.ToggleLike exactly.
func (s *EngagementStore) ToggleLike(ctx context.Context, profileID, userID int64) (liked bool, count int, err error) {
	tag, err := s.Pool.Exec(ctx,
		`INSERT INTO marriage_profile_likes (profile_id, user_id) VALUES ($1, $2)
		 ON CONFLICT (profile_id, user_id) DO NOTHING`,
		profileID, userID)
	if err != nil {
		return false, 0, err
	}
	if tag.RowsAffected() == 0 {
		if _, err = s.Pool.Exec(ctx,
			`DELETE FROM marriage_profile_likes WHERE profile_id = $1 AND user_id = $2`,
			profileID, userID); err != nil {
			return false, 0, err
		}
		liked = false
	} else {
		liked = true
	}
	if err = s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM marriage_profile_likes WHERE profile_id = $1`, profileID,
	).Scan(&count); err != nil {
		return liked, 0, err
	}
	return liked, count, nil
}

// AddComment inserts a comment with the given moderation status.
func (s *EngagementStore) AddComment(ctx context.Context, profileID, userID int64, body, status string, flagged bool) (*ProfileComment, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, errors.New("comment cannot be empty")
	}
	if len(body) > 2000 {
		body = body[:2000]
	}
	flag := 0
	if flagged {
		flag = 1
	}
	var out ProfileComment
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO marriage_profile_comments (profile_id, user_id, body, status, flagged)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, profile_id, user_id, body, status, (flagged = 1), created_at`,
		profileID, userID, body, status, flag,
	).Scan(&out.ID, &out.ProfileID, &out.UserID, &out.Body, &out.Status, &out.Flagged, &out.CreatedAt)
	if err != nil {
		return nil, err
	}
	_ = s.Pool.QueryRow(ctx, `SELECT full_name FROM user_profiles WHERE user_id = $1`, userID).Scan(&out.UserName)
	return &out, nil
}

const commentNameFallback = "User"

// ListCommentsForViewer is the public comment feed as one app user sees it
// (K8): a commenter who switched their name off in Privacy Settings shows as
// the same anonymous placeholder the query uses for a missing profile.
func (s *EngagementStore) ListCommentsForViewer(ctx context.Context, profileID, viewerID int64, limit int) ([]ProfileComment, error) {
	items, err := s.listComments(ctx, profileID, true, limit)
	if err != nil {
		return nil, err
	}
	authors := make([]int64, 0, len(items))
	for _, c := range items {
		authors = append(authors, c.UserID)
	}
	seen, err := privacy.LoadFor(ctx, s.Pool, viewerID, authors)
	if err != nil {
		return nil, err
	}
	for i := range items {
		if name := seen.NameString(items[i].UserID, items[i].UserName); name != "" {
			items[i].UserName = name
		} else {
			items[i].UserName = commentNameFallback
		}
	}
	return items, nil
}

func (s *EngagementStore) listComments(ctx context.Context, profileID int64, onlyApproved bool, limit int) ([]ProfileComment, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	where := "c.profile_id = $1"
	if onlyApproved {
		where += " AND c.status = 'approved'"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT c.id, c.profile_id, c.user_id, COALESCE(u.full_name, 'User'),
		        c.body, c.status, (c.flagged = 1), c.created_at
		   FROM marriage_profile_comments c
		   -- OPOS #26603: user_profiles.user_id has no UNIQUE constraint.
		   LEFT JOIN LATERAL (
		          SELECT p.full_name FROM user_profiles p
		           WHERE p.user_id = c.user_id ORDER BY p.id LIMIT 1
		        ) u ON TRUE
		  WHERE `+where+`
		  ORDER BY c.created_at DESC, c.id DESC
		  LIMIT `+itoa(limit),
		profileID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ProfileComment{}
	for rows.Next() {
		var x ProfileComment
		if err := rows.Scan(&x.ID, &x.ProfileID, &x.UserID, &x.UserName,
			&x.Body, &x.Status, &x.Flagged, &x.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

// AdminListComments returns comments across all profiles for the moderation
// queue, optionally filtered by status.
func (s *EngagementStore) AdminListComments(ctx context.Context, statusFilter string, limit int) ([]ProfileComment, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	args := []any{}
	where := "1=1"
	if statusFilter = strings.TrimSpace(statusFilter); statusFilter != "" && statusFilter != "all" {
		args = append(args, statusFilter)
		where = "c.status = $1"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT c.id, c.profile_id, c.user_id, COALESCE(u.full_name, 'User'),
		        c.body, c.status, (c.flagged = 1), c.created_at
		   FROM marriage_profile_comments c
		   LEFT JOIN LATERAL (
		          SELECT pf.full_name FROM user_profiles pf
		           WHERE pf.user_id = c.user_id ORDER BY pf.id LIMIT 1
		        ) u ON TRUE
		  WHERE `+where+`
		  ORDER BY (c.status = 'pending') DESC, c.created_at DESC, c.id DESC
		  LIMIT `+itoa(limit),
		args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ProfileComment{}
	for rows.Next() {
		var x ProfileComment
		if err := rows.Scan(&x.ID, &x.ProfileID, &x.UserID, &x.UserName,
			&x.Body, &x.Status, &x.Flagged, &x.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

// IncrementShare bumps a profile's share_count and returns the new value.
func (s *EngagementStore) IncrementShare(ctx context.Context, profileID int64) (int, error) {
	var count int
	err := s.Pool.QueryRow(ctx,
		`UPDATE marriage_profiles SET share_count = share_count + 1 WHERE id = $1
		 RETURNING share_count`, profileID).Scan(&count)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, errors.New("profile not found")
		}
		return 0, err
	}
	return count, nil
}
