// user_profiles_writer_race_test.go — OPOS #26601.
//
// WHAT IS UNDER TEST
// `user_profiles` has no UNIQUE constraint on `user_id` (and cannot get one
// until somebody decides how to dedupe the pairs that already exist), so the
// writers branch on "does a row exist" and then INSERT. With no lock between
// the check and the INSERT, two concurrent calls for the SAME user both see
// "no row" and both insert — and the account ends up with two profile rows.
// Those duplicates are the reason the reads had to be rewritten in #115 and
// #127; this file pins the writing end.
//
// Two writers live in this package and get one test each:
//   - Store.UpsertProfile      (profile.go)
//   - Store.SubmitRegistration (registration.go)
//
// HOW THE RACE IS MADE DETERMINISTIC — no sleeps, the database does the
// synchronising:
//
//  1. The test opens its own transaction and holds `SELECT … FROM users
//     WHERE id = $1 FOR UPDATE` on the target account. An INSERT into
//     user_profiles must take a FOR KEY SHARE lock on that parent row to
//     satisfy the foreign key (migration 002, fk_user_profiles_user), and
//     FOR UPDATE conflicts with it. So every writer that reaches its INSERT
//     parks there instead of completing.
//  2. Both writers are launched and the test waits — by polling
//     pg_stat_activity, pacing itself with pg_sleep INSIDE the database —
//     until two backends are blocked on a lock. That is the proof both
//     goroutines have got as far as they can get, which is exactly the
//     moment the old code has already made its two "no row" decisions.
//  3. The holding transaction commits, both writers finish, and the test
//     counts the rows.
//
// On the unfixed code both writers are parked on the FK lock and both insert
// once it is released → 2 rows. On the fixed code the second writer is parked
// on the advisory lock instead, sees the first one's row afterwards, and
// updates it → 1 row. Either way the test never sleeps in Go and never races
// on timing.
//
// Needs a throwaway Postgres; skipped without TEST_DATABASE_URL, like the
// other integration tests in this package:
//
//	createdb godonation_wrace
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_wrace?sslmode=disable' \
//	  go test ./internal/users/ -run WriterRace -v
package users

import (
	"context"
	"fmt"
	"math/rand"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────

// makeRaceUser inserts a `users` row and NO profile row — the state both
// writers' insert branches are reached from — and removes everything the
// writers may have created when the test finishes.
func makeRaceUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	// Reserved test range, randomised because users.phone is UNIQUE and a
	// failed cleanup must not break the next run.
	phone := fmt.Sprintf("9647%09d", rand.Intn(1_000_000_000))
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		phone,
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM user_profile_audit_logs WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// holdUsersRow opens a transaction that locks the account's `users` row with
// FOR UPDATE and returns the function that releases it. See the file header:
// this is what parks every writer on its user_profiles INSERT, because the
// foreign key makes that INSERT ask for FOR KEY SHARE on the same row.
func holdUsersRow(t *testing.T, pool *pgxpool.Pool, userID int64) (release func()) {
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

// waitForBlockedBackends returns once at least `want` backends of this
// database are waiting on a lock. It paces itself with pg_sleep, so the
// waiting happens inside Postgres rather than as a Go sleep, and the loop is
// bounded so a test can never hang the suite.
func waitForBlockedBackends(t *testing.T, pool *pgxpool.Pool, want int) {
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
		// The database does the waiting — 20ms per poll, no Go sleep.
		if _, err := pool.Exec(ctx, `SELECT pg_sleep(0.02)`); err != nil {
			t.Fatalf("pace poll: %v", err)
		}
	}
}

// countProfiles is the assertion every test in this file ends with.
func countProfiles(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM user_profiles WHERE user_id = $1`, userID).Scan(&n); err != nil {
		t.Fatalf("count profiles: %v", err)
	}
	return n
}

// runConcurrently launches the two calls, waits for both to park on the lock
// the test is holding, releases it, and returns each call's error. Errors are
// carried back rather than reported from the goroutines, because t.Fatalf may
// only be called from the test's own goroutine.
func runConcurrently(t *testing.T, pool *pgxpool.Pool, userID int64, call func() error) []error {
	t.Helper()
	release := holdUsersRow(t, pool, userID)

	done := make(chan error, 2)
	for i := 0; i < 2; i++ {
		go func() { done <- call() }()
	}
	waitForBlockedBackends(t, pool, 2)
	release()

	errs := make([]error, 0, 2)
	for i := 0; i < 2; i++ {
		select {
		case err := <-done:
			errs = append(errs, err)
		case <-time.After(60 * time.Second):
			t.Fatalf("a concurrent writer never returned")
		}
	}
	return errs
}

// ─── Tests ──────────────────────────────────────────────────────────────

// TestUpsertProfileWriterRaceCreatesOneRow — two /profile/set saves landing at
// the same moment (a double-tap, or the app retrying) must leave the account
// with one profile row, not two.
func TestUpsertProfileWriterRaceCreatesOneRow(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := NewStore(pool)
	uid := makeRaceUser(t, pool)

	name := "Race Tester"
	errs := runConcurrently(t, pool, uid, func() error {
		_, err := s.UpsertProfile(context.Background(), uid,
			ProfileUpdate{FullName: &name}, "user", 0, nil)
		return err
	})
	for i, err := range errs {
		if err != nil {
			t.Fatalf("UpsertProfile call %d: %v", i, err)
		}
	}

	if got := countProfiles(t, pool, uid); got != 1 {
		t.Fatalf("user %d has %d user_profiles rows after two concurrent UpsertProfile calls, want exactly 1", uid, got)
	}
}

// TestSubmitRegistrationWriterRaceCreatesOneRow — the same for registration,
// which is the likelier double-submit of the two: the form's button is the one
// a user taps twice on a slow connection.
func TestSubmitRegistrationWriterRaceCreatesOneRow(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := NewStore(pool)
	uid := makeRaceUser(t, pool)

	errs := runConcurrently(t, pool, uid, func() error {
		_, err := s.SubmitRegistration(context.Background(), uid,
			"Race Tester", "", "Erbil", 1, RegistrationExtras{})
		return err
	})
	for i, err := range errs {
		if err != nil {
			t.Fatalf("SubmitRegistration call %d: %v", i, err)
		}
	}

	if got := countProfiles(t, pool, uid); got != 1 {
		t.Fatalf("user %d has %d user_profiles rows after two concurrent SubmitRegistration calls, want exactly 1", uid, got)
	}
}
