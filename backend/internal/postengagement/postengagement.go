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

// Activity is one engagement event on a post — a comment or a like — for the
// dashboard's Comments & Activities section (#10).
type Activity struct {
	Kind      string    `json:"kind"` // comment | like
	ID        int64     `json:"id"`   // comment id; 0 for a like (no id of its own)
	PostID    int64     `json:"post_id"`
	PostTitle string    `json:"post_title"`
	PostType  string    `json:"post_type"`
	UserID    int64     `json:"user_id"`
	UserName  string    `json:"user_name"`
	Body      string    `json:"body,omitempty"`   // comment text; empty for a like
	Status    string    `json:"status,omitempty"` // comment moderation status
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

// ItemTypeMediaPost is the saved_items.item_type for a media post. The column
// is free text so a new savable kind needs no migration — but every value the
// backend writes should be a constant here, not a literal at the call site.
const ItemTypeMediaPost = "media_post"

// ToggleSave flips "save for later" for (user, item). Mirrors ToggleLike, but
// against the generic saved_items table (migration 092) so the same two
// endpoints can serve any savable record. Returns the resulting saved state.
func (s *Store) ToggleSave(ctx context.Context, userID int64, itemType string, itemID int64) (bool, error) {
	tag, err := s.Pool.Exec(ctx,
		`INSERT INTO saved_items (user_id, item_type, item_id) VALUES ($1, $2, $3)
		 ON CONFLICT (user_id, item_type, item_id) DO NOTHING`,
		userID, itemType, itemID)
	if err != nil {
		return false, err
	}
	if tag.RowsAffected() > 0 {
		return true, nil
	}
	// Already saved → this call means unsave.
	if _, err = s.Pool.Exec(ctx,
		`DELETE FROM saved_items WHERE user_id = $1 AND item_type = $2 AND item_id = $3`,
		userID, itemType, itemID); err != nil {
		return false, err
	}
	return false, nil
}

// SavedIDs returns the ids of a user's saved items of one type, newest first.
// The caller joins these against whatever table item_type refers to, so this
// package stays unaware of what a "media_post" actually is.
func (s *Store) SavedIDs(ctx context.Context, userID int64, itemType string, limit int) ([]int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT item_id FROM saved_items
		  WHERE user_id = $1 AND item_type = $2
		  ORDER BY created_at DESC
		  LIMIT $3`, userID, itemType, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []int64{}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
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

// ActivityFeed returns recent engagement across all posts, newest first (#10).
//
// Comments and likes are two different tables with no shared key, so this is a
// UNION ALL rather than a join: each side is projected onto the same column
// list and the whole thing is ordered once. A like carries no id, body or
// status of its own — those columns are filled with neutral values so the
// projections line up, and the `kind` column is what the UI switches on.
//
// kindFilter narrows to one kind ("comment" / "like"); anything else, "" or
// "all" returns both.
func (s *Store) ActivityFeed(ctx context.Context, kindFilter string, limit int) ([]Activity, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	kindFilter = strings.TrimSpace(kindFilter)
	if kindFilter != "comment" && kindFilter != "like" {
		kindFilter = ""
	}

	rows, err := s.Pool.Query(ctx,
		`SELECT kind, id, post_id, post_title, post_type, user_id, user_name,
		        body, status, flagged, created_at
		   FROM (
		     SELECT 'comment' AS kind, c.id, c.post_id,
		            COALESCE(p.title, '') AS post_title,
		            COALESCE(p.post_type, '') AS post_type,
		            c.user_id, COALESCE(u.full_name, 'User') AS user_name,
		            c.body, c.status, (c.flagged = 1) AS flagged, c.created_at
		       FROM post_comments c
		       LEFT JOIN user_profiles u ON u.user_id = c.user_id
		       LEFT JOIN media_posts p ON p.id = c.post_id
		     UNION ALL
		     SELECT 'like', 0, l.post_id,
		            COALESCE(p.title, ''),
		            COALESCE(p.post_type, ''),
		            l.user_id, COALESCE(u.full_name, 'User'),
		            '', '', false, l.created_at
		       FROM post_likes l
		       LEFT JOIN user_profiles u ON u.user_id = l.user_id
		       LEFT JOIN media_posts p ON p.id = l.post_id
		   ) a
		  WHERE ($1 = '' OR a.kind = $1)
		  ORDER BY a.created_at DESC
		  LIMIT `+itoa(limit),
		kindFilter)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Activity{}
	for rows.Next() {
		var a Activity
		if err := rows.Scan(&a.Kind, &a.ID, &a.PostID, &a.PostTitle, &a.PostType,
			&a.UserID, &a.UserName, &a.Body, &a.Status, &a.Flagged, &a.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// DeleteComment hard-deletes a comment (admin action).
// H15 — the admin route no longer calls this: DELETE goes through
// handlers.trashRow so the row lands in the Trash and can be restored.
// Kept as the low-level primitive; if you wire it to a route again, that
// route becomes permanently destructive.
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
