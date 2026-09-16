// chat_guest_reads_test.go pins what a lightweight guest account gets from the
// donor ↔ campaign-owner chats and the staff-mediated marriage chats (OPOS
// #26354, the follow-up to #26347). Before it, these read routes had no guest
// gate at all: a guest token that was party to a thread could list it and read
// its whole history. Nothing server-side stopped it — RequireApproved does
// not, because guests are created approved.
//
// # WHAT A GUEST GETS
//
//   - The two LIST routes, in both spellings, answer a guest with exactly the
//     successful, empty list a signed-in user with no threads gets
//     (GuestGetsEmptyList). The owner chose this over a 403 because apps
//     already installed on guests' phones fetch and poll GET /api/chats on
//     every dashboard session: a 403 showed them "Unable to load your chats."
//     with a Retry that can never work, where an empty list shows the normal
//     empty state. No thread data reaches the guest either way.
//   - The two MESSAGES routes still refuse a guest with RequireNotGuest's 403
//     guest_restricted. A guest's list is always empty, so the app never offers
//     a guest a thread to open; a direct call is an attempt to read a
//     conversation and is refused outright.
//
// # WHY SUPPORT STAYS OPEN
//
// GET /api/support/mine is deliberately NOT gated, and a test below pins it
// open so a later "gate every guest read" sweep cannot close it by accident.
// The owner's decision was "Block, keep guest support":
//
//   - The Technical Support screen loads /support/mine for EVERY session, a
//     guest's included (humanitarian/lib/modules/support/screens/
//     technical_support_screen.dart, _load). Gating it would turn a guest's
//     ticket list into "Could not load your support requests." with a Retry
//     that can never succeed.
//   - Guests cannot WRITE to support. POST /api/support and POST
//     /api/chats/support refuse them (commit 9d1cde5, pinned by
//     chat_guest_support_test.go), and the screen's send asks a guest to sign
//     in first. So this read only ever shows a guest its own tickets, which is
//     normally none.
//
// newChatReadRouter wires these routes exactly as main.go does: the authed
// group's RequireBearer + RequireApproved, then GuestGetsEmptyList on each list
// route, RequireNotGuest on each messages route, and no guest gate on
// /support/mine. The gates ARE what is under test, same as
// chat_group_guest_test.go does for the group chats.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_guest_chat_reads
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_guest_chat_reads?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'ChatLists|ChatMessages|ChatReads|SupportMine' -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/support"
)

// ─── Harness ────────────────────────────────────────────────────────────

// emptyChatListBody is the exact response ChatHandler.List and
// MarriageChatHandler.List send a signed-in user with no threads: both stores
// start from an empty, non-nil slice, and gin writes map keys in sorted order.
// It is what the installed app parses as "no chats".
const emptyChatListBody = `{"items":[],"success":true}`

// guestLeakCanary is written into a message in each fixture thread. A list
// response that leaked thread data would carry it in last_message.
const guestLeakCanary = "guest-leak-canary"

// newChatReadRouter mounts the participant chat reads and the support read
// behind main.go's chain. Both list routes are registered with and without the
// trailing slash because main.go registers both spellings, and a gate added to
// one but not the other would leave the other open.
func newChatReadRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	n := notify.New(pool)
	chatH := NewChatHandler(chat.New(pool), n, pool)
	marriageH := NewMarriageChatHandler(marriagechat.New(pool), n, pool)
	supportH := NewSupportHandler(support.New(pool), n)

	r := gin.New()
	participant := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)), auth.RequireApproved())
	participant.GET("/chats", GuestGetsEmptyList(), chatH.List)
	participant.GET("/chats/", GuestGetsEmptyList(), chatH.List)
	participant.GET("/chats/:id/messages", auth.RequireNotGuest(), chatH.Messages)
	participant.GET("/marriage/chats", GuestGetsEmptyList(), marriageH.List)
	participant.GET("/marriage/chats/", GuestGetsEmptyList(), marriageH.List)
	participant.GET("/marriage/chats/:id/messages", auth.RequireNotGuest(), marriageH.Messages)
	// Deliberately no guest gate — see "WHY SUPPORT STAYS OPEN" above.
	participant.GET("/support/mine", supportH.Mine)
	return r
}

