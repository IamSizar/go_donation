// Package support handles support tickets.
package support

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Ticket is one support request as the user sees it: their message, its
// current status, and the reply if staff have answered.
type Ticket struct {
	ID         int64      `json:"id"`
	Subject    string     `json:"subject"`
	Message    string     `json:"message"`
	Status     string     `json:"status"`
	AdminReply string     `json:"admin_reply,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
	RepliedAt  *time.Time `json:"replied_at,omitempty"`
}

// A ticket counts as unresolved until staff close or resolve it. Used both to
// badge the list and to decide whether to offer the WhatsApp escalation.
func unresolved(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "closed", "resolved", "done":
		return false
	}
	return true
}

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

// ListForUser returns a user's own tickets, newest first, with the escalation
// signal the support screen needs.
//
// "When a user sends more than three messages on different DATES about the
// same unresolved issue, display an option to contact support through
// WhatsApp." Distinct calendar dates is the part that matters: three messages
// fired off in one frustrated sitting is one attempt, not three, and should
// not unlock an escalation path that bypasses the ticket queue.
func (s *Store) ListForUser(ctx context.Context, userID int64, limit int) ([]Ticket, bool, error) {
	if userID <= 0 {
		return nil, false, errors.New("invalid userID")
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT id, subject, message, status,
		        COALESCE(admin_reply, ''), created_at, replied_at
		   FROM support_tickets
		  WHERE user_id = $1
		  ORDER BY created_at DESC, id DESC
		  LIMIT $2`, userID, limit)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()
	out := []Ticket{}
	for rows.Next() {
		var t Ticket
		if err := rows.Scan(&t.ID, &t.Subject, &t.Message, &t.Status,
			&t.AdminReply, &t.CreatedAt, &t.RepliedAt); err != nil {
			return nil, false, err
		}
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}

	// Count distinct days on which this user raised a ticket that is still
	// unresolved. Done in SQL rather than over `out` so the window is the
	// user's whole history, not just the page returned above.
	var days int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(DISTINCT created_at::date)
		   FROM support_tickets
		  WHERE user_id = $1
		    AND LOWER(COALESCE(status, '')) NOT IN ('closed', 'resolved', 'done')`,
		userID).Scan(&days); err != nil {
		return nil, false, err
	}
	return out, days > 3, nil
}

// ErrEmptyReply / ErrTicketNotFound let the handler map a failure to a stable
// `code` for the dashboard instead of forwarding raw English prose to the
// operator (rule 1.5 / 5.7).
var (
	ErrEmptyReply     = errors.New("reply cannot be empty")
	ErrTicketNotFound = errors.New("ticket not found")
)

// Replied identifies the ticket a staff answer just landed on, so the caller
// can notify the person waiting for it.
//
// OwnerID is a pointer because `support_tickets.user_id` is nullable: the
// dashboard can raise a ticket with no user attached ("User ID (optional)" on
// its create form). Such a ticket has nobody to notify, and the caller must be
// able to tell that apart from user 0.
type Replied struct {
	OwnerID *int64
	Subject string
}

// Reply records a staff answer, marks the ticket answered, and returns who was
// waiting for it.
//
// It returns the owner rather than writing silently because the reply is the
// only half of the support round trip the user cannot poll for: the app's
// ticket list shows a reply once it exists, but nothing tells the user to go
// and look. RETURNING keeps that one round trip instead of a second SELECT.
func (s *Store) Reply(ctx context.Context, id int64, body string, byUserID int64) (Replied, error) {
	body = trimMax(body, 5000)
	if body == "" {
		return Replied{}, ErrEmptyReply
	}
	var out Replied
	err := s.Pool.QueryRow(ctx,
		`UPDATE support_tickets
		    SET admin_reply = $2, replied_at = CURRENT_TIMESTAMP, replied_by = $3
		  WHERE id = $1
		  RETURNING user_id, subject`, id, body, byUserID,
	).Scan(&out.OwnerID, &out.Subject)
	if errors.Is(err, pgx.ErrNoRows) {
		return Replied{}, ErrTicketNotFound
	}
	if err != nil {
		return Replied{}, err
	}
	return out, nil
}

// Unresolved is exported for callers that need the same rule.
func Unresolved(status string) bool { return unresolved(status) }
