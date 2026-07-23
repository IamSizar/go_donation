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
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Status      string     `json:"status"` // pending | completed
	AssignedBy  *int64     `json:"assigned_by,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// ListForUser returns the user's own tasks, newest first.
func (s *Store) ListForUser(ctx context.Context, userID int64) ([]Task, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT id, user_id, title, description, status, assigned_by, created_at, completed_at
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

// AdminCreate assigns a new task to userID.
func (s *Store) AdminCreate(ctx context.Context, userID int64, title, description string, assignedBy int64) (Task, error) {
	title = strings.TrimSpace(title)
	if title == "" {
		return Task{}, errors.New("title is required")
	}
	var assignedByArg any
	if assignedBy > 0 {
		assignedByArg = assignedBy
	}
	var t Task
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO tasks (user_id, title, description, assigned_by)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, user_id, title, description, status, assigned_by, created_at, completed_at`,
		userID, title, strings.TrimSpace(description), assignedByArg,
	).Scan(&t.ID, &t.UserID, &t.Title, &t.Description, &t.Status, &t.AssignedBy, &t.CreatedAt, &t.CompletedAt)
	if err != nil {
		return Task{}, err
	}
	return t, nil
}

// AdminList returns tasks across all users (newest first), optionally
// filtered to one user, for the admin dashboard's Tasks page.
func (s *Store) AdminList(ctx context.Context, userID int64, page, perPage int) ([]Task, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 50
	}
	offset := (page - 1) * perPage

	var rows pgx.Rows
	var err error
	if userID > 0 {
		rows, err = s.Pool.Query(ctx,
			`SELECT id, user_id, title, description, status, assigned_by, created_at, completed_at
			   FROM tasks WHERE user_id = $1
			  ORDER BY id DESC LIMIT $2 OFFSET $3`,
			userID, perPage, offset,
		)
	} else {
		rows, err = s.Pool.Query(ctx,
			`SELECT id, user_id, title, description, status, assigned_by, created_at, completed_at
			   FROM tasks
			  ORDER BY id DESC LIMIT $1 OFFSET $2`,
			perPage, offset,
		)
	}
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
		if err := rows.Scan(&t.ID, &t.UserID, &t.Title, &t.Description, &t.Status, &t.AssignedBy, &t.CreatedAt, &t.CompletedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
