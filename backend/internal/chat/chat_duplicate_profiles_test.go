// chat_duplicate_profiles_test.go — the chat reads must return one row per
// thread, message or contact block even when a participant has two
// user_profiles rows (OPOS #26497).
//
// user_profiles.user_id has no UNIQUE constraint, and three writers used to
// check-then-insert with no lock, so a user can own two rows. A plain
// `LEFT JOIN user_profiles ON user_id = …` then repeats every row it touches.
//
// Integration tests, skipped unless TEST_DATABASE_URL is set (newTestPool in
// chat_test.go).
package chat

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// dupAddTwoProfiles gives userID two user_profiles rows, the older one first.
// users → user_profiles is ON DELETE CASCADE, so makeTestUser's cleanup
// removes them.
func dupAddTwoProfiles(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	for _, name := range []string{"Oldest Profile Name", "Newer Duplicate Profile Name"} {
		if _, err := pool.Exec(context.Background(),
			`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
			userID, name); err != nil {
			t.Fatalf("insert profile %q for user %d: %v", name, userID, err)
		}
	}
}

// dupChatFixture is a direct thread whose owner and assigned staff member
// both have two profile rows, with one message from the owner and one
// contact block from the owner.
type dupChatFixture struct {
	donor, owner, staff, threadID int64
}

func seedDupChatFixture(t *testing.T, pool *pgxpool.Pool) dupChatFixture {
	t.Helper()
	ctx := context.Background()
	f := dupChatFixture{
		donor: makeTestUser(t, pool, "donor"),
		owner: makeTestUser(t, pool, "owner"),
		staff: makeTestUser(t, pool, "staff"),
	}
	dupAddTwoProfiles(t, pool, f.donor)
	dupAddTwoProfiles(t, pool, f.owner)
	dupAddTwoProfiles(t, pool, f.staff)
	if err := pool.QueryRow(ctx, `
		INSERT INTO chat_threads (donor_user_id, owner_user_id, initiated_by, status, kind, assigned_staff_user_id)
		VALUES ($1, $2, $1, 'active', 'direct', $3) RETURNING id`,
		f.donor, f.owner, f.staff).Scan(&f.threadID); err != nil {
		t.Fatalf("insert thread: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_threads WHERE id = $1`, f.threadID)
	})
	if _, err := pool.Exec(ctx, `
		INSERT INTO chat_messages (thread_id, sender_user_id, sender_role, body) VALUES ($1, $2, 1, 'hello once')`,
		f.threadID, f.owner); err != nil {
		t.Fatalf("insert message: %v", err)
	}
	return f
}

func TestChatListThreadsForUserListsEachThreadOnceWhenProfilesAreDuplicated(t *testing.T) {
	pool := newTestPool(t)
	f := seedDupChatFixture(t, pool)

	threads, err := New(pool).ListThreadsForUser(context.Background(), f.donor)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	got := 0
	for _, v := range threads {
		if v.ID == f.threadID {
			got++
		}
	}
	if got != 1 {
		t.Fatalf("thread %d listed %d times, want 1: two profile rows for the owner and the staff member must not repeat it", f.threadID, got)
	}
}

func TestChatListMessagesListsEachMessageOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newTestPool(t)
	f := seedDupChatFixture(t, pool)

	msgs, err := New(pool).ListMessages(context.Background(), f.threadID)
	if err != nil {
		t.Fatalf("ListMessages: %v", err)
	}
	if len(msgs) != 1 {
		t.Fatalf("got %d messages, want 1", len(msgs))
	}
	if msgs[0].SenderName == nil || *msgs[0].SenderName != "Oldest Profile Name" {
		t.Errorf("SenderName = %v, want the oldest profile row's name", msgs[0].SenderName)
	}
}

func TestChatListAllThreadsListsEachThreadOnceWhenProfilesAreDuplicated(t *testing.T) {
	pool := newTestPool(t)
	f := seedDupChatFixture(t, pool)

	threads, err := New(pool).ListAllThreads(context.Background(), "", "direct")
	if err != nil {
		t.Fatalf("ListAllThreads: %v", err)
	}
	got := 0
	for _, v := range threads {
		if v.ID == f.threadID {
			got++
		}
	}
	if got != 1 {
		t.Fatalf("thread %d listed %d times, want 1", f.threadID, got)
	}
}

func TestChatListContactBlocksListsEachBlockOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newTestPool(t)
	f := seedDupChatFixture(t, pool)
	s := New(pool)
	ctx := context.Background()
	if err := s.RecordContactBlock(ctx, f.threadID, f.owner, "phone", 1, "call [redacted]"); err != nil {
		t.Fatalf("RecordContactBlock: %v", err)
	}

	blocks, err := s.ListContactBlocks(ctx, f.threadID)
	if err != nil {
		t.Fatalf("ListContactBlocks: %v", err)
	}
	if len(blocks) != 1 {
		t.Fatalf("got %d contact blocks, want 1", len(blocks))
	}
}
