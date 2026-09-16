// chat_trash_direct_restore_test.go — what a chat looks like after it comes
// back out of the Trash (OPOS #26466).
//
// Direct donor↔owner messaging is retired: POST /api/chats/request answers
// 410, and cmd/retire-direct-chats ends and archives every direct thread. The
// Trash was a way around both. A direct thread deleted while it was open came
// back open, so its two participants could carry on in a conversation the
// product had closed. That includes a thread trashed before the retire run,
// which the run never saw.
//
// The owner's decision (2026-09-15) is "restore as closed". A restored direct
// chat comes back ENDED and ARCHIVED, by the retire run's rules and with its
// reason: staff keep the history, and nobody can message in it again. Every
// other chat restores exactly as before, which the last test pins.
//
// Every delete and restore goes through the real routes and their gates, since
// the change lives in those handlers.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_trash_restore
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_trash_restore?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'TestTrashRestore' -v
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"reflect"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// retiredDirectChatReason is the reason cmd/retire-direct-chats stamps on every
// direct thread it ends. Written out rather than read from chatlifecycle: the
// runbook's post-checks match on this exact text (em dash U+2014), so a change
// to it has to fail a test.
const retiredDirectChatReason = "OPOS #25284 Phase 4 — direct donor-owner chat retired"

// trashRestorePast dates every stamp a test sets before the delete, so a stamp
// the restore wrote can never be mistaken for one it kept.
const trashRestorePast = "2026-09-01 10:00:00"

// trashRestoreNull is how readChatThreadState reports a NULL column, so a whole
// row compares with ==.
const trashRestoreNull = "<null>"

// The two staff members' own passwords: the delete and restore routes both
// require the acting staff member to re-enter theirs.
const (
	trashRestoreDeletePassword  = "trash-restore-delete-pin"
	trashRestoreRestorePassword = "trash-restore-restore-pin"
)

// ─── Harness ────────────────────────────────────────────────────────────

// trashRestoreStaff is the staff member who deletes a chat and the one who
// restores it. They are two people, so an assertion that the restorer is
// recorded cannot pass on the deleter's id.
type trashRestoreStaff struct {
	deleterID, restorerID int64
	deleterToken          string
}

// newTrashRestoreStaff creates both as admins, the lowest tier the restore
// route's RequireAdminTier lets through.
func newTrashRestoreStaff(t *testing.T, pool *pgxpool.Pool) trashRestoreStaff {
	t.Helper()
	deleter := insertAccount(t, pool, "admin", trashRestoreDeletePassword)
	restorer := insertAccount(t, pool, "admin", trashRestoreRestorePassword)
	return trashRestoreStaff{
		deleterID:    deleter.id,
		restorerID:   restorer.id,
		deleterToken: tokenFor(t, pool, deleter.id),
	}
}

// deleteThroughRoute deletes f's thread through the dashboard's DELETE route
// and returns the trash entry it produced.
func (s trashRestoreStaff) deleteThroughRoute(t *testing.T, pool *pgxpool.Pool, r *gin.Engine, f chatFixture) int64 {
	t.Helper()
	code, body := doJSON(t, r, http.MethodDelete, adminThreadPath(f.Kind, f.ThreadID), s.deleterToken,
		map[string]string{"password": trashRestoreDeletePassword})
	if code != http.StatusOK || body["trashed"] != true {
		t.Fatalf("delete %s thread %d: status %d body %v", f.Kind, f.ThreadID, code, body)
	}
	return trashEntryFor(t, pool, f.ThreadTable, f.ThreadID)
}

// restoreThroughRoute restores a trash entry through POST
// /api/admin/trash/:id/restore, behind main.go's gates, as the restorer.
func (s trashRestoreStaff) restoreThroughRoute(t *testing.T, pool *pgxpool.Pool, trashID int64) {
	t.Helper()
	status, body := postAsStaff(t, pool, s.restorerID, "/api/admin/trash/:id/restore",
		"/api/admin/trash/"+strconv.FormatInt(trashID, 10)+"/restore",
		map[string]string{"password": trashRestoreRestorePassword},
		auth.RequireAdminTier(), (&AdminTrashHandler{Pool: pool, Perms: permissions.New(pool)}).Restore)
	if status != http.StatusOK {
		t.Fatalf("restore trash entry %d: status %d body %v", trashID, status, body)
	}
}

