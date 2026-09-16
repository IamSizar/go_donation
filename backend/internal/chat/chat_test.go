// chat_test.go — OPOS #25284 Phase 4 Task 1: proves chat.Store.RequestThread
// is gated shut. The old donor↔campaign-owner direct-chat system is being
// retired in favor of staff-mediated masked group chats (internal/chatgroups,
// Phases 1-3); this pins that the retirement actually landed at the store
// layer, not just that the code compiles.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chat
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chat?sslmode=disable' \
//	  go test ./internal/chat/ -v
package chat

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newTestPool brings a throwaway database up to date with the real
// migrations, mirroring internal/chatgroups/chatgroups_test.go's helper of
// the same name (this package had no test file before this task).
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chat integration test")
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

// makeTestUserSeq keeps generated phone numbers unique across subtests.
var makeTestUserSeq int

// makeTestUser inserts a minimal users row and removes it on cleanup. role is
// informational only (RequestThread's guard never reads it); it is recorded
// so test failures are easier to read.
func makeTestUser(t *testing.T, pool *pgxpool.Pool, role string) int64 {
	t.Helper()
	ctx := context.Background()
	makeTestUserSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		fmt.Sprintf("9647721%06d", makeTestUserSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert test user (%s): %v", role, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// TestRequestThreadRefusesNewDirectChat pins Phase 4 Task 1: RequestThread
// must refuse EVERY call with ErrDirectChatRetired and must not write a
// chat_threads row, now that donor↔owner direct chat is retired in favor of
// staff-mediated masked group chats.
func TestRequestThreadRefusesNewDirectChat(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")

	_, _, _, err := s.RequestThread(context.Background(), donor, owner, nil, donor)
	if !errors.Is(err, ErrDirectChatRetired) {
		t.Fatalf("err = %v, want ErrDirectChatRetired", err)
	}

	var count int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM chat_threads WHERE donor_user_id = $1 AND owner_user_id = $2`,
		donor, owner).Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected no row inserted, got %d", count)
	}
}
