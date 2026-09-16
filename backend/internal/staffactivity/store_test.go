// store_test.go — regression coverage for the OpenWork ("Chats assigned
// now") counters in Store.Load.
//
// Follows this codebase's standard integration-test shape (see
// internal/chatgroups/chatgroups_test.go): skipped unless TEST_DATABASE_URL
// is set, migrations applied to a throwaway database, rows cleaned up via
// t.Cleanup.
package staffactivity

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newTestPool brings a throwaway database up to date with the real
// migrations. Skipped unless TEST_DATABASE_URL is set, so `go test ./...`
// stays green on a bare checkout:
//
//	createdb godonation_staffactivity
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_staffactivity?sslmode=disable' \
//	  go test ./internal/staffactivity/ -v
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping staffactivity integration test")
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

// makeTestUser inserts a minimal users row and removes it on cleanup.
func makeTestUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	phone := "9647" + fmt.Sprintf("%08d", rand.Intn(100000000))
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		phone,
	).Scan(&id); err != nil {
		t.Fatalf("insert test user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// makeDonorChatThread inserts a minimal donor↔owner chat_threads row assigned
// to staffID, with the given lifecycle ('open' or 'ended'), and removes it on
// cleanup.
func makeDonorChatThread(t *testing.T, pool *pgxpool.Pool, donor, owner, staffID int64, lifecycle string) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, assigned_staff_user_id, lifecycle)
		 VALUES ($1, $2, 'active', $1, $3, $4) RETURNING id`,
		donor, owner, staffID, lifecycle,
	).Scan(&id); err != nil {
		t.Fatalf("insert chat thread: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_threads WHERE id = $1`, id)
	})
	return id
}

// TestLoadOpenWorkExcludesEndedDonorChats is the regression test for the
// staffactivity "Chats assigned now" metric: after OPOS #25284 Phase 4 ended
// (and Task 2 bulk-archived) every retired direct thread, the DonorChats
// subquery had no `lifecycle` predicate at all, so a staff member's ended
// threads counted toward "currently held" forever — contradicting the
// dashboard's own hint text ("Currently held, not a total over time").
//
// Before the fix (no `AND lifecycle = 'open'` predicate), this test failed:
// DonorChats counted both the open and the ended thread (2), not just the
// open one (1). After the fix it passes.
func TestLoadOpenWorkExcludesEndedDonorChats(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	staff := makeTestUser(t, pool)
	openDonor := makeTestUser(t, pool)
	openOwner := makeTestUser(t, pool)
	endedDonor := makeTestUser(t, pool)
	endedOwner := makeTestUser(t, pool)

	makeDonorChatThread(t, pool, openDonor, openOwner, staff, "open")
	makeDonorChatThread(t, pool, endedDonor, endedOwner, staff, "ended")

	summary, err := s.Load(ctx, staff, 50)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if summary.OpenWork.DonorChats != 1 {
		t.Errorf("OpenWork.DonorChats = %d, want 1 — the ended thread must not count toward \"currently held\"",
			summary.OpenWork.DonorChats)
	}
}
