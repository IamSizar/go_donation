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
	"strings"
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

	// KindCase is deliberately absent: OPOS #25284 Phase 4 retired
	// casevolchat's direct volunteer↔beneficiary messaging entirely, so
	// there is no more case-chats route to archive/list through.
	cases := []struct {
		kind            chatlifecycle.Kind
		fixture         chatFixture
		lifecyclePath   string
		participantList string
		staffList       string
	}{
		// Direct, deliberately: this case checks the STAFF oversight list, and
		// GET /api/admin/chats lists kind='direct' threads unless asked for
		// ?kind=support (chat.Store.ListAllThreads). Nothing here sends a
		// message, so the send refusal on a direct thread (OPOS #25284) does
		// not apply.
		{chatlifecycle.KindDonor, seedDonorChat(t, pool), "/api/admin/chats/%d/lifecycle",
			"/api/chats", "/api/admin/chats"},
		{chatlifecycle.KindMarriage, seedMarriageChat(t, pool), "/api/admin/marriage/chats/%d/lifecycle",
			"/api/marriage/chats", "/api/admin/marriage/chats"},
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

// childCounts renders "table=n" for every child table of a system, so the
// delete/restore round trip is VISIBLE in the test log rather than only
// asserted about — the same reason TestChatLifecycle_PausedThreadRefusesMessage
// prints the refusal a user actually receives. For chat groups, whose tables
// carry no cascade, these three numbers going 2→0→2 are the whole fix.
func childCounts(t *testing.T, pool *pgxpool.Pool, sys chatlifecycle.System, threadID int64) string {
	t.Helper()
	parts := make([]string, 0, len(sys.ChildTables()))
	for _, table := range sys.ChildTables() {
		parts = append(parts, fmt.Sprintf("%s=%d", table, countRows(t, pool, table, sys.ChildIDColumn, threadID)))
	}
	return strings.Join(parts, " ")
}

// adminThreadPath maps a chat system to its ADMIN THREAD-LEVEL URL — the one
// a DELETE goes to, and the stem the /lifecycle routes hang off. Deliberately
// the same map TestChatLifecycle_ParticipantCannotModerate builds, kept here
// so both it and the round-trip test below drive the very routes
// newLifecycleRouter registers.
// KindCase carries no entry here: OPOS #25284 Phase 4 retired casevolchat's
// direct volunteer↔beneficiary messaging entirely, so it is no longer in
// allFixtures and this function is never called with it.
func adminThreadPath(kind chatlifecycle.Kind, threadID int64) string {
	base := map[chatlifecycle.Kind]string{
		chatlifecycle.KindDonor:    "/api/admin/chats/%d",
		chatlifecycle.KindMarriage: "/api/admin/marriage/chats/%d",
		chatlifecycle.KindStaff:    "/api/admin/staff-chats/%d",
		chatlifecycle.KindGroup:    "/api/admin/chat-groups/%d",
	}[kind]
	return fmt.Sprintf(base, threadID)
}

// TestChatLifecycle_DeleteTrashesAndRestoreBringsBackMessages is the reason
// trashChatThread exists at all. The generic trashRow would put an empty
// thread in the Trash; this asserts the conversation survives the round trip.
//
// RUNS AGAINST ALL FIVE SYSTEMS, and that is the point of the test rather
// than a tidy-up. It used to be hardcoded to seedDonorChat, which is exactly
// how a real bug shipped undetected: the donor chat (and marriage, staff and
// case) declare ON DELETE CASCADE on every child table, so deleting the
// thread row alone removed the messages for free. chat_group_* (migration
// 120) declares no foreign keys at all, so for a group that same code deleted
// nothing but the thread — leaving every message, read cursor, contact-block
// and member row live forever, and making the restore fail on a duplicate
// key. A single-system test could not see that, and neither could a sixth
// chat system added tomorrow. This one can.
func TestChatLifecycle_DeleteTrashesAndRestoreBringsBackMessages(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	// The DELETE goes through main.go's delete-password gate, so the staff
	// member needs a password of their own and sends it with the delete,
	// exactly as the dashboard does.
	const staffPassword = "lifecycle-delete-pin"
	staffToken := tokenFor(t, pool, insertAccount(t, pool, "admin", staffPassword).id)

	for _, f := range allFixtures(t, pool) {
		t.Run(string(f.Kind), func(t *testing.T) {
			sys, ok := chatlifecycle.Lookup(f.Kind)
			if !ok {
				t.Fatalf("%s is not a registered chat system", f.Kind)
			}

			// Two real messages, so "restored something" cannot pass for
			// "restored the conversation".
			for _, text := range []string{"first message", "second message"} {
				if code, body := doJSON(t, r, http.MethodPost, f.SendPath, tokenFor(t, pool, f.SenderID),
					map[string]string{"body": text}); code != http.StatusOK {
					t.Fatalf("seed message %q: status %d body %v", text, code, body)
				}
			}
			if n := countRows(t, pool, f.MsgTable, f.MsgIDColumn, f.ThreadID); n != 2 {
				t.Fatalf("seeded %d messages in %s, want 2", n, f.MsgTable)
			}
			t.Logf("before delete: %s", childCounts(t, pool, sys, f.ThreadID))

			code, body := doJSON(t, r, http.MethodDelete, adminThreadPath(f.Kind, f.ThreadID), staffToken,
				map[string]string{"password": staffPassword})
			if code != http.StatusOK || body["trashed"] != true {
				t.Fatalf("delete: status %d body %v", code, body)
			}

			// Gone from the live tables. For four systems the cascade would
			// have done this; for chat groups only trashChatThread's own
			// explicit child delete does, which is what this asserts.
			if n := countRows(t, pool, f.MsgTable, f.MsgIDColumn, f.ThreadID); n != 0 {
				t.Fatalf("%s = %d after delete, want 0 — the messages were not actually deleted", f.MsgTable, n)
			}
			t.Logf("after delete:  %s", childCounts(t, pool, sys, f.ThreadID))
			// …and present in the Trash.
			trashID := trashEntryFor(t, pool, f.ThreadTable, f.ThreadID)

			// Restore it. Called directly rather than through the PIN-gated
			// HTTP route: the subject here is whether the CONVERSATION comes
			// back, and re-testing the password gate that
			// admin_trash_credentials_test.go already covers would only make
			// this test fail for the wrong reason.
			restoreTrashEntry(t, pool, trashID)

			var restoredThread int64
			if err := pool.QueryRow(context.Background(),
				"SELECT id FROM "+f.ThreadTable+" WHERE id = $1", f.ThreadID).Scan(&restoredThread); err != nil {
				t.Fatalf("thread was not restored: %v", err)
			}
			t.Logf("after restore: %s", childCounts(t, pool, sys, f.ThreadID))
			// THE assertion.
			if n := countRows(t, pool, f.MsgTable, f.MsgIDColumn, f.ThreadID); n != 2 {
				t.Fatalf("restored thread has %d messages, want 2 — a thread without its history is not a restore", n)
			}
			// The read cursors came back too, so unread badges are not
			// silently reset. The read table and its FK column come from the
			// registry rather than from a new chatFixture field: chatlifecycle
			// already knows both for every system, and a second copy would be
			// a second thing to keep in step.
			if n := countRows(t, pool, sys.ReadTable, sys.ChildIDColumn, f.ThreadID); n == 0 {
				t.Fatalf("%s did not survive the round trip", sys.ReadTable)
			}
		})
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

// TestAllowedChatChildTablesCoversEveryRestorableTable is the reverse
// direction of the assertion above, and the one that actually catches the
// regression this fix addresses: every chat thread table restorableTables
// promises the operator can come back must ALSO resolve a non-empty child
// table list via allowedChatChildTables, or the row restores as an empty
// shell (the thread reappears, its messages don't) with no error to say so.
//
// case_volunteer_chat_threads is the case that matters here: OPOS #25284
// Phase 4 retired its active routes, which correctly dropped KindCase from
// chatlifecycle.Systems() (Task 3 of that plan) — but a row trashed before
// that deploy is still sitting in the Trash UI, still listed in
// restorableTables, and still expected to restore as a full conversation,
// not just a bare thread row. allowedChatChildTables must keep resolving it
// by walking chatlifecycle.AllSystems(), which — unlike Systems() — never
// drops a retired kind.
//
// Before the fix (allowedChatChildTables walking Systems() instead of
// AllSystems()), this test failed: case_volunteer_chat_threads resolved to
// a nil child-table list. After the fix it passes.
func TestAllowedChatChildTablesCoversEveryRestorableTable(t *testing.T) {
	// Every Kind chatlifecycle knows about, keyed by its thread table, so we
	// can tell a genuine chat-thread table in restorableTables apart from an
	// unrelated one (partners, campaigns, ...) that this function correctly
	// returns nil for.
	knownChatThreadTables := map[string]bool{}
	for _, sys := range chatlifecycle.AllSystems() {
		knownChatThreadTables[sys.ThreadTable] = true
	}

	// KindCase's table must actually be one of the ones AllSystems() still
	// knows about, or this test would not be exercising the retired-kind
	// case it exists to cover.
	if !knownChatThreadTables["case_volunteer_chat_threads"] {
		t.Fatal("case_volunteer_chat_threads is no longer in chatlifecycle.AllSystems() — this test needs updating")
	}

	for table := range restorableTables {
		if !knownChatThreadTables[table] {
			continue // not a chat thread table at all (partners, campaigns, ...)
		}
		children := allowedChatChildTables(table)
		if len(children) == 0 {
			t.Errorf("allowedChatChildTables(%q) = %v, want a non-empty child-table list — "+
				"a row for this table would restore as an empty shell (thread back, messages gone)", table, children)
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
