// Package wallet implements Note #42's TEST-phase internal app wallet: a
// stored IQD balance per real user, admin-only top-up, and spend (debit) as
// a payment method for donations/marketplace purchases. See migration
// 065_wallet.sql for the schema and its rationale.
package wallet

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrInsufficientBalance is returned by Debit when the user's balance is
// lower than the requested amount — the debit and its ledger row are never
// written (the whole attempt rolls back).
var ErrInsufficientBalance = errors.New("insufficient wallet balance")

// Transaction is one row of a user's wallet ledger.
type Transaction struct {
	ID                int64     `json:"id"`
	AmountIQD         int64     `json:"amount_iqd"`
	Type              string    `json:"type"`
	RelatedEntityType *string   `json:"related_entity_type,omitempty"`
	RelatedEntityID   *int64    `json:"related_entity_id,omitempty"`
	Note              *string   `json:"note,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// GetBalance returns the user's current IQD balance (0 for an unknown user —
// callers that need to distinguish "no such user" already know the id is
// valid, since it comes from an authenticated token).
func (s *Store) GetBalance(ctx context.Context, userID int64) (int64, error) {
	var bal int64
	err := s.Pool.QueryRow(ctx, `SELECT wallet_balance_iqd FROM users WHERE id = $1`, userID).Scan(&bal)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, err
	}
	return bal, nil
}

// TopUp credits a user's wallet (admin-initiated, Note #42's test-phase
// top-up) and records the ledger row atomically. adminID is the staff user
// who performed it (0 for a system-generated credit, e.g. a refund).
// Returns the new balance.
func (s *Store) TopUp(ctx context.Context, userID, amountIQD, adminID int64, note string) (int64, error) {
	return s.credit(ctx, userID, amountIQD, "topup", "", 0, adminID, note)
}

// Refund credits back a debit that couldn't be honored downstream (e.g. the
// donation/order row failed to insert after the wallet was already charged).
// Recorded distinctly from an admin TopUp so the ledger stays honest about
// why the balance went up.
func (s *Store) Refund(ctx context.Context, userID, amountIQD int64, relatedEntityType string, relatedEntityID int64, note string) (int64, error) {
	return s.credit(ctx, userID, amountIQD, "refund", relatedEntityType, relatedEntityID, 0, note)
}

func (s *Store) credit(ctx context.Context, userID, amountIQD int64, txType, relatedEntityType string, relatedEntityID, adminID int64, note string) (int64, error) {
	if amountIQD <= 0 {
		return 0, errors.New("amount must be positive")
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var newBalance int64
	if err := tx.QueryRow(ctx,
		`UPDATE users SET wallet_balance_iqd = wallet_balance_iqd + $1 WHERE id = $2 RETURNING wallet_balance_iqd`,
		amountIQD, userID,
	).Scan(&newBalance); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, errors.New("user not found")
		}
		return 0, err
	}

	if err := insertLedgerRow(ctx, tx, userID, amountIQD, txType, relatedEntityType, relatedEntityID, adminID, note); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return newBalance, nil
}

// Debit spends from a user's wallet (a donation or marketplace purchase paid
// with the "app_wallet" payment method). Atomic: the balance check and the
// deduction happen in the same statement (WHERE wallet_balance_iqd >= $1), so
// two concurrent spends can never both succeed past a balance that only
// covers one of them. Returns ErrInsufficientBalance without changing
// anything when the balance is too low.
func (s *Store) Debit(ctx context.Context, userID, amountIQD int64, txType, relatedEntityType string, relatedEntityID int64, note string) error {
	if amountIQD <= 0 {
		return errors.New("amount must be positive")
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx,
		`UPDATE users SET wallet_balance_iqd = wallet_balance_iqd - $1 WHERE id = $2 AND wallet_balance_iqd >= $1`,
		amountIQD, userID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInsufficientBalance
	}

	if err := insertLedgerRow(ctx, tx, userID, -amountIQD, txType, relatedEntityType, relatedEntityID, 0, note); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func insertLedgerRow(ctx context.Context, tx pgx.Tx, userID, signedAmountIQD int64, txType, relatedEntityType string, relatedEntityID, adminID int64, note string) error {
	var entTypeArg, entIDArg, adminIDArg, noteArg any
	if relatedEntityType != "" {
		entTypeArg = relatedEntityType
	}
	if relatedEntityID > 0 {
		entIDArg = relatedEntityID
	}
	if adminID > 0 {
		adminIDArg = adminID
	}
	if n := strings.TrimSpace(note); n != "" {
		noteArg = n
	}
	_, err := tx.Exec(ctx,
		`INSERT INTO wallet_transactions (user_id, amount_iqd, type, related_entity_type, related_entity_id, created_by, note)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		userID, signedAmountIQD, txType, entTypeArg, entIDArg, adminIDArg, noteArg,
	)
	return err
}

// ListTransactions returns a user's own ledger, newest first.
func (s *Store) ListTransactions(ctx context.Context, userID int64, page, perPage int) ([]Transaction, error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 100 {
		perPage = 20
	}
	offset := (page - 1) * perPage
	rows, err := s.Pool.Query(ctx,
		`SELECT id, amount_iqd, type, related_entity_type, related_entity_id, note, created_at
		   FROM wallet_transactions
		  WHERE user_id = $1
		  ORDER BY id DESC
		  LIMIT $2 OFFSET $3`,
		userID, perPage, offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []Transaction{}
	for rows.Next() {
		var t Transaction
		if err := rows.Scan(&t.ID, &t.AmountIQD, &t.Type, &t.RelatedEntityType, &t.RelatedEntityID, &t.Note, &t.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
