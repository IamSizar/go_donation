// chat_lifecycle_trash_test.go — the two lifecycle actions whose correctness
// is invisible from the send path: ARCHIVE and DELETE.
//
// ARCHIVE is a staff moderation action that HIDES a thread from the people in
// it while staff keep seeing it on the dashboard. That is two assertions, and
// only asserting one of them is how "archive" quietly becomes "delete".
//
// DELETE has a subtler failure. trashRow, the product's generic delete,
// snapshots ONE row and lets the FK cascade take the children. A chat thread's
// children ARE the conversation. A restore that brings back an empty thread
// looks like it worked, which makes it worse than a restore that fails — so
// the restore test counts the MESSAGES, not the thread.
//
// Shares the harness in chat_lifecycle_test.go. Same database requirement:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatlifecycle?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatLifecycle -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

// listIDs pulls the thread ids out of a `{items:[...]}` response.
func listIDs(t *testing.T, body map[string]any) map[int64]bool {
	t.Helper()
	out := map[int64]bool{}
	items, _ := body["items"].([]any)
	for _, it := range items {
		m, ok := it.(map[string]any)
		if !ok {
			continue
		}
		if f, ok := m["id"].(float64); ok {
			out[int64(f)] = true
		}
	}
	return out
}

// ─── Archive hides from participants, not from staff ────────────────────

// TestChatLifecycle_ArchiveHidesFromParticipantsOnly pins the owner's exact
// intent — "archive from dashboard, hides it from users" — from both sides at
// once, for the three user-facing systems. (Internal staff chat has no
// separate oversight endpoint; its moderation view is the same list with
// ?include_archived=1, covered below.)
func TestChatLifecycle_ArchiveHidesFromParticipantsOnly(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staffToken := tokenFor(t, pool, makeLifecycleUser(t, pool, "admin"))

	cases := []struct {
		kind            chatlifecycle.Kind
		fixture         chatFixture
		lifecyclePath   string
		participantList string
		staffList       string
	}{
		{chatlifecycle.KindDonor, seedDonorChat(t, pool), "/api/admin/chats/%d/lifecycle",
			"/api/chats", "/api/admin/chats"},
		{chatlifecycle.KindMarriage, seedMarriageChat(t, pool), "/api/admin/marriage/chats/%d/lifecycle",
			"/api/marriage/chats", "/api/admin/marriage/chats"},
		{chatlifecycle.KindCase, seedCaseChat(t, pool), "/api/admin/case-chats/%d/lifecycle",
			"/api/case-chats", "/api/admin/case-chats"},
	}

	for _, tc := range cases {
		t.Run(string(tc.kind), func(t *testing.T) {
			id := tc.fixture.ThreadID
			userToken := tokenFor(t, pool, tc.fixture.SenderID)

			// Before: the participant sees it.
			_, body := doJSON(t, r, http.MethodGet, tc.participantList, userToken, nil)
			if !listIDs(t, body)[id] {
				t.Fatalf("participant cannot see thread %d before archiving; the test proves nothing", id)
			}

			code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf(tc.lifecyclePath, id),
				staffToken, map[string]string{"action": "archive"})
			if code != http.StatusOK || body["is_archived"] != true {
				t.Fatalf("archive: status %d body %v", code, body)
			}

			// After: gone for the participant …
			_, body = doJSON(t, r, http.MethodGet, tc.participantList, userToken, nil)
			if listIDs(t, body)[id] {
				t.Fatalf("archived thread %d is still in the participant's list", id)
			}
			// … and still there for staff, who have to be able to un-archive it.
			_, body = doJSON(t, r, http.MethodGet, tc.staffList, staffToken, nil)
			if !listIDs(t, body)[id] {
				t.Fatalf("archived thread %d vanished from the STAFF list too — archive is not delete", id)
			}

			// Un-archive puts it back exactly as it was.
			code, body = doJSON(t, r, http.MethodPost, fmt.Sprintf(tc.lifecyclePath, id),
				staffToken, map[string]string{"action": "unarchive"})
			if code != http.StatusOK || body["is_archived"] != false {
				t.Fatalf("unarchive: status %d body %v", code, body)
			}
			_, body = doJSON(t, r, http.MethodGet, tc.participantList, userToken, nil)
			if !listIDs(t, body)[id] {
				t.Fatalf("thread %d did not come back to the participant after un-archiving", id)
			}
		})
	}
}

// The internal staff chat's own version of the same rule: hidden from the
// people in it, findable by a moderator through ?include_archived=1.
func TestChatLifecycle_ArchivedStaffChatNeedsTheModerationFlag(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staffToken := tokenFor(t, pool, makeLifecycleUser(t, pool, "admin"))
	f := seedStaffChat(t, pool)
	participantToken := tokenFor(t, pool, f.SenderID)

	if code, body := doJSON(t, r, http.MethodPost,
		fmt.Sprintf("/api/admin/staff-chats/%d/lifecycle", f.ThreadID),
		staffToken, map[string]string{"action": "archive"}); code != http.StatusOK {
		t.Fatalf("archive: status %d body %v", code, body)
	}

	_, body := doJSON(t, r, http.MethodGet, "/api/admin/staff-chats", participantToken, nil)
	if listIDs(t, body)[f.ThreadID] {
		t.Fatalf("archived staff thread %d is still in its participant's inbox", f.ThreadID)
	}
	_, body = doJSON(t, r, http.MethodGet, "/api/admin/staff-chats?include_archived=1", participantToken, nil)
	if !listIDs(t, body)[f.ThreadID] {
		t.Fatalf("archived staff thread %d is unreachable even with include_archived=1", f.ThreadID)
	}
}