// chatReadFixture is one guest and one full account who are the two sides of
// a donor chat AND of a marriage chat, so the same pair can walk every read.
type chatReadFixture struct {
	guest          int64
	member         int64
	donorThread    int64
	marriageThread int64
}

// seedChatReadFixture puts the guest on a real side of both threads, each
// holding a message — the worst case. If a gate were missing, the list would
// hand the guest the thread and its last message, and the messages route the
// whole conversation, because being a participant is the only other check
// those handlers make.
func seedChatReadFixture(t *testing.T, pool *pgxpool.Pool) chatReadFixture {
	t.Helper()
	guest := makeGuestUser(t, pool)
	member := makeContactUser(t, pool, "user")
	f := chatReadFixture{
		guest:          guest,
		member:         member,
		donorThread:    makeContactThread(t, pool, guest, member),
		marriageThread: insertMarriageChatThread(t, pool, guest, member),
	}
	seedCanaryMessages(t, pool, f)
	return f
}

// seedCanaryMessages writes one message from the member into each thread. The
// rows are removed by the threads' own cleanups, which delete their messages.
func seedCanaryMessages(t *testing.T, pool *pgxpool.Pool, f chatReadFixture) {
	t.Helper()
	ctx := context.Background()
	// chat_messages.sender_role is a plain INTEGER with no CHECK (migration
	// 012); 1 matches the member's role_id from makeContactUser.
	if _, err := pool.Exec(ctx,
		`INSERT INTO chat_messages (thread_id, sender_user_id, sender_role, body) VALUES ($1, $2, 1, $3)`,
		f.donorThread, f.member, "donor thread "+guestLeakCanary,
	); err != nil {
		t.Fatalf("insert donor chat message: %v", err)
	}
	// The member is the marriage thread's profile owner; migration 058 limits
	// sender_role to requester/owner/staff.
	if _, err := pool.Exec(ctx,
		`INSERT INTO marriage_chat_messages (thread_id, sender_user_id, sender_role, body) VALUES ($1, $2, 'owner', $3)`,
		f.marriageThread, f.member, "marriage thread "+guestLeakCanary,
	); err != nil {
		t.Fatalf("insert marriage chat message: %v", err)
	}
}

// chatReadRoute is one participant GET route and the fixture thread it lists
// or reads.
type chatReadRoute struct {
	name     string
	path     string
	threadID int64
}

// chatListRoutes returns the four list routes. The guest test and the member
// control walk this same list, so they can never drift onto different routes.
func chatListRoutes(f chatReadFixture) []chatReadRoute {
	return []chatReadRoute{
		{"donor chats list", "/api/chats", f.donorThread},
		{"donor chats list, trailing slash", "/api/chats/", f.donorThread},
		{"marriage chats list", "/api/marriage/chats", f.marriageThread},
		{"marriage chats list, trailing slash", "/api/marriage/chats/", f.marriageThread},
	}
}

// chatMessageRoutes returns the two messages routes for the fixture's threads.
func chatMessageRoutes(f chatReadFixture) []chatReadRoute {
	return []chatReadRoute{
		{"donor chat messages", fmt.Sprintf("/api/chats/%d/messages", f.donorThread), f.donorThread},
		{"marriage chat messages", fmt.Sprintf("/api/marriage/chats/%d/messages", f.marriageThread), f.marriageThread},
	}
}

// getRawAs is getAs without the decoding. The guest list assertions compare
// exact bytes, because "no thread data" has to hold for every field.
func getRawAs(t *testing.T, r *gin.Engine, token, path string) (int, string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code, w.Body.String()
}

// ─── A guest gets an empty chat list ────────────────────────────────────

