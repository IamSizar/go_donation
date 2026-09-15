// chat_guest_reads_test.go proves that a lightweight guest account cannot
// READ the donor ↔ campaign-owner chats or the staff-mediated marriage chats
// (OPOS #26354, the follow-up to #26347). The write routes beside them already
// refused guests, but the read routes had no guest gate at all: a guest token
// that was party to a thread could list it and read its whole history. Nothing
// server-side stopped it — RequireApproved does not, because guests are
// created approved.
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
// group's RequireBearer + RequireApproved, then each chat read's own
// RequireNotGuest, and no guest gate on /support/mine. The gates ARE what is
// under test, same as chat_group_guest_test.go does for the group chats.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_guest_chat_reads
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_guest_chat_reads?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'ChatReads|SupportMine' -v
package handlers

import (
	"fmt"
	"net/http"
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
	participant.GET("/chats", auth.RequireNotGuest(), chatH.List)
	participant.GET("/chats/", auth.RequireNotGuest(), chatH.List)
	participant.GET("/chats/:id/messages", auth.RequireNotGuest(), chatH.Messages)
	participant.GET("/marriage/chats", auth.RequireNotGuest(), marriageH.List)
	participant.GET("/marriage/chats/", auth.RequireNotGuest(), marriageH.List)
	participant.GET("/marriage/chats/:id/messages", auth.RequireNotGuest(), marriageH.Messages)
	// Deliberately no RequireNotGuest — see "WHY SUPPORT STAYS OPEN" above.
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

// seedChatReadFixture puts the guest on a real side of both threads — the
// worst case. If a gate were missing, the messages routes would hand the guest
// the conversation, because being a participant is the only other check those
// handlers make.
func seedChatReadFixture(t *testing.T, pool *pgxpool.Pool) chatReadFixture {
	t.Helper()
	guest := makeGuestUser(t, pool)
	member := makeContactUser(t, pool, "user")
	return chatReadFixture{
		guest:          guest,
		member:         member,
		donorThread:    makeContactThread(t, pool, guest, member),
		marriageThread: insertMarriageChatThread(t, pool, guest, member),
	}
}

// chatReadRoute is one gated participant GET route.
type chatReadRoute struct {
	name string
	path string
}

// chatReadRoutes returns every gated chat read for the fixture's threads. Both
// chat tests below walk this same list, so the guest refusal and the member
// control can never drift apart onto different routes.
func chatReadRoutes(f chatReadFixture) []chatReadRoute {
	return []chatReadRoute{
		{"donor chats list", "/api/chats"},
		{"donor chats list, trailing slash", "/api/chats/"},
		{"donor chat messages", fmt.Sprintf("/api/chats/%d/messages", f.donorThread)},
		{"marriage chats list", "/api/marriage/chats"},
		{"marriage chats list, trailing slash", "/api/marriage/chats/"},
		{"marriage chat messages", fmt.Sprintf("/api/marriage/chats/%d/messages", f.marriageThread)},
	}
}

// ─── A guest may not read donor or marriage chats ───────────────────────

func TestChatReads_RefuseGuest(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatReadRouter(pool)
	f := seedChatReadFixture(t, pool)
	token := tokenForChatGroupUser(t, pool, f.guest)

	for _, route := range chatReadRoutes(f) {
		t.Run(route.name, func(t *testing.T) {
			code, body := getAs(t, r, token, route.path)

			if code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 — a guest must upgrade before reading chats (body %v)", code, body)
			}
			if body["code"] != "guest_restricted" {
				t.Fatalf("code = %v, want \"guest_restricted\" so the app can show its Upgrade Account prompt", body["code"])
			}
		})
	}
}

// ─── A full account still gets through ──────────────────────────────────

// TestChatReads_AllowSignedInParticipant is the control for the test above:
// the same routes, walked by the full account on the other side of the same
// threads, must reach the handler. It pins that the gate refuses guests only.
func TestChatReads_AllowSignedInParticipant(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newChatReadRouter(pool)
	f := seedChatReadFixture(t, pool)
	token := tokenForChatGroupUser(t, pool, f.member)

	for _, route := range chatReadRoutes(f) {
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
