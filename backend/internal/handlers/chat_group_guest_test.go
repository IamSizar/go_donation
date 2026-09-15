// chat_group_guest_test.go proves that a lightweight guest account cannot
// READ the staff-mediated group chats either (OPOS #26347, part of #25284).
// The write routes beside them already refused guests, but the three read
// routes had no guest gate at all: a guest token could list its groups, read a
// group's messages and see its connect requests. Nothing server-side stopped
// it — RequireApproved does not, because guests are created approved.
//
// The routers used here are chat_group_test.go's newChatGroupRouter and
// newConnectRequestRouter, which wire these routes with the same PER-ROUTE
// gates main.go puts on them — the gates ARE what is under test, same as
// chat_guest_support_test.go does for the direct chat. They leave out the
// authed group's RequireApproved (main.go), which a guest passes anyway.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_guest
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_guest?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatGroupReads -v
package handlers

import (
	"fmt"
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// ─── Harness ────────────────────────────────────────────────────────────

// chatGroupReadRoute is one of the three participant GET routes, paired with
// the router that wires it.
type chatGroupReadRoute struct {
	name   string
	router *gin.Engine
	path   string
}

// chatGroupReadRoutes returns every participant read route for groupID. Both
// tests below walk this same list, so the guest refusal and the member
// control can never drift apart onto different routes.
func chatGroupReadRoutes(listRouter, connectRouter *gin.Engine, groupID int64) []chatGroupReadRoute {
	return []chatGroupReadRoute{
		{"list groups", listRouter, "/api/chat-groups"},
		{"read messages", listRouter, fmt.Sprintf("/api/chat-groups/%d/messages", groupID)},
		{"my connect requests", connectRouter, "/api/chat-groups/connect-requests/mine"},
	}
}

// ─── A guest may not read group chats ───────────────────────────────────

// TestChatGroupReads_RefuseGuest makes the guest an actual member of the
// group — the worst case. If the gate were missing, the messages route would
// hand a guest the conversation, because membership is the only other check.
func TestChatGroupReads_RefuseGuest(t *testing.T) {
	pool := newChatGroupPool(t)
	listRouter, _ := newChatGroupRouter(pool)
	connectRouter, _ := newConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	guest := makeGuestUser(t, pool)
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked,
		[]chatgroups.MemberInput{{UserID: guest, RoleInGroup: "donor"}})
	token := tokenForChatGroupUser(t, pool, guest)

	for _, route := range chatGroupReadRoutes(listRouter, connectRouter, groupID) {
		t.Run(route.name, func(t *testing.T) {
			code, body := getAs(t, route.router, token, route.path)

			if code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 — a guest must upgrade before reading group chats (body %v)", code, body)
			}
			if body["code"] != "guest_restricted" {
				t.Fatalf("code = %v, want \"guest_restricted\" so the app shows its Upgrade Account prompt", body["code"])
			}
		})
	}
}

// ─── A full account still gets through ──────────────────────────────────

// TestChatGroupReads_AllowSignedInMember is the control for the test above:
// the same routes, walked by an ordinary approved member, must reach the
// handler. It pins that the guest gate refuses guests only.
func TestChatGroupReads_AllowSignedInMember(t *testing.T) {
	pool := newChatGroupPool(t)
	listRouter, _ := newChatGroupRouter(pool)
	connectRouter, _ := newConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked,
		[]chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForChatGroupUser(t, pool, donor)

	for _, route := range chatGroupReadRoutes(listRouter, connectRouter, groupID) {
		t.Run(route.name, func(t *testing.T) {
			code, body := getAs(t, route.router, token, route.path)

			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 — a full account must reach the handler (body %v)", code, body)
			}
			if body["code"] == "guest_restricted" {
				t.Fatalf("a full account was refused as a guest (body %v)", body)
			}
		})
	}
}