// TestChatLists_GuestGetsEmptyList requires every list route to answer a guest
// who is party to both threads byte-for-byte like the real handler answers a
// signed-in user who has no threads at all.
func TestChatLists_GuestGetsEmptyList(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatReadRouter(pool)
	f := seedChatReadFixture(t, pool)
	guestToken := tokenForChatGroupUser(t, pool, f.guest)
	threadlessToken := tokenForChatGroupUser(t, pool, makeContactUser(t, pool, "user"))

	for _, route := range chatListRoutes(f) {
		t.Run(route.name, func(t *testing.T) {
			// The premise: the handler's own "no chats" answer is the constant.
			if code, body := getRawAs(t, r, threadlessToken, route.path); code != http.StatusOK || body != emptyChatListBody {
				t.Fatalf("a threadless member got %d %s, want 200 %s; the comparison below proves nothing", code, body, emptyChatListBody)
			}

			code, body := getRawAs(t, r, guestToken, route.path)

			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 — installed apps must get their normal empty list, not an error (body %s)", code, body)
			}
			if body != emptyChatListBody {
				t.Fatalf("body = %s, want exactly %s — no thread ids or fields may reach a guest", body, emptyChatListBody)
			}
			if strings.Contains(body, guestLeakCanary) {
				t.Fatalf("a message body reached the guest: %s", body)
			}
		})
	}
}

// ─── A guest may not read a conversation ────────────────────────────────

func TestChatMessages_RefuseGuest(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatReadRouter(pool)
	f := seedChatReadFixture(t, pool)
	token := tokenForChatGroupUser(t, pool, f.guest)

	for _, route := range chatMessageRoutes(f) {
		t.Run(route.name, func(t *testing.T) {
			code, body := getAs(t, r, token, route.path)

			if code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 — a guest must upgrade before reading a chat (body %v)", code, body)
			}
			if body["code"] != "guest_restricted" {
				t.Fatalf("code = %v, want \"guest_restricted\" so the app can show its Upgrade Account prompt", body["code"])
			}
		})
	}
}

// ─── A full account still gets through ──────────────────────────────────

// TestChatReads_AllowSignedInParticipant is the control for both tests above:
// the full account on the other side of the same threads still sees each
// thread in its lists and can read each conversation. It pins that the guards
// act on guests only.
func TestChatReads_AllowSignedInParticipant(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatReadRouter(pool)
	f := seedChatReadFixture(t, pool)
	token := tokenForChatGroupUser(t, pool, f.member)

	for _, route := range chatListRoutes(f) {
		t.Run(route.name, func(t *testing.T) {
			code, body := getAs(t, r, token, route.path)

			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %v)", code, body)
			}
			if !listIDs(t, body)[route.threadID] {
				t.Fatalf("thread %d missing from the member's list — the guest guard hid a full account's chats (body %v)", route.threadID, body)
			}
		})
	}
	for _, route := range chatMessageRoutes(f) {
		t.Run(route.name, func(t *testing.T) {
			code, body := getAs(t, r, token, route.path)

			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 — a full account must reach the handler (body %v)", code, body)
			}
			if body["code"] == "guest_restricted" {
				t.Fatalf("a full account was refused as a guest (body %v)", body)
			}
		})
	}
}

// ─── Support stays open to a guest ──────────────────────────────────────

// TestSupportMine_StaysOpenToGuest pins the support exception described in the
// file header. If this starts failing with 403 guest_restricted, someone gated
// /support/mine: that contradicts the owner's "keep guest support" decision and
// breaks the Technical Support screen for every guest.
func TestSupportMine_StaysOpenToGuest(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatReadRouter(pool)
	guest := makeGuestUser(t, pool)

	code, body := getAs(t, r, tokenForChatGroupUser(t, pool, guest), "/api/support/mine")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — a guest must still be able to load the support screen (body %v)", code, body)
	}
	if body["success"] != true {
		t.Fatalf("success = %v, want true — the support handler itself must answer (body %v)", body["success"], body)
	}
}
