// engagement.go — like/comment on donation campaigns.
//
// The campaign detail screen was already showing "Likes"/"Comments" counts
// (List's query hardcoded both to 0 — see campaigns.go) with no way to ever
// move them. This gives them a real backing store.
//
// Deliberately its own small store, not a reuse of internal/postengagement:
// that package's post_likes/post_comments tables key on a bare post_id with
// no type discriminator, so a campaign and a media post that happen to share
// a numeric id would silently merge their like/comment counts. Mirrors
// internal/marriage/engagement.go's shape exactly (added the same day, same
// moderation model) rather than marriage's own privacy name-masking, which
// is specific to marriage profiles being real people's dating-style cards —
// a campaign comment shows the commenter's real name the same way a media
// post comment already does.
package campaigns

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Comment is one user comment on a campaign.
type Comment struct {
	ID         int64     `json:"id"`
	CampaignID int64     `json:"campaign_id"`
	UserID     int64     `json:"user_id"`
	UserName   string    `json:"user_name"`
	Body       string    `json:"body"`
	Status     string    `json:"status"`
	Flagged    bool      `json:"flagged"`
	CreatedAt  time.Time `json:"created_at"`
}

type EngagementStore struct{ Pool *pgxpool.Pool }

func NewEngagementStore(pool *pgxpool.Pool) *EngagementStore { return &EngagementStore{Pool: pool} }

// Exists is the existence check the like/comment handlers use — ErrNoRows
// means the campaign id is not real.
func (s *EngagementStore) Exists(ctx context.Context, campaignID int64) error {
	var id int64
	return s.Pool.QueryRow(ctx, `SELECT id FROM campaigns WHERE id = $1`, campaignID).Scan(&id)
}

// ToggleLike flips the like for (campaign, user). Mirrors
// marriage.EngagementStore.ToggleLike exactly.
func (s *EngagementStore) ToggleLike(ctx context.Context, campaignID, userID int64) (liked bool, count int, err error) {
	tag, err := s.Pool.Exec(ctx,
		`INSERT INTO campaign_likes (campaign_id, user_id) VALUES ($1, $2)
		 ON CONFLICT (campaign_id, user_id) DO NOTHING`,
		campaignID, userID)
	if err != nil {
		return false, 0, err
	}
	if tag.RowsAffected() == 0 {
		if _, err = s.Pool.Exec(ctx,
			`DELETE FROM campaign_likes WHERE campaign_id = $1 AND user_id = $2`,
			campaignID, userID); err != nil {
			return false, 0, err
		}
		liked = false
	} else {
		liked = true
	}
	if err = s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM campaign_likes WHERE campaign_id = $1`, campaignID,
	).Scan(&count); err != nil {
		return liked, 0, err
	}
	return liked, count, nil
}

// HasLiked reports whether the given user has already liked the campaign —
// 0 for a signed-out/guest viewer, who cannot have a row either way.
func (s *EngagementStore) HasLiked(ctx context.Context, campaignID, userID int64) (bool, error) {
	if userID <= 0 {
		return false, nil
	}
	var x int
	err := s.Pool.QueryRow(ctx,
		`SELECT 1 FROM campaign_likes WHERE campaign_id = $1 AND user_id = $2`,
		campaignID, userID).Scan(&x)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// AddComment inserts a comment with the given moderation status.
func (s *EngagementStore) AddComment(ctx context.Context, campaignID, userID int64, body, status string, flagged bool) (*Comment, error) {
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
	var out Comment
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO campaign_comments (campaign_id, user_id, body, status, flagged)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, campaign_id, user_id, body, status, (flagged = 1), created_at`,
		campaignID, userID, body, status, flag,
	).Scan(&out.ID, &out.CampaignID, &out.UserID, &out.Body, &out.Status, &out.Flagged, &out.CreatedAt)
	if err != nil {
		return nil, err
	}
	// OPOS #26603: user_profiles.user_id has no UNIQUE constraint — same
	// LATERAL-join pattern listComments uses below, just for the single row
	// this insert just made.
	_ = s.Pool.QueryRow(ctx,
		`SELECT full_name FROM user_profiles WHERE user_id = $1 ORDER BY id LIMIT 1`,
		userID).Scan(&out.UserName)
	return &out, nil
}

// ListCommentsApproved is the public comment feed — approved only.
func (s *EngagementStore) ListCommentsApproved(ctx context.Context, campaignID int64, limit int) ([]Comment, error) {
	return s.listComments(ctx, campaignID, true, limit)
}

func (s *EngagementStore) listComments(ctx context.Context, campaignID int64, onlyApproved bool, limit int) ([]Comment, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	where := "c.campaign_id = $1"
	if onlyApproved {
		where += " AND c.status = 'approved'"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT c.id, c.campaign_id, c.user_id, COALESCE(u.full_name, 'User'),
		        c.body, c.status, (c.flagged = 1), c.created_at
		   FROM campaign_comments c
		   LEFT JOIN LATERAL (
		          SELECT p.full_name FROM user_profiles p
		           WHERE p.user_id = c.user_id ORDER BY p.id LIMIT 1
		        ) u ON TRUE
		  WHERE `+where+`
		  ORDER BY c.created_at DESC, c.id DESC
		  LIMIT `+strconv.Itoa(limit),
		campaignID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Comment{}
	for rows.Next() {
		var x Comment
		if err := rows.Scan(&x.ID, &x.CampaignID, &x.UserID, &x.UserName,
			&x.Body, &x.Status, &x.Flagged, &x.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

// AdminListComments returns comments across all campaigns for the moderation
// queue, optionally filtered by status. Mirrors
// marriage.EngagementStore.AdminListComments.
func (s *EngagementStore) AdminListComments(ctx context.Context, statusFilter string, limit int) ([]Comment, error) {
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
		`SELECT c.id, c.campaign_id, c.user_id, COALESCE(u.full_name, 'User'),
		        c.body, c.status, (c.flagged = 1), c.created_at
		   FROM campaign_comments c
		   LEFT JOIN LATERAL (
		          SELECT pf.full_name FROM user_profiles pf
		           WHERE pf.user_id = c.user_id ORDER BY pf.id LIMIT 1
		        ) u ON TRUE
		  WHERE `+where+`
		  ORDER BY (c.status = 'pending') DESC, c.created_at DESC, c.id DESC
		  LIMIT `+strconv.Itoa(limit),
		args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Comment{}
	for rows.Next() {
		var x Comment
		if err := rows.Scan(&x.ID, &x.CampaignID, &x.UserID, &x.UserName,
			&x.Body, &x.Status, &x.Flagged, &x.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}
