// marriagechat_duplicate_profiles_test.go — the marriage admin reads must
// return one row per meeting request, thread or message even when a party has
// two user_profiles rows (OPOS #26497).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set. This package had no test file before.
package marriagechat

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newDupTestPool connects to TEST_DATABASE_URL and applies the real
// migrations, the same harness as internal/chat/chat_test.go.
func newDupTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping marriagechat integration test")
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

// makeDupUser inserts a user with two profile rows (older first) and removes
// it afterwards; the profiles cascade.
func makeDupUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
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

// dupMarriageFixture is one profile, one meeting request against it, one
// thread and one message, where requester and owner both have two profiles.
type dupMarriageFixture struct {
	requestID, threadID int64
}

func seedDupMarriageFixture(t *testing.T, pool *pgxpool.Pool) dupMarriageFixture {
	t.Helper()
	ctx := context.Background()
	owner, requester := makeDupUser(t, pool), makeDupUser(t, pool)
	var profileID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code) VALUES ($1, $2) RETURNING id`,
		owner, fmt.Sprintf("DUP-%d", owner),
	).Scan(&profileID); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	var f dupMarriageFixture
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id) VALUES ($1, $2) RETURNING id`,
		requester, profileID,
	).Scan(&f.requestID); err != nil {
		t.Fatalf("insert meeting request: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_chat_threads (meeting_request_id, profile_id, requester_user_id, owner_user_id)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		f.requestID, profileID, requester, owner,
	).Scan(&f.threadID); err != nil {
		t.Fatalf("insert thread: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO marriage_chat_messages (thread_id, sender_user_id, sender_role, body)
		 VALUES ($1, $2, 'requester', 'hello once')`, f.threadID, requester); err != nil {
		t.Fatalf("insert message: %v", err)
	}
	// Removed child-first; registered after the users, so it runs before
	// their cleanup.
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM marriage_chat_messages WHERE thread_id = $1`, f.threadID)
		_, _ = pool.Exec(bg, `DELETE FROM marriage_chat_threads WHERE id = $1`, f.threadID)
		_, _ = pool.Exec(bg, `DELETE FROM marriage_meeting_requests WHERE id = $1`, f.requestID)
		_, _ = pool.Exec(bg, `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})
	return f
}

func TestMarriageListMeetingRequestsListsEachRequestOnceWhenProfilesAreDuplicated(t *testing.T) {
	pool := newDupTestPool(t)
	f := seedDupMarriageFixture(t, pool)

	reqs, err := New(pool).ListMeetingRequests(context.Background())
	if err != nil {
		t.Fatalf("ListMeetingRequests: %v", err)
	}
	got := 0
	for _, r := range reqs {
		if r.ID == f.requestID {
			got++
		}
	}
	if got != 1 {
		t.Fatalf("request %d listed %d times, want 1", f.requestID, got)
	}
}

func TestMarriageListAllThreadsListsEachThreadOnceWhenProfilesAreDuplicated(t *testing.T) {
	pool := newDupTestPool(t)
	f := seedDupMarriageFixture(t, pool)

	threads, err := New(pool).ListAllThreads(context.Background(), "")
	if err != nil {
		t.Fatalf("ListAllThreads: %v", err)
	}
	got := 0
	for _, v := range threads {
		if v.ID == f.threadID {
			got++
			if v.RequesterName == nil || *v.RequesterName != "Oldest Profile Name" {
				t.Errorf("RequesterName = %v, want the oldest profile row's name", v.RequesterName)
			}
		}
	}
	if got != 1 {
		t.Fatalf("thread %d listed %d times, want 1", f.threadID, got)
	}
}

func TestMarriageAdminListMessagesListsEachMessageOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	f := seedDupMarriageFixture(t, pool)

	msgs, err := New(pool).AdminListMessages(context.Background(), f.threadID)
	if err != nil {
		t.Fatalf("AdminListMessages: %v", err)
	}
	if len(msgs) != 1 {
		t.Fatalf("got %d messages, want 1", len(msgs))
	}
}