// ─── Delete → Trash → Restore, with the messages intact ─────────────────

// TestChatLifecycle_DeleteTrashesAndRestoreBringsBackMessages is the reason
// trashChatThread exists at all. The generic trashRow would put an empty
// thread in the Trash; this asserts the conversation survives the round trip.
func TestChatLifecycle_DeleteTrashesAndRestoreBringsBackMessages(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staffToken := tokenFor(t, pool, makeLifecycleUser(t, pool, "admin"))
	f := seedDonorChat(t, pool)

	// Two real messages, so "restored something" cannot pass for "restored
	// the conversation".
	for _, text := range []string{"first message", "second message"} {
		if code, body := doJSON(t, r, http.MethodPost, f.SendPath, tokenFor(t, pool, f.SenderID),
			map[string]string{"body": text}); code != http.StatusOK {
			t.Fatalf("seed message %q: status %d body %v", text, code, body)
		}
	}
	if n := countRows(t, pool, "chat_messages", f.ThreadID); n != 2 {
		t.Fatalf("seeded %d messages, want 2", n)
	}

	code, body := doJSON(t, r, http.MethodDelete, fmt.Sprintf("/api/admin/chats/%d", f.ThreadID), staffToken, nil)
	if code != http.StatusOK || body["trashed"] != true {
		t.Fatalf("delete: status %d body %v", code, body)
	}

	// Gone from the live tables — the cascade took the messages with it.
	if n := countRows(t, pool, "chat_messages", f.ThreadID); n != 0 {
		t.Fatalf("chat_messages = %d after delete, want 0", n)
	}
	// …and present in the Trash.
	trashID := trashEntryFor(t, pool, "chat_threads", f.ThreadID)

	// Restore it. Called directly rather than through the PIN-gated HTTP
	// route: the subject here is whether the CONVERSATION comes back, and
	// re-testing the password gate that admin_trash_credentials_test.go
	// already covers would only make this test fail for the wrong reason.
	restoreTrashEntry(t, pool, trashID)

	var restoredThread int64
	if err := pool.QueryRow(context.Background(),
		`SELECT id FROM chat_threads WHERE id = $1`, f.ThreadID).Scan(&restoredThread); err != nil {
		t.Fatalf("thread was not restored: %v", err)
	}
	// THE assertion.
	if n := countRows(t, pool, "chat_messages", f.ThreadID); n != 2 {
		t.Fatalf("restored thread has %d messages, want 2 — a thread without its history is not a restore", n)
	}
	// The read cursors came back too, so unread badges are not silently reset.
	if n := countRows(t, pool, "chat_reads", f.ThreadID); n == 0 {
		t.Fatalf("chat_reads did not survive the round trip")
	}
}

// Every one of the four thread tables must be restorable, or a delete would
// be a one-way trip the operator was told was reversible.
func TestChatLifecycle_AllFourThreadTablesAreRestorable(t *testing.T) {
	for _, sys := range chatlifecycle.Systems() {
		if !restorableTables[sys.ThreadTable] {
			t.Errorf("%s is trashed but missing from restorableTables — it could never come back", sys.ThreadTable)
		}
	}
}

// ─── Small helpers, kept out of the tests above for readability ─────────

func trashEntryFor(t *testing.T, pool *pgxpool.Pool, table string, rowID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`SELECT id FROM trash_items WHERE source_table = $1 AND row_id = $2 AND restored_at IS NULL`,
		table, rowID).Scan(&id); err != nil {
		t.Fatalf("no trash entry for %s/%d: %v", table, rowID, err)
	}
	return id
}

// restoreTrashEntry replays exactly what AdminTrashHandler.Restore does after
// its password check: re-insert the parent, then restoreChatChildren.
func restoreTrashEntry(t *testing.T, pool *pgxpool.Pool, trashID int64) {
	t.Helper()
	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var table string
	var payload []byte
	if err := tx.QueryRow(ctx,
		`SELECT source_table, payload FROM trash_items WHERE id = $1`, trashID).Scan(&table, &payload); err != nil {
		t.Fatalf("read trash entry: %v", err)
	}
	if !restorableTables[table] {
		t.Fatalf("%s is not restorable", table)
	}
	if _, err := tx.Exec(ctx,
		"INSERT INTO "+table+" SELECT * FROM jsonb_populate_record(NULL::"+table+", $1::jsonb)",
		payload); err != nil {
		t.Fatalf("restore parent row: %v", err)
	}
	if err := restoreChatChildren(ctx, tx, table, payload); err != nil {
		t.Fatalf("restore children: %v", err)
	}
	if _, err := tx.Exec(ctx, `UPDATE trash_items SET restored_at = NOW() WHERE id = $1`, trashID); err != nil {
		t.Fatalf("mark restored: %v", err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatalf("commit: %v", err)
	}
}
