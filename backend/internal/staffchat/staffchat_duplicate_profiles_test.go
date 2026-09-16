// staffchat_duplicate_profiles_test.go — the staff chat reads must return one
// row per thread, message or directory entry even when a staff member has two
// user_profiles rows (OPOS #26497).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set. This package had no test file before.
package staffchat

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newDupTestPool connects to TEST_DATABASE_URL and brings it up to date with
// the real migrations, the same harness as internal/chat/chat_test.go.
func newDupTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping staffchat integration test")
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

// makeDupStaffUser inserts an employee-tier user with two profile rows (the
// older first) and removes it afterwards; the profiles cascade.
func makeDupStaffUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, staff_tier) VALUES ($1, 1, 1, 'employee') RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert staff user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	for _, name := range []string{"Oldest Profile Name", "Newer Duplicate Profile Name"} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
			id, name); err != nil {
			t.Fatalf("insert profile: %v", err)
		}
	}
	return id
}

// seedDupStaffThread creates a thread between two such users with one message
// from the second, and returns (userA, userB, threadID) with userA < userB as
// the table's CHECK requires.
func seedDupStaffThread(t *testing.T, pool *pgxpool.Pool) (int64, int64, int64) {
	t.Helper()
	ctx := context.Background()
	a, b := makeDupStaffUser(t, pool), makeDupStaffUser(t, pool)
	if a > b {
		a, b = b, a
	}
	var threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO staff_chat_threads (user_a_id, user_b_id) VALUES ($1, $2) RETURNING id`, a, b,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert thread: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM staff_chat_threads WHERE id = $1`, threadID)
	})
	if _, err := pool.Exec(ctx,
		`INSERT INTO staff_chat_messages (thread_id, sender_user_id, body) VALUES ($1, $2, 'hello once')`,
		threadID, b); err != nil {
		t.Fatalf("insert message: %v", err)
	}
	return a, b, threadID
}

func TestStaffChatListThreadsForUserListsEachThreadOnceWhenProfilesAreDuplicated(t *testing.T) {
	pool := newDupTestPool(t)
	a, _, threadID := seedDupStaffThread(t, pool)

	threads, err := New(pool).ListThreadsForUser(context.Background(), a, true)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	if len(threads) != 1 || threads[0].ID != threadID {
		t.Fatalf("got %d threads, want exactly thread %d once", len(threads), threadID)
	}
	if threads[0].OtherName == nil || *threads[0].OtherName != "Oldest Profile Name" {
		t.Errorf("OtherName = %v, want the oldest profile row's name", threads[0].OtherName)
	}
}

func TestStaffChatListMessagesListsEachMessageOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	_, _, threadID := seedDupStaffThread(t, pool)

	msgs, err := New(pool).ListMessages(context.Background(), threadID)
	if err != nil {
		t.Fatalf("ListMessages: %v", err)
	}
	if len(msgs) != 1 {
		t.Fatalf("got %d messages, want 1", len(msgs))
	}
}

func TestStaffChatDirectoryListsEachAccountOnceWhenItHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	a, b, _ := seedDupStaffThread(t, pool)

	entries, err := New(pool).Directory(context.Background(), a)
	if err != nil {
		t.Fatalf("Directory: %v", err)
	}
	got := 0
	for _, e := range entries {
		if e.UserID == b {
			got++
		}
	}
	if got != 1 {
		t.Fatalf("user %d listed %d times in the directory, want 1", b, got)
	}
}
