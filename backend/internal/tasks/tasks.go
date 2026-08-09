// Package tasks implements the client note's "Task Verification": staff
// assign a task (title + description) to a user, who sees it in their own
// list and marks it done themselves. See migration 066_tasks.sql.
package tasks

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a task id doesn't exist, or exists but isn't
// owned by the acting user (Complete never leaks which).
var ErrNotFound = errors.New("task not found")

type Task struct {
	ID          int64  `json:"id"`
	UserID      int64  `json:"user_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Status      string `json:"status"` // pending | completed
	AssignedBy  *int64 `json:"assigned_by,omitempty"`
	// Rows sharing a GroupID were assigned together (#5, migration 095).
	// NULL for a task assigned on its own, including every pre-095 row.
	GroupID     *int64     `json:"group_id,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// ListForUser returns the user's own tasks, newest first.
func (s *Store) ListForUser(ctx context.Context, userID int64) ([]Task, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT id, user_id, title, description, status, assigned_by, group_id, created_at, completed_at
		   FROM tasks
		  WHERE user_id = $1
		  ORDER BY id DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanTasks(rows)
}

// Complete marks a task done, but only when it belongs to userID — a user
// can never complete someone else's task, even by guessing an id.
func (s *Store) Complete(ctx context.Context, taskID, userID int64) error {
	tag, err := s.Pool.Exec(ctx,
		`UPDATE tasks SET status = 'completed', completed_at = now()
		  WHERE id = $1 AND user_id = $2 AND status = 'pending'`,
		taskID, userID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// AdminCreate assigns a new task to userID. Kept as the one-assignee case of
// AdminCreateGroup so both paths share the validation and the group_id.
func (s *Store) AdminCreate(ctx context.Context, userID int64, title, description string, assignedBy int64) (Task, error) {
	out, err := s.AdminCreateGroup(ctx, []int64{userID}, title, description, assignedBy)
	if err != nil {
		return Task{}, err
	}
	if len(out) == 0 {
		return Task{}, errors.New("task not created")
	}
	return out[0], nil
}

// AdminCreateGroup assigns the same task to several people at once (#5).
//
// One row per assignee, all sharing a group_id, so each person completes their
// own copy exactly as before and the admin list can still collapse them into
// one card. The whole batch is a single INSERT, so a failure part-way through
// cannot leave some people assigned and others not.
//
// Duplicate ids in userIDs are collapsed — assigning the same person twice
// from a multi-select is a slip, not an instruction to give them two copies.
func (s *Store) AdminCreateGroup(ctx context.Context, userIDs []int64, title, description string, assignedBy int64) ([]Task, error) {
	title = strings.TrimSpace(title)
	if title == "" {
		return nil, errors.New("title is required")
	}
	seen := map[int64]bool{}
	ids := make([]int64, 0, len(userIDs))
	for _, id := range userIDs {
		if id > 0 && !seen[id] {
			seen[id] = true
			ids = append(ids, id)
		}
	}
	if len(ids) == 0 {
		return nil, errors.New("at least one assignee is required")
	}
	var assignedByArg any
	if assignedBy > 0 {
		assignedByArg = assignedBy
	}
	rows, err := s.Pool.Query(ctx,
		// nextval() has to be pulled once in its own CTE. Written inline in
		// the SELECT list it is a per-row volatile call, so every assignee
		// would get a DIFFERENT group_id and the batch would not be a group
		// at all. The CTE yields exactly one row, cross-joined onto each id.
		`WITH g AS (SELECT nextval('task_group_seq') AS gid)
		 INSERT INTO tasks (user_id, title, description, assigned_by, group_id)
		 SELECT uid, $2, $3, $4, g.gid
		   FROM unnest($1::bigint[]) AS uid, g
		 RETURNING id, user_id, title, description, status, assigned_by, group_id, created_at, completed_at`,
		ids, title, strings.TrimSpace(description), assignedByArg,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanTasks(rows)
}

// AdminList returns tasks for the admin dashboard's Tasks page, optionally
// filtered to one user.
//
// Pagination is over GROUPS, not rows (#5): a batch assigned to eight people
// is one card in the UI, and paging by row would split it across a page
// boundary and show the same task twice with half its assignees each time.
// COALESCE(group_id, -id) gives every ungrouped row — which is every task
// created before migration 095 — a group key of its own.
func (s *Store) AdminList(ctx context.Context, userID int64, page, perPage int) ([]Task, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 50
	}
	offset := (page - 1) * perPage

	// When filtering by user, the inner query picks the groups that user
	// appears in and the outer one still returns every member of those groups
	// — an admin looking at one person's task should still see who else was
	// assigned it.
	filter := ""
	args := []any{perPage, offset}
	if userID > 0 {
		filter = "WHERE user_id = $3"
		args = append(args, userID)
	}

	rows, err := s.Pool.Query(ctx,
		`SELECT id, user_id, title, description, status, assigned_by, group_id, created_at, completed_at
		   FROM tasks
		  WHERE COALESCE(group_id, -id) IN (
		        SELECT COALESCE(group_id, -id)
		          FROM tasks `+filter+`
		         GROUP BY COALESCE(group_id, -id)
		         ORDER BY MAX(id) DESC
		         LIMIT $1 OFFSET $2)
		  ORDER BY id DESC`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanTasks(rows)
}

// AdminDelete removes a task outright (an admin correcting a mis-assignment).
func (s *Store) AdminDelete(ctx context.Context, taskID int64) error {
	tag, err := s.Pool.Exec(ctx, `DELETE FROM tasks WHERE id = $1`, taskID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func scanTasks(rows pgx.Rows) ([]Task, error) {
	out := []Task{}
	for rows.Next() {
		var t Task
		if err := rows.Scan(&t.ID, &t.UserID, &t.Title, &t.Description, &t.Status, &t.AssignedBy, &t.GroupID, &t.CreatedAt, &t.CompletedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
