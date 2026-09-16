// admin_edit_user_profile_race_test.go — OPOS #26601.
//
// The dashboard's PATCH /api/admin/users/:id branches on "does this account
// have a profile row" and INSERTs when it does not (admin_edit.go). Without a
// lock between the check and the INSERT, two operators saving the same account
// at the same moment — or one operator whose double-click sent the request
// twice — each see "no row" and each insert one, leaving the account with two
// `user_profiles` rows. Those duplicates are what #115 and #127 had to work
// around on the reading side.
//
// The race is made deterministic by the database, not by sleeps: the test
// holds `SELECT … FROM users WHERE id = $1 FOR UPDATE` on the account, which
// blocks any INSERT into user_profiles for it (the foreign key from migration
// 002 needs FOR KEY SHARE on that same row), waits until two backends are
// parked on a lock, and only then releases. See
// internal/users/user_profiles_writer_race_test.go for the longer write-up of
// why that is the exact moment the unfixed code has already decided twice.
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_wrace?sslmode=disable' \
//	  go test ./internal/handlers/ -run WriterRace -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// holdUsersRowForRace locks the account's `users` row in its own transaction
// and returns the release function.
func holdUsersRowForRace(t *testing.T, pool *pgxpool.Pool, userID int64) (release func()) {
	t.Helper()
	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin holding transaction: %v", err)
	}
	var got int64
	if err := tx.QueryRow(ctx,
		`SELECT id FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&got); err != nil {
		_ = tx.Rollback(ctx)
		t.Fatalf("lock users row %d: %v", userID, err)
	}
	released := false
	t.Cleanup(func() {
		if !released {
			_ = tx.Rollback(context.Background())
		}
	})
	return func() {
		released = true
		if err := tx.Commit(context.Background()); err != nil {
			t.Errorf("release users row lock: %v", err)
		}
	}
}

// waitForBlockedBackendsInRace returns once at least `want` backends of this
// database are waiting on a lock, pacing itself with pg_sleep so the waiting
// happens inside Postgres rather than as a Go sleep.
func waitForBlockedBackendsInRace(t *testing.T, pool *pgxpool.Pool, want int) {
	t.Helper()
	ctx := context.Background()
	deadline := time.Now().Add(30 * time.Second)
	for {
		var blocked int
		if err := pool.QueryRow(ctx,
			`SELECT count(*) FROM pg_stat_activity
			  WHERE datname = current_database()
			    AND wait_event_type = 'Lock'`).Scan(&blocked); err != nil {
			t.Fatalf("read pg_stat_activity: %v", err)
		}
		if blocked >= want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("only %d backends are blocked on a lock after 30s, want %d", blocked, want)
		}
		if _, err := pool.Exec(ctx, `SELECT pg_sleep(0.02)`); err != nil {
			t.Fatalf("pace poll: %v", err)
		}
	}
}

// TestUserProfileEditWriterRaceCreatesOneRow drives the real PATCH route twice
// at once against an account with no profile row.
func TestUserProfileEditWriterRaceCreatesOneRow(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM user_profiles WHERE user_id = $1`, target.id)
	})

	// The token is minted on the test's own goroutine; only the HTTP call runs
	// concurrently. The body touches profile columns ONLY — no phone or email —
	// so nothing but the profile block writes, which is the branch under test.
	session, err := auth.NewTokenStore(pool).IssueToken(ctx, actor.id, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	raw, err := json.Marshal(map[string]any{"full_name": "Race Tester"})
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	router := newUserEditRouter(pool)

	release := holdUsersRowForRace(t, pool, target.id)
	type result struct {
		status int
		body   string
	}
	done := make(chan result, 2)
	for i := 0; i < 2; i++ {
		go func() {
			req := httptest.NewRequest(http.MethodPatch,
				"/api/admin/users/"+strconv.FormatInt(target.id, 10), bytes.NewReader(raw))
			req.Header.Set("Authorization", "Bearer "+session.AccessToken)
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			done <- result{rec.Code, rec.Body.String()}
		}()
	}
	waitForBlockedBackendsInRace(t, pool, 2)
	release()

	for i := 0; i < 2; i++ {
		select {
		case got := <-done:
			if got.status != http.StatusOK {
				t.Fatalf("PATCH status = %d, want 200 (body: %s)", got.status, got.body)
			}
		case <-time.After(60 * time.Second):
			t.Fatalf("a concurrent PATCH never returned")
		}
	}

	var rows int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM user_profiles WHERE user_id = $1`, target.id).Scan(&rows); err != nil {
		t.Fatalf("count profiles: %v", err)
	}
	if rows != 1 {
		t.Fatalf("user %d has %d user_profiles rows after two concurrent PATCHes, want exactly 1", target.id, rows)
	}
}