// chatThreadState is every chat_threads column the retire rules write, as
// text.
type chatThreadState struct {
	Lifecycle, Reason, ChangedAt, ChangedBy, ArchivedAt, ArchivedBy, UpdatedAt string
}

// readChatThreadState reads one chat_threads row's lifecycle and archive stamps.
func readChatThreadState(t *testing.T, pool *pgxpool.Pool, threadID int64) chatThreadState {
	t.Helper()
	var s chatThreadState
	if err := pool.QueryRow(context.Background(), `
		SELECT lifecycle,
		       COALESCE(lifecycle_reason, $2),
		       COALESCE(lifecycle_changed_at::text, $2),
		       COALESCE(lifecycle_changed_by::text, $2),
		       COALESCE(archived_at::text, $2),
		       COALESCE(archived_by::text, $2),
		       updated_at::text
		  FROM chat_threads WHERE id = $1`, threadID, trashRestoreNull,
	).Scan(&s.Lifecycle, &s.Reason, &s.ChangedAt, &s.ChangedBy, &s.ArchivedAt, &s.ArchivedBy, &s.UpdatedAt); err != nil {
		t.Fatalf("read chat_threads/%d: %v", threadID, err)
	}
	return s
}

// chatThreadJSON reads a whole thread row, so "restored exactly as it was" is
// one comparison over every column, including the ones this change never names.
func chatThreadJSON(t *testing.T, pool *pgxpool.Pool, table string, threadID int64) map[string]any {
	t.Helper()
	var raw []byte
	// table is a literal from the fixtures, never a request value.
	if err := pool.QueryRow(context.Background(),
		"SELECT to_jsonb(t.*) FROM "+table+" t WHERE t.id = $1", threadID).Scan(&raw); err != nil {
		t.Fatalf("read %s/%d: %v", table, threadID, err)
	}
	var row map[string]any
	if err := json.Unmarshal(raw, &row); err != nil {
		t.Fatalf("decode %s/%d: %v", table, threadID, err)
	}
	return row
}

// stampChatThread puts a chat_threads row into lifecycle, as set by staffID at
// trashRestorePast, and archives it by staffID at that time too when archived
// is true. updated_at moves to trashRestorePast as well.
func stampChatThread(t *testing.T, pool *pgxpool.Pool, threadID, staffID int64, lifecycle string, archived bool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), `
		UPDATE chat_threads
		   SET lifecycle            = $2::varchar,
		       lifecycle_reason     = CASE WHEN $2::varchar = 'open' THEN NULL ELSE 'set by staff before the delete' END,
		       lifecycle_changed_at = CASE WHEN $2::varchar = 'open' THEN NULL ELSE $4::text::timestamp END,
		       lifecycle_changed_by = CASE WHEN $2::varchar = 'open' THEN NULL ELSE $3::int END,
		       archived_at          = CASE WHEN $5::boolean THEN $4::text::timestamp END,
		       archived_by          = CASE WHEN $5::boolean THEN $3::int END,
		       updated_at           = $4::text::timestamp
		 WHERE id = $1`, threadID, lifecycle, staffID, trashRestorePast, archived); err != nil {
		t.Fatalf("stamp chat_threads/%d as %s (archived %v): %v", threadID, lifecycle, archived, err)
	}
}

// ─── A direct chat comes back closed ────────────────────────────────────

