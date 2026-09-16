// chat_direct_kind_gate_test.go — OPOS #25284's policy on the SEND and ACCEPT
// paths of the donor↔owner chat, which is where it was never enforced.
//
// # WHAT WAS MISSING
//
// The policy is that a donor, a beneficiary or a volunteer never messages
// another one directly. Creation already refuses: chat.Store.RequestThread
// returns chat.ErrDirectChatRetired and the handler maps it to 410 Gone
// (chat_test.go pins that). The one-off retirement run then ended and archived
// every direct thread that already existed.
//
// Neither of those is the send path. POST /api/chats/:id/messages checked the
// caller was a participant, the thread's `status`, and its LIFECYCLE — never
// its `kind`. chatlifecycle/retire.go names the hole in its own header: "Left
// paused, staff could resume one into a working direct chat: sending checks
// lifecycle, never kind." A kind='direct' thread that staff resume — or one
// the production run somehow missed — was postable again, and accepting a
// stale invite on one revived it the same way.
//
// # WHAT THESE TESTS PIN
//
//   - Sending on a kind='direct' thread is refused even when everything else
//     about it is perfect: status 'active', lifecycle 'open', caller a real
//     participant. That is the staff-resume case, reproduced exactly.
//   - Accepting an invite on a kind='direct' thread is refused, and the invite
//     is left pending rather than activated.
//   - READING a direct thread's history still works. The policy retires new
//     messages, not the record of the old ones.
//   - The chats that are NOT retired still post: a support thread (kind
//     'support', the same table) and a marriage thread (its own table).
//
// The refusal shape is deliberately the one creation already uses — 410 Gone
// with chat.ErrDirectChatRetired's English sentence — so a client that handles
// the request refusal handles these too.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_direct_kind
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_direct_kind?sslmode=disable' \
//	  go test ./internal/handlers/ -run DirectKindGate -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// directRetiredMessage is the English sentence POST /api/chats/request has
// answered with since Phase 4 (see ChatHandler.Request). The send and accept
// refusals must be indistinguishable from it.
const directRetiredMessage = "Direct messaging has been retired. Ask staff to connect you instead."

// ─── Harness ────────────────────────────────────────────────────────────

// newDirectKindRouter mounts the four routes these tests exercise with the
// same middleware main.go puts in front of them: the authed group's
// RequireBearer + RequireApproved, plus RequireNotGuest on each one.
func newDirectKindRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	n := notify.New(pool)
	chatH := NewChatHandler(chat.New(pool), n, pool)
	marriageH := NewMarriageChatHandler(marriagechat.New(pool), n, pool)

	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)), auth.RequireApproved())
	authed.POST("/chats/:id/messages", auth.RequireNotGuest(), chatH.PostMessage)
	authed.GET("/chats/:id/messages", auth.RequireNotGuest(), chatH.Messages)
	authed.POST("/chats/:id/accept", auth.RequireNotGuest(), chatH.Accept)
	authed.POST("/marriage/chats/:id/messages", auth.RequireNotGuest(), marriageH.PostMessage)
	return r
}

