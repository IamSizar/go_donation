// R2 #67 — a wallet top-up REQUEST never changes a balance; only staff
// approving it does, once, atomically with the ledger row.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set.
package wallet

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

func requestsPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestTopUpRequestChangesNothingUntilStaffApprove(t *testing.T) {
	pool := requestsPool(t)
	s := New(pool)
	ctx := context.Background()
	var uid int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ('96470099777', 1, 1) RETURNING id`).Scan(&uid); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM wallet_transactions WHERE user_id = $1`, uid)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, uid)
	})

	id, err := s.CreateTopUpRequest(ctx, uid, 25000, "FIB", "ref 123", nil)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if bal, _ := s.GetBalance(ctx, uid); bal != 0 {
		t.Fatalf("a pending request changed the balance to %d", bal)
	}

	req, bal, err := s.DecideTopUpRequest(ctx, id, 0, true, "")
	if err != nil || req.Status != "approved" || bal != 25000 {
		t.Fatalf("approve: req=%v bal=%d err=%v", req, bal, err)
	}
	if got, _ := s.GetBalance(ctx, uid); got != 25000 {
		t.Fatalf("balance = %d, want 25000", got)
	}
	// Deciding twice must not credit twice.
	if _, _, err := s.DecideTopUpRequest(ctx, id, 0, true, ""); !errors.Is(err, ErrAlreadyDecided) {
		t.Fatalf("second approve err = %v, want ErrAlreadyDecided", err)
	}
	if got, _ := s.GetBalance(ctx, uid); got != 25000 {
		t.Fatalf("balance after second approve = %d, want still 25000", got)
	}
}

func TestRejectedTopUpRequestCreditsNothing(t *testing.T) {
	pool := requestsPool(t)
	s := New(pool)
	ctx := context.Background()
	var uid int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ('96470099778', 1, 1) RETURNING id`).Scan(&uid); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, uid) })

	id, err := s.CreateTopUpRequest(ctx, uid, 10000, "Cash", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.DecideTopUpRequest(ctx, id, 0, false, "payment not received"); err != nil {
		t.Fatalf("reject: %v", err)
	}
	if bal, _ := s.GetBalance(ctx, uid); bal != 0 {
		t.Fatalf("a rejected request credited %d", bal)
	}
	if _, err := s.CreateTopUpRequest(ctx, uid, 0, "Cash", "", nil); !errors.Is(err, ErrInvalidTopUpInput) {
		t.Fatalf("zero amount err = %v, want ErrInvalidTopUpInput", err)
	}
}
