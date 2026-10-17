package wallet

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Wallet top-up REQUESTS (R2 #67). A request never changes a balance: only
// DecideTopUpRequest does, and only when staff approve it.

var (
	ErrRequestNotFound   = errors.New("top-up request not found")
	ErrAlreadyDecided    = errors.New("top-up request was already decided")
	ErrTooManyPending    = errors.New("too many pending top-up requests")
	ErrInvalidTopUpInput = errors.New("invalid top-up request")
)

// MaxTopUpIQD is the sanity ceiling for one request.
const MaxTopUpIQD = 1_000_000_000

// maxPendingPerUser stops one account from flooding the staff queue.
const maxPendingPerUser = 5

// TopUpRequest is one request, as the user and as staff read it.
type TopUpRequest struct {
	ID            int64      `json:"id"`
	UserID        int64      `json:"user_id"`
	AmountIQD     int64      `json:"amount_iqd"`
	PaymentMethod string     `json:"payment_method"`
	Note          string     `json:"note"`
	ProofPath     *string    `json:"proof_path"`
	Status        string     `json:"status"`
	RejectReason  *string    `json:"reject_reason"`
	DecidedAt     *time.Time `json:"decided_at"`
	CreatedAt     time.Time  `json:"created_at"`
	// Staff view only (empty for the user's own list).
	UserName  *string `json:"user_name,omitempty"`
	UserPhone *string `json:"user_phone,omitempty"`
}

// CreateTopUpRequest records a pending request. The balance is not touched.
func (s *Store) CreateTopUpRequest(ctx context.Context, userID, amountIQD int64, method, note string, proofPath *string) (int64, error) {
	if userID <= 0 || amountIQD <= 0 || amountIQD >= MaxTopUpIQD {
		return 0, ErrInvalidTopUpInput
	}
	method = strings.TrimSpace(method)
	if r := []rune(method); len(r) > 64 {
		method = string(r[:64])
	}
	note = strings.TrimSpace(note)
	if r := []rune(note); len(r) > 500 {
		note = string(r[:500])
	}
	var pending int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM wallet_topup_requests WHERE user_id = $1 AND status = 'pending'`, userID,
	).Scan(&pending); err != nil {
		return 0, err
	}
	if pending >= maxPendingPerUser {
		return 0, ErrTooManyPending
	}
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO wallet_topup_requests (user_id, amount_iqd, payment_method, note, proof_path)
		VALUES ($1, $2, $3, $4, $5) RETURNING id`,
		userID, amountIQD, method, note, proofPath,
	).Scan(&id)
	return id, err
}

const topUpCols = `r.id, r.user_id, r.amount_iqd, r.payment_method, r.note, r.proof_path,
	r.status, r.reject_reason, r.decided_at, r.created_at`

// ListTopUpRequestsForUser returns the user's own requests, newest first.
func (s *Store) ListTopUpRequestsForUser(ctx context.Context, userID int64, limit int) ([]TopUpRequest, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT `+topUpCols+` FROM wallet_topup_requests r
		  WHERE r.user_id = $1 ORDER BY r.created_at DESC, r.id DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []TopUpRequest{}
	for rows.Next() {
		var t TopUpRequest
		if err := rows.Scan(&t.ID, &t.UserID, &t.AmountIQD, &t.PaymentMethod, &t.Note, &t.ProofPath,
			&t.Status, &t.RejectReason, &t.DecidedAt, &t.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// AdminListTopUpRequests returns requests for staff, with the requester's name
// and phone. status "" means all.
func (s *Store) AdminListTopUpRequests(ctx context.Context, status string, limit int) ([]TopUpRequest, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	args := []any{limit}
	where := ""
	if status != "" {
		args = append(args, status)
		where = " WHERE r.status = $2"
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT `+topUpCols+`, p.full_name, u.phone
		  FROM wallet_topup_requests r
		  LEFT JOIN users u ON u.id = r.user_id
		  LEFT JOIN LATERAL (
		      SELECT up.full_name FROM user_profiles up WHERE up.user_id = r.user_id ORDER BY up.id LIMIT 1
		  ) p ON TRUE`+where+`
		 ORDER BY (r.status = 'pending') DESC, r.created_at DESC, r.id DESC
		 LIMIT $1`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []TopUpRequest{}
	for rows.Next() {
		var t TopUpRequest
		if err := rows.Scan(&t.ID, &t.UserID, &t.AmountIQD, &t.PaymentMethod, &t.Note, &t.ProofPath,
			&t.Status, &t.RejectReason, &t.DecidedAt, &t.CreatedAt, &t.UserName, &t.UserPhone); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// DecideTopUpRequest approves or rejects a PENDING request. Approving credits
// the wallet and writes the ledger row in the same transaction as the status
// change, so a request can never be credited twice or credited without being
// marked approved. Returns the request and, when approved, the new balance.
func (s *Store) DecideTopUpRequest(ctx context.Context, id, adminID int64, approve bool, reason string) (*TopUpRequest, int64, error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return nil, 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var t TopUpRequest
	err = tx.QueryRow(ctx,
		`SELECT `+topUpCols+` FROM wallet_topup_requests r WHERE r.id = $1 FOR UPDATE`, id,
	).Scan(&t.ID, &t.UserID, &t.AmountIQD, &t.PaymentMethod, &t.Note, &t.ProofPath,
		&t.Status, &t.RejectReason, &t.DecidedAt, &t.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, 0, ErrRequestNotFound
		}
		return nil, 0, err
	}
	if t.Status != "pending" {
		return nil, 0, ErrAlreadyDecided
	}

	var newBalance int64
	newStatus := "rejected"
	if approve {
		newStatus = "approved"
		if err := tx.QueryRow(ctx,
			`UPDATE users SET wallet_balance_iqd = wallet_balance_iqd + $1 WHERE id = $2 RETURNING wallet_balance_iqd`,
			t.AmountIQD, t.UserID,
		).Scan(&newBalance); err != nil {
			return nil, 0, err
		}
		if err := insertLedgerRow(ctx, tx, t.UserID, t.AmountIQD, "topup", "wallet_topup_requests", t.ID, adminID,
			"Top-up request approved"); err != nil {
			return nil, 0, err
		}
	}
	reason = strings.TrimSpace(reason)
	var reasonArg any
	if !approve && reason != "" {
		reasonArg = reason
	}
	if _, err := tx.Exec(ctx, `
		UPDATE wallet_topup_requests
		   SET status = $2, reject_reason = $3, decided_by = $4, decided_at = CURRENT_TIMESTAMP
		 WHERE id = $1`, id, newStatus, reasonArg, adminID); err != nil {
		return nil, 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, 0, err
	}
	t.Status = newStatus
	return &t, newBalance, nil
}
