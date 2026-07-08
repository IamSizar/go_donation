// Package postengagement backs likes, comments and share counts on media posts
// (#24) plus the data side of comment moderation (#25). Likes are a toggle
// keyed on (post, user); comments carry a moderation status.
package postengagement

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Comment is one user comment on a post. UserName / PostTitle are joined in for
// display (empty when not selected).
type Comment struct {
	ID        int64     `json:"id"`
	PostID    int64     `json:"post_id"`
	UserID    int64     `json:"user_id"`
	UserName  string    `json:"user_name"`
	PostTitle string    `json:"post_title,omitempty"`
	Body      string    `json:"body"`
	Status    string    `json:"status"`
	Flagged   bool      `json:"flagged"`
	CreatedAt time.Time `json:"created_at"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// PostMeta returns a post's author id (0 if none) and English title. Also the
// existence check the like/comment handlers use — ErrNoRows → post not found.
func (s *Store) PostMeta(ctx context.Context, postID int64) (authorID int64, title string, err error) {
	var author *int64
	err = s.Pool.QueryRow(ctx,
		`SELECT created_by_user_id, title FROM media_posts WHERE id = $1`, postID,
	).Scan(&author, &title)
	if err != nil {
		return 0, "", err
	}
	if author != nil {
		authorID = *author
	}
	return authorID, title, nil
}

// ToggleLike flips the like for (post, user): inserts when absent, removes when
// present. Returns the resulting liked state and the post's new like count.
func (s *Store) ToggleLike(ctx context.Context, postID, userID int64) (liked bool, count int, err error) {
	tag, err := s.Pool.Exec(ctx,
		`INSERT INTO post_likes (post_id, user_id) VALUES ($1, $2)
		 ON CONFLICT (post_id, user_id) DO NOTHING`,
		postID, userID)
	if err != nil {
		return false, 0, err
	}
	if tag.RowsAffected() == 0 {
		// Already liked → this call means unlike.
		if _, err = s.Pool.Exec(ctx,
			`DELETE FROM post_likes WHERE post_id = $1 AND user_id = $2`, postID, userID); err != nil {
			return false, 0, err
		}
		liked = false
	} else {
		liked = true
	}
	if err = s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM post_likes WHERE post_id = $1`, postID).Scan(&count); err != nil {
		return liked, 0, err
	}
	return liked, count, nil
}

// AddComment inserts a comment with the given moderation status. Returns the
// stored row (with UserName populated) for the app to render optimistically.
func (s *Store) AddComment(ctx context.Context, postID, userID int64, body, status string, flagged bool) (*Comment, error) {
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
		`INSERT INTO post_comments (post_id, user_id, body, status, flagged)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, post_id, user_id, body, status, (flagged = 1), created_at`,
		postID, userID, body, status, flag,
	).Scan(&out.ID, &out.PostID, &out.UserID, &out.Body, &out.Status, &out.Flagged, &out.CreatedAt)
	if err != nil {
		return nil, err
	}
	// Best-effort name fill so the fresh comment shows the author's name.
	// full_name lives on user_profiles (not users).
	_ = s.Pool.QueryRow(ctx, `SELECT full_name FROM user_profiles WHERE user_id = $1`, userID).Scan(&out.UserName)
	return &out, nil
}

// ListComments returns a post's comments, newest first. When onlyApproved, only
// 'approved' rows (the public app view).
func (s *Store) ListComments(ctx context.Context, postID int64, onlyApproved bool, limit int) ([]Comment, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	where := "c.post_id = $1"
	if onlyApproved {
		where += " AND c.status = 'approved'"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT c.id, c.post_id, c.user_id, COALESCE(u.full_name, 'User'),
		        c.body, c.status, (c.flagged = 1), c.created_at
		   FROM post_comments c
		   LEFT JOIN user_profiles u ON u.user_id = c.user_id
		  WHERE `+where+`
		  ORDER BY c.created_at DESC, c.id DESC
		  LIMIT `+itoa(limit),
		postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanComments(rows)
}

// AdminListComments returns comments across all posts for the moderation queue,
// optionally filtered by status. Includes the post title.
func (s *Store) AdminListComments(ctx context.Context, statusFilter string, limit int) ([]Comment, error) {
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
		`SELECT c.id, c.post_id, c.user_id, COALESCE(u.full_name, 'User'),
		        COALESCE(p.title, ''), c.body, c.status, (c.flagged = 1), c.created_at
		   FROM post_comments c
		   LEFT JOIN user_profiles u ON u.user_id = c.user_id
		   LEFT JOIN media_posts p ON p.id = c.post_id
		  WHERE `+where+`
		  ORDER BY (c.status = 'pending') DESC, c.created_at DESC, c.id DESC
		  LIMIT `+itoa(limit),
		args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Comment{}
	for rows.Next() {
		var x Comment
		if err := rows.Scan(&x.ID, &x.PostID, &x.UserID, &x.UserName, &x.PostTitle,
			&x.Body, &x.Status, &x.Flagged, &x.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

// DeleteComment hard-deletes a comment (admin action).
func (s *Store) DeleteComment(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM post_comments WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("comment not found")
	}
	return nil
}

// IncrementShare bumps a post's share_count and returns the new value.
func (s *Store) IncrementShare(ctx context.Context, postID int64) (int, error) {
	var count int
	err := s.Pool.QueryRow(ctx,
		`UPDATE media_posts SET share_count = share_count + 1 WHERE id = $1
		 RETURNING share_count`, postID).Scan(&count)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, errors.New("post not found")
		}
		return 0, err
	}
	return count, nil
}

func scanComments(rows pgx.Rows) ([]Comment, error) {
	out := []Comment{}
	for rows.Next() {
		var x Comment
		if err := rows.Scan(&x.ID, &x.PostID, &x.UserID, &x.UserName,
			&x.Body, &x.Status, &x.Flagged, &x.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