// TestTrashRestore_OpenDirectChatComesBackClosed is the owner's decision end
// to end: an open direct chat with a conversation in it is deleted and
// restored. It must come back ended and archived by the restorer, with the
// retire run's reason. Its history stays with staff, its participants no
// longer see it, and a send into it is refused.
func TestTrashRestore_OpenDirectChatComesBackClosed(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staff := newTrashRestoreStaff(t, pool)
	f := seedDonorChat(t, pool)
	participant := tokenFor(t, pool, f.SenderID)

	// Written straight to the table, not through f.SendPath: the send route
	// now refuses a kind='direct' thread outright (OPOS #25284,
	// chat_direct_kind_gate_test.go). That refusal is the reason this test's
	// subject exists — the Trash was the remaining way back into one — so the
	// fixture must stay direct and its history must be seeded around the gate.
	var lastMessageID int64
	for _, text := range []string{"first message", "second message"} {
		if err := pool.QueryRow(context.Background(),
			`INSERT INTO chat_messages (thread_id, sender_user_id, sender_role, body)
			 VALUES ($1, $2, 1, $3) RETURNING id`, f.ThreadID, f.SenderID, text,
		).Scan(&lastMessageID); err != nil {
			t.Fatalf("seed message %q: %v", text, err)
		}
	}
	// The sender's own read marker, which the send route would have written.
	// This test asserts chat_reads survives the delete/restore round trip, so
	// the row has to exist before the round trip starts.
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO chat_reads (thread_id, user_id, last_read_msg_id) VALUES ($1, $2, $3)`,
		f.ThreadID, f.SenderID, lastMessageID); err != nil {
		t.Fatalf("seed chat_reads: %v", err)
	}
	before := readChatThreadState(t, pool, f.ThreadID)
	if before.Lifecycle != chatlifecycle.StateOpen || before.ArchivedAt != trashRestoreNull {
		t.Fatalf("fixture thread is %+v, want open and not archived; the test would prove nothing", before)
	}

	staff.restoreThroughRoute(t, pool, staff.deleteThroughRoute(t, pool, r, f))

	got := readChatThreadState(t, pool, f.ThreadID)
	restorer := strconv.FormatInt(staff.restorerID, 10)
	want := chatThreadState{
		Lifecycle: chatlifecycle.StateEnded, Reason: retiredDirectChatReason,
		ChangedAt: got.UpdatedAt, ChangedBy: restorer,
		ArchivedAt: got.UpdatedAt, ArchivedBy: restorer,
		UpdatedAt: got.UpdatedAt,
	}
	if got != want {
		t.Fatalf("restored direct chat = %+v\nwant                    %+v\n"+
			"a direct chat must come back ended and archived, or the Trash reopens a retired conversation", got, want)
	}
	if got.UpdatedAt == before.UpdatedAt {
		t.Errorf("updated_at is still %s from before the delete; the restore did not record the retirement", got.UpdatedAt)
	}

	// Staff keep the history.
	if n := countRows(t, pool, "chat_messages", "thread_id", f.ThreadID); n != 2 {
		t.Errorf("restored thread has %d messages, want 2", n)
	}
	if n := countRows(t, pool, "chat_reads", "thread_id", f.ThreadID); n == 0 {
		t.Errorf("chat_reads did not survive the round trip")
	}
	if _, body := doJSON(t, r, http.MethodGet, "/api/admin/chats", staff.deleterToken, nil); !listIDs(t, body)[f.ThreadID] {
		t.Errorf("restored thread %d is missing from the staff list; staff must keep the history", f.ThreadID)
	}

	// Nobody can use it again.
	if _, body := doJSON(t, r, http.MethodGet, "/api/chats", participant, nil); listIDs(t, body)[f.ThreadID] {
		t.Errorf("restored thread %d is back in its participant's list", f.ThreadID)
	}
	if code, body := doJSON(t, r, http.MethodPost, f.SendPath, participant,
		map[string]string{"body": "after the restore"}); code == http.StatusOK {
		t.Errorf("a participant could send into the restored direct chat: status %d body %v", code, body)
	}
	if n := countRows(t, pool, "chat_messages", "thread_id", f.ThreadID); n != 2 {
		t.Errorf("restored thread has %d messages after the refused send, want 2", n)
	}
}

// TestTrashRestore_DirectChatKeepsTheStampsStaffAlreadySet walks the other
// states a direct chat can be trashed in. The retire run's rules decide each:
// an end or archive staff already recorded is kept, and only what is missing
// is added, by the restorer. An ended and archived chat restores byte for byte.
func TestTrashRestore_DirectChatKeepsTheStampsStaffAlreadySet(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staff := newTrashRestoreStaff(t, pool)
	earlier := makeLifecycleUser(t, pool, "supervisor")
	restorer := strconv.FormatInt(staff.restorerID, 10)

	cases := []struct {
		name      string
		lifecycle string
		archived  bool
		// want is the row the restore must leave, from the row before the delete
		// and the restore's own timestamp, which every column it writes carries.
		want func(before chatThreadState, restoredAt string) chatThreadState
	}{
		{"paused: ended and archived by the restorer", chatlifecycle.StatePaused, false,
			func(_ chatThreadState, at string) chatThreadState {
				return chatThreadState{Lifecycle: chatlifecycle.StateEnded, Reason: retiredDirectChatReason,
					ChangedAt: at, ChangedBy: restorer, ArchivedAt: at, ArchivedBy: restorer, UpdatedAt: at}
			}},
		{"open and archived: ended by the restorer, archive stamp kept", chatlifecycle.StateOpen, true,
			func(b chatThreadState, at string) chatThreadState {
				return chatThreadState{Lifecycle: chatlifecycle.StateEnded, Reason: retiredDirectChatReason,
					ChangedAt: at, ChangedBy: restorer, ArchivedAt: b.ArchivedAt, ArchivedBy: b.ArchivedBy, UpdatedAt: at}
			}},
		{"ended and visible: archived by the restorer, end stamp kept", chatlifecycle.StateEnded, false,
			func(b chatThreadState, at string) chatThreadState {
				return chatThreadState{Lifecycle: chatlifecycle.StateEnded, Reason: b.Reason,
					ChangedAt: b.ChangedAt, ChangedBy: b.ChangedBy, ArchivedAt: at, ArchivedBy: restorer, UpdatedAt: at}
			}},
		{"ended and archived: every stamp kept", chatlifecycle.StateEnded, true,
			func(b chatThreadState, _ string) chatThreadState { return b }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := seedDonorChat(t, pool)
			stampChatThread(t, pool, f.ThreadID, earlier, tc.lifecycle, tc.archived)
			before := readChatThreadState(t, pool, f.ThreadID)
			wholeBefore := chatThreadJSON(t, pool, f.ThreadTable, f.ThreadID)

			staff.restoreThroughRoute(t, pool, staff.deleteThroughRoute(t, pool, r, f))

			got := readChatThreadState(t, pool, f.ThreadID)
			want := tc.want(before, got.UpdatedAt)
			if got != want {
				t.Fatalf("restored direct chat = %+v\nwant                    %+v", got, want)
			}
			if want == before {
				// Nothing left to retire, so the restore is the deleted row exactly.
				if after := chatThreadJSON(t, pool, f.ThreadTable, f.ThreadID); !reflect.DeepEqual(after, wholeBefore) {
					t.Fatalf("an ended and archived chat changed in the round trip:\n  before %v\n  after  %v", wholeBefore, after)
				}
				return
			}
			if got.UpdatedAt == before.UpdatedAt {
				t.Errorf("updated_at is still %s from before the delete; the restore did not record the retirement", got.UpdatedAt)
			}
		})
	}
}

// ─── Every other chat is unchanged ──────────────────────────────────────

// TestTrashRestore_OtherChatsComeBackExactlyAsTheyWere pins the other half of
// the decision: only direct chats are closed on the way back. A support chat
// shares chat_threads with the direct ones, and an ended but visible one is the
// state the retire rules would archive if they ignored kind. So both are
// checked, next to one thread of each other chat system, column for column.
func TestTrashRestore_OtherChatsComeBackExactlyAsTheyWere(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staff := newTrashRestoreStaff(t, pool)
	earlier := makeLifecycleUser(t, pool, "supervisor")

	cases := []struct {
		name string
		seed func(t *testing.T) chatFixture
	}{
		{"open support chat", func(t *testing.T) chatFixture { return seedSupportChat(t, pool) }},
		{"ended but visible support chat", func(t *testing.T) chatFixture {
			f := seedSupportChat(t, pool)
			stampChatThread(t, pool, f.ThreadID, earlier, chatlifecycle.StateEnded, false)
			return f
		}},
		{"paused support chat", func(t *testing.T) chatFixture {
			f := seedSupportChat(t, pool)
			stampChatThread(t, pool, f.ThreadID, earlier, chatlifecycle.StatePaused, false)
			return f
		}},
		{"marriage chat", func(t *testing.T) chatFixture { return seedMarriageChat(t, pool) }},
		{"staff chat", func(t *testing.T) chatFixture { return seedStaffChat(t, pool) }},
		{"chat group", func(t *testing.T) chatFixture { return seedGroupChat(t, pool) }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := tc.seed(t)
			before := chatThreadJSON(t, pool, f.ThreadTable, f.ThreadID)

			staff.restoreThroughRoute(t, pool, staff.deleteThroughRoute(t, pool, r, f))

			if after := chatThreadJSON(t, pool, f.ThreadTable, f.ThreadID); !reflect.DeepEqual(after, before) {
				t.Fatalf("%s/%d changed in the round trip:\n  before %v\n  after  %v", f.ThreadTable, f.ThreadID, before, after)
			}
		})
	}
}
