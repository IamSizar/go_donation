// Package support handles support tickets.
package support

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Insert writes a new ticket. Returns its id.
func (s *Store) Insert(ctx context.Context, userID int64, subject, message string) (int64, error) {
	if userID <= 0 {
		return 0, errors.New("invalid userID")
	}
	subject = trimMax(subject, 255)
	message = trimMax(message, 5000)
	if subject == "" || message == "" {
		return 0, errors.New("missing subject or message")
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO support_tickets (user_id, subject, message) VALUES ($1, $2, $3) RETURNING id`,
		userID, subject, message,
	).Scan(&id)
	return id, err
}

func trimMax(s string, max int) string {
	s = strings.TrimSpace(s)
	r := []rune(s)
	if len(r) > max {
		return string(r[:max])
	}
	return s
}
