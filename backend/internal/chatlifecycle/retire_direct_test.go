package chatlifecycle

import (
	"context"
	"crypto/rand"
	"math/big"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newTestPool brings a throwaway database up to date with the real
// migrations. Skipped unless TEST_DATABASE_URL is set, so `go test ./...`
// stays green on a bare checkout:
//
//	createdb godonation_chatlifecycle
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatlifecycle?sslmode=disable' \
//	  go test ./internal/chatlifecycle/ -v
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chatlifecycle integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// makeTestUser inserts a minimal users row and removes it on cleanup. role is
// informational only (this package doesn't read users.role_id) — recorded so
// test failures are easier to read.
func makeTestUser(t *testing.T, pool *pgxpool.Pool, role string) int64 {
	t.Helper()
	ctx := context.Background()
	phone := "9647" + randomDigits(t, 8)
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		phone,
	).Scan(&id); err != nil {
		t.Fatalf("insert test user (%s): %v", role, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// randomDigits returns n random decimal digits, for building unique test
// phone numbers without colliding across parallel test runs.
func randomDigits(t *testing.T, n int) string {
	t.Helper()
	digits := make([]byte, n)
	for i := range digits {
		d, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			t.Fatalf("generate random digit: %v", err)
		}
		digits[i] = byte('0' + d.Int64())
	}
	return string(digits)
}

func TestRetireAllDirectThreadsEndsAndArchivesOpenDirectThreads(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")

	var directID, supportID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		VALUES ($1, $2, 'active', $1, 'direct') RETURNING id`, donor, owner).Scan(&directID); err != nil {
		t.Fatalf("insert direct: %v", err)
	}
	if err := pool.QueryRow(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		VALUES ($1, $1, 'active', $1, 'support') RETURNING id`, donor).Scan(&supportID); err != nil {
		t.Fatalf("insert support: %v", err)
	}

	count, err := RetireAllDirectThreads(ctx, pool, staff)
	if err != nil {
		t.Fatalf("RetireAllDirectThreads: %v", err)
	}
	if count != 1 {
		t.Fatalf("count = %d, want 1 (only the direct thread)", count)
	}

	var directLifecycle string
	var directArchivedAt *string
	if err := pool.QueryRow(ctx, `SELECT lifecycle, archived_at::text FROM chat_threads WHERE id = $1`, directID).
		Scan(&directLifecycle, &directArchivedAt); err != nil {
		t.Fatalf("query direct: %v", err)
	}
	if directLifecycle != "ended" || directArchivedAt == nil {
		t.Fatalf("direct thread = lifecycle=%q archived_at=%v, want ended + archived", directLifecycle, directArchivedAt)
	}

	var supportLifecycle string
	if err := pool.QueryRow(ctx, `SELECT lifecycle FROM chat_threads WHERE id = $1`, supportID).Scan(&supportLifecycle); err != nil {
		t.Fatalf("query support: %v", err)
	}
	if supportLifecycle != "open" {
		t.Fatalf("support thread lifecycle = %q, want unchanged (open)", supportLifecycle)
	}
}

func TestRetireAllDirectThreadsIsIdempotent(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")
	if _, err := pool.Exec(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		VALUES ($1, $2, 'active', $1, 'direct')`, donor, owner); err != nil {
		t.Fatalf("insert: %v", err)
	}

	if _, err := RetireAllDirectThreads(ctx, pool, staff); err != nil {
		t.Fatalf("first run: %v", err)
	}
	count, err := RetireAllDirectThreads(ctx, pool, staff)
	if err != nil {
		t.Fatalf("second run: %v", err)
	}
	if count != 0 {
		t.Fatalf("second run count = %d, want 0 (already ended+archived, lifecycle != 'open')", count)
	}
}