// seedKindThread inserts one chat_threads row with the given kind and status,
// between two fresh public users, and removes everything it wrote afterwards.
// Returns the thread id, the donor (who is also the initiator) and the owner.
//
// It writes the row directly because there is no longer any code path that
// creates a kind='direct' thread — RequestThread refuses — and reproducing the
// bug requires exactly such a row.
func seedKindThread(t *testing.T, pool *pgxpool.Pool, kind, status string) (threadID, donor, owner int64) {
	t.Helper()
	ctx := context.Background()
	donor = makeLifecycleUser(t, pool, "user")
	owner = makeLifecycleUser(t, pool, "user")
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		 VALUES ($1, $2, $3, $1, $4) RETURNING id`,
		donor, owner, status, kind,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert %s/%s chat thread: %v", kind, status, err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_contact_blocks WHERE thread_id = $1`, threadID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_reads WHERE thread_id = $1`, threadID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_messages WHERE thread_id = $1`, threadID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_threads WHERE id = $1`, threadID)
	})
	return threadID, donor, owner
}

// assertDirectRefusal checks the response is the retirement refusal creation
// already gives: 410 Gone, success false, and the same English sentence.
func assertDirectRefusal(t *testing.T, code int, body map[string]any) {
	t.Helper()
	if code != http.StatusGone {
		t.Fatalf("status = %d, want 410 Gone — the shape POST /api/chats/request already uses (body %v)", code, body)
	}
	if body["error"] != directRetiredMessage {
		t.Fatalf("error = %v, want %q", body["error"], directRetiredMessage)
	}
	if body["success"] != false {
		t.Fatalf("success = %v, want false", body["success"])
	}
}

// ─── Sending ────────────────────────────────────────────────────────────

// The staff-resume case, reproduced exactly: a direct thread that is active
// and lifecycle-open, posted into by a genuine participant. Every check the
// send path had before this fix passes; only the kind refuses it.
func TestDirectKindGate_SendRefusedOnOpenDirectThread(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDirectKindRouter(pool)
	thread, donor, _ := seedKindThread(t, pool, "direct", "active")

	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/messages", thread),
		tokenFor(t, pool, donor), map[string]string{"body": "meet me outside the office"})

	assertDirectRefusal(t, code, body)
	// Nothing stored means nothing pushed — a stored message also fans out an
	// 80-character push preview to the other party.
	if n := countRows(t, pool, "chat_messages", "thread_id", thread); n != 0 {
		t.Fatalf("chat_messages has %d rows after a refused send; want 0", n)
	}
}

// ─── Accepting ──────────────────────────────────────────────────────────

// A stale invite on a direct thread must not be acceptable: accepting flips it
// to active and pushes the initiator "chat accepted", which is a direct chat
// opening by another door.
func TestDirectKindGate_AcceptRefusedOnDirectThread(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDirectKindRouter(pool)
	thread, _, owner := seedKindThread(t, pool, "direct", "pending")

	// The owner is the recipient here: seedKindThread makes the donor the
	// initiator, so this is the one party entitled to accept.
	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", thread),
		tokenFor(t, pool, owner), nil)

	assertDirectRefusal(t, code, body)
	var status string
	if err := pool.QueryRow(context.Background(),
		`SELECT status FROM chat_threads WHERE id = $1`, thread).Scan(&status); err != nil {
		t.Fatalf("read status: %v", err)
	}
	if status != "pending" {
		t.Fatalf("status = %q after a refused accept, want it left \"pending\"", status)
	}
}

// ─── Reading ────────────────────────────────────────────────────────────

// The policy keeps history readable. A participant opening a retired
// conversation must still see what was said — only the composer is closed.
func TestDirectKindGate_ReadingHistoryStillWorks(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDirectKindRouter(pool)
	thread, donor, _ := seedKindThread(t, pool, "direct", "active")
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO chat_messages (thread_id, sender_user_id, sender_role, body)
		 VALUES ($1, $2, 1, 'said before the retirement')`, thread, donor); err != nil {
		t.Fatalf("seed message: %v", err)
	}

	code, body := doJSON(t, r, http.MethodGet, fmt.Sprintf("/api/chats/%d/messages", thread),
		tokenFor(t, pool, donor), nil)

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — retiring the chat must not hide its history (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("got %d messages, want the 1 that was seeded (body %v)", len(items), body)
	}
}

// ─── The chats that are NOT retired ─────────────────────────────────────

// Without this, "refuse everything" would pass every test above. A support
// thread lives on the SAME table and is only told apart by kind, so it is the
// one most easily broken by a gate that reads the table instead of the column.
func TestDirectKindGate_SupportThreadStillPosts(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDirectKindRouter(pool)
	thread, user, _ := seedKindThread(t, pool, "support", "active")

	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/messages", thread),
		tokenFor(t, pool, user), map[string]string{"body": "how do I register for aid?"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — support chat is not retired (body %v)", code, body)
	}
	if n := countRows(t, pool, "chat_messages", "thread_id", thread); n != 1 {
		t.Fatalf("chat_messages has %d rows; want 1", n)
	}
}

// The marriage chat is staff-mediated and has its own table; a gate written
// against chat_threads must not reach it.
func TestDirectKindGate_MarriageThreadStillPosts(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDirectKindRouter(pool)
	requester := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	thread := insertMarriageChatThread(t, pool, requester, owner)

	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/marriage/chats/%d/messages", thread),
		tokenFor(t, pool, requester), map[string]string{"body": "when could we meet?"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — marriage chat is not retired (body %v)", code, body)
	}
	if n := countRows(t, pool, "marriage_chat_messages", "thread_id", thread); n != 1 {
		t.Fatalf("marriage_chat_messages has %d rows; want 1", n)
	}
}
