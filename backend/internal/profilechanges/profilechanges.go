// Package profilechanges holds staff review of a user's own name / photo
// change (migration 093).
//
// profile.Set used to write full_name and profile_picture straight through.
// Both now land here as a pending request; the live profile is untouched until
// an admin approves, so a rejected change never appears anywhere.
package profilechanges

import (
	"context"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Reviewable fields. Kept as constants so no call site writes the literal.
const (
	FieldFullName = "full_name"
	FieldPicture  = "profile_picture"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

type Request struct {
	ID        int64   `json:"id"`
	UserID    int64   `json:"user_id"`
	UserName  string  `json:"user_name"`
	UserPhone string  `json:"user_phone"`
	Field     string  `json:"field"`
	OldValue  string  `json:"old_value"`
	NewValue  string  `json:"new_value"`
	Status    string  `json:"status"`
	CreatedAt string  `json:"created_at"`
	DecidedAt *string `json:"decided_at"`
}

// Submit records a proposed change, replacing any pending one for the same
// (user, field) — re-submitting supersedes rather than queueing another row
// behind the same reviewer. A no-op change (new == old) is dropped.
func (s *Store) Submit(ctx context.Context, userID int64, field, oldValue, newValue string) error {
	if strings.TrimSpace(newValue) == "" || newValue == oldValue {
		return nil
	}
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO profile_change_requests (user_id, field, old_value, new_value)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (user_id, field) WHERE status = 'pending'
		 DO UPDATE SET new_value = EXCLUDED.new_value,
		               old_value = EXCLUDED.old_value,
		               created_at = CURRENT_TIMESTAMP`,
		userID, field, oldValue, newValue)
	return err
}

// PendingFor returns the fields this user currently has awaiting review, so
// the app can show "waiting for approval" next to them.
func (s *Store) PendingFor(ctx context.Context, userID int64) ([]string, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT field FROM profile_change_requests
		  WHERE user_id = $1 AND status = 'pending'`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var f string
		if err := rows.Scan(&f); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

// List returns the review queue. status="" returns every state.
func (s *Store) List(ctx context.Context, status string, limit int) ([]Request, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	args := []any{limit}
	where := "1=1"
	if status = strings.TrimSpace(status); status != "" {
		args = append(args, status)
		where = "r.status = $2"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT r.id, r.user_id,
		        COALESCE(p.full_name, ''), COALESCE(u.phone, ''),
		        r.field, r.old_value, r.new_value, r.status,
		        to_char(r.created_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
		        to_char(r.decided_at, 'YYYY-MM-DD"T"HH24:MI:SS')
		   FROM profile_change_requests r
		   JOIN users u ON u.id = r.user_id
		   LEFT JOIN user_profiles p ON p.user_id = r.user_id
		  WHERE `+where+`
		  ORDER BY (r.status = 'pending') DESC, r.created_at ASC
		  LIMIT $1`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Request{}
	for rows.Next() {
		var r Request
		if err := rows.Scan(&r.ID, &r.UserID, &r.UserName, &r.UserPhone,
			&r.Field, &r.OldValue, &r.NewValue, &r.Status,
			&r.CreatedAt, &r.DecidedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// Decide approves or rejects a pending request. Approving applies the value to
// the live profile in the SAME transaction as the status flip, so the two can
// never disagree.
func (s *Store) Decide(ctx context.Context, id, adminID int64, approve bool, note string) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var userID int64
	var field, newValue string
	if err := tx.QueryRow(ctx,
		`SELECT user_id, field, new_value FROM profile_change_requests
		  WHERE id = $1 AND status = 'pending' FOR UPDATE`, id).
		Scan(&userID, &field, &newValue); err != nil {
		return err
	}

	status := "rejected"
	if approve {
		status = "approved"
		col := ""
		switch field {
		case FieldFullName:
			col = "full_name"
		case FieldPicture:
			col = "profile_picture"
		}
		if col != "" {
			if _, err := tx.Exec(ctx,
				`UPDATE user_profiles SET `+col+` = $1 WHERE user_id = $2`,
				newValue, userID); err != nil {
				return err
			}
		}
	}
	if _, err := tx.Exec(ctx,
		`UPDATE profile_change_requests
		    SET status = $1, decided_at = CURRENT_TIMESTAMP,
		        decided_by = $2, decide_note = $3
		  WHERE id = $4`, status, adminID, strings.TrimSpace(note), id); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
