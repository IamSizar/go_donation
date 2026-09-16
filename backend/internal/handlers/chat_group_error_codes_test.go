// chat_group_error_codes_test.go pins OPOS #26410's error contract for the
// chat-group routes: every refusal chatErr sends carries a stable
// machine-readable "code" beside its English "error" sentence. admin-web
// translates the code (describeError looks up error.<code>) and falls back to
// the sentence, and the Flutter app keeps showing the sentence or its own copy
// exactly as before, so the sentences must not change.
//
// TestChatErr_EveryRefusalCarriesAStableCode covers the whole mapping without
// a database, so it always runs. The route tests after it prove real requests
// reach that mapping; the member and label conflicts have their own file,
// chat_group_conflict_test.go. The route tests need a throwaway Postgres and
// skip unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_error_codes
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_error_codes?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'ChatErr|CarriesItsCode' -v
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// ─── Expected refusals ──────────────────────────────────────────────────

// chatGroupRefusal is one response chatErr must send: the HTTP status, the
// machine code a client keys on, and the English sentence shown when a client
// has no copy of its own for that code.
type chatGroupRefusal struct {
	status  int
	code    string
	message string
}

// Every chat-group refusal, written out once so the mapping test and the route
// tests hold each route to the identical response. The codes are a contract
// with admin-web's locale files: never rename one.
var (
	wantNotGroupMember         = chatGroupRefusal{http.StatusForbidden, "not_group_member", "You are not a member of this group."}
	wantGroupNotFound          = chatGroupRefusal{http.StatusNotFound, "group_not_found", "Group not found."}
	wantConnectRequestDecided  = chatGroupRefusal{http.StatusConflict, "connect_request_decided", "This request has already been decided."}
	wantGroupMemberConflict    = chatGroupRefusal{http.StatusConflict, "group_member_conflict", "This person is already a member of this group."}
	wantGroupLabelConflict     = chatGroupRefusal{http.StatusConflict, "group_label_conflict", "Another member of this group already has this label."}
	wantGuestMemberNotAllowed  = chatGroupRefusal{http.StatusBadRequest, "guest_member_not_allowed", "Guest accounts cannot be added to a chat group."}
	wantGroupLabelContact      = chatGroupRefusal{http.StatusBadRequest, "group_label_contact", "A member label cannot contain a phone number or email address."}
	wantGroupInvalidInput      = chatGroupRefusal{http.StatusBadRequest, "group_invalid_input", "Invalid request."}
	wantConnectContextNotFound = chatGroupRefusal{http.StatusBadRequest, "connect_context_not_found", "We couldn't find that case or donation."}
	wantChatGroupServerError   = chatGroupRefusal{http.StatusInternalServerError, "server_error", "Database error."}
)

// assertChatGroupRefusal checks a decoded response against want.
func assertChatGroupRefusal(t *testing.T, status int, body map[string]any, want chatGroupRefusal) {
	t.Helper()
	if status != want.status {
		t.Fatalf("status = %d, want %d (body %v)", status, want.status, body)
	}
	if body["code"] != want.code {
		t.Errorf("code = %v, want %q (body %v)", body["code"], want.code, body)
	}
	if body["error"] != want.message {
		t.Errorf("error = %v, want the sentence %q", body["error"], want.message)
	}
	if body["success"] != false {
		t.Errorf("success = %v, want false", body["success"])
	}
}

// ─── The mapping ────────────────────────────────────────────────────────

// TestChatErr_EveryRefusalCarriesAStableCode feeds chatErr each store sentinel,
// wrapped the way the store returns it, plus an unrecognised failure.
func TestChatErr_EveryRefusalCarriesAStableCode(t *testing.T) {
	gin.SetMode(gin.TestMode)
	cases := []struct {
		name string
		err  error
		want chatGroupRefusal
	}{
		{"not a member", chatgroups.ErrNotMember, wantNotGroupMember},
		{"group or member not found", chatgroups.ErrNotFound, wantGroupNotFound},
		{"connect request already decided", chatgroups.ErrAlreadyDecided, wantConnectRequestDecided},
		{"already an active member", chatgroups.ErrMemberConflict, wantGroupMemberConflict},
		{"label held by another active member", chatgroups.ErrLabelConflict, wantGroupLabelConflict},
		{"guest account as a member", chatgroups.ErrGuestMember, wantGuestMemberNotAllowed},
		{"donor or beneficiary in a team group", chatgroups.ErrTeamMemberRole, wantTeamMemberRole},
		// ErrLabelContact wraps ErrInvalidInput, so this case also proves the
		// specific code wins over the generic one.
		{"contact details in a label", chatgroups.ErrLabelContact, wantGroupLabelContact},
		{"invalid input", chatgroups.ErrInvalidInput, wantGroupInvalidInput},
		{"unknown connect-request context", chatgroups.ErrUnknownContext, wantConnectContextNotFound},
		{"any other failure", errors.New("connection reset by peer"), wantChatGroupServerError},
	}
	h := &ChatGroupHandler{}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			// A real handler always has its request; chatErr logs from it.
			c.Request = httptest.NewRequest(http.MethodGet, "/api/chat-groups/7/messages", nil)

			h.chatErr(c, fmt.Errorf("chatgroups: group 7: %w", tc.err))

			var body map[string]any
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode %q: %v", w.Body.String(), err)
			}
			assertChatGroupRefusal(t, w.Code, body, tc.want)
		})
	}
}

// ─── Real routes ────────────────────────────────────────────────────────

// chatGroupMissingID names no group: far above any id a test database hands
// out yet a valid BIGINT, so parseID accepts it and the store answers.
const chatGroupMissingID int64 = 8_000_000_000_000_000

// TestChatGroupParticipantRoutes_NotAMemberCarriesItsCode has an outsider read
// and post to a group they were never in.
func TestChatGroupParticipantRoutes_NotAMemberCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	outsider := makeChatGroupUser(t, pool, "Outsider")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	token := tokenForChatGroupUser(t, pool, outsider)
	path := fmt.Sprintf("/api/chat-groups/%d/messages", groupID)

	t.Run("read", func(t *testing.T) {
		code, body := getAs(t, r, token, path)
		assertChatGroupRefusal(t, code, body, wantNotGroupMember)
	})
	t.Run("post", func(t *testing.T) {
		code, body := postAs(t, r, token, path, map[string]string{"body": "hello"})
		assertChatGroupRefusal(t, code, body, wantNotGroupMember)
	})
}

// TestChatGroupRoutes_MissingGroupCarriesItsCode asks three routes about a
// group that does not exist.
func TestChatGroupRoutes_MissingGroupCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	adminRouter, _ := newAdminChatGroupRouter(pool)
	memberRouter, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	member := makeChatGroupUser(t, pool, "Donor Name")
	staffToken := tokenForStaffUser(t, pool, staff)

	t.Run("admin group detail", func(t *testing.T) {
		code, body := getAs(t, adminRouter, staffToken, fmt.Sprintf("/api/admin/chat-groups/%d", chatGroupMissingID))
		assertChatGroupRefusal(t, code, body, wantGroupNotFound)
	})
	t.Run("admin add member", func(t *testing.T) {
		code, body := postAs(t, adminRouter, staffToken, fmt.Sprintf("/api/admin/chat-groups/%d/members", chatGroupMissingID),
			map[string]any{"user_id": member, "role_in_group": "donor"})
		assertChatGroupRefusal(t, code, body, wantGroupNotFound)
	})
	t.Run("participant read", func(t *testing.T) {
		code, body := getAs(t, memberRouter, tokenForChatGroupUser(t, pool, member),
			fmt.Sprintf("/api/chat-groups/%d/messages", chatGroupMissingID))
		assertChatGroupRefusal(t, code, body, wantGroupNotFound)
	})
}

// submitTestConnectRequest files a pending request for requesterID about
// donation 1 (a demo seed row from migrations/001_full_v2.sql) and deletes it
// when the test ends — a refused approval leaves it with no group, so no group
// cleanup reaches it.
func submitTestConnectRequest(t *testing.T, pool *pgxpool.Pool, requesterID int64) int64 {
	t.Helper()
	reqID, err := chatgroups.New(pool).SubmitConnectRequest(context.Background(), requesterID, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit connect request: %v", err)
	}
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(), `DELETE FROM chat_group_connect_requests WHERE id = $1`, reqID); err != nil {
			t.Logf("cleanup: connect request %d: %v", reqID, err)
		}
	})
	return reqID
}

// TestAdminConnectRequest_AlreadyDecidedCarriesItsCode declines a request, then
// tries to approve it and to decline it again.
func TestAdminConnectRequest_AlreadyDecidedCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	reqID := submitTestConnectRequest(t, pool, donor)
	token := tokenForStaffUser(t, pool, staff)
	declinePath := fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/decline", reqID)
	if code, body := postAs(t, r, token, declinePath, map[string]any{"reason": "Not needed."}); code != http.StatusOK {
		t.Fatalf("first decline: status = %d, want 200 (body %v)", code, body)
	}

	t.Run("approve", func(t *testing.T) {
		code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID),
			map[string]any{"kind": "masked", "members": []map[string]any{{"user_id": donor, "role_in_group": "donor"}}})
		assertChatGroupRefusal(t, code, body, wantConnectRequestDecided)
	})
	t.Run("decline again", func(t *testing.T) {
		code, body := postAs(t, r, token, declinePath, map[string]any{"reason": "Still not needed."})
		assertChatGroupRefusal(t, code, body, wantConnectRequestDecided)
	})
}

// TestAdminApproveConnectRequest_InvalidInputCarriesItsCode approves with a
// member list that leaves out the requester, and with an unknown kind. Both are
// refused and the request stays pending.
func TestAdminApproveConnectRequest_InvalidInputCarriesItsCode(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	other := makeChatGroupUser(t, pool, "Beneficiary Name")
	reqID := submitTestConnectRequest(t, pool, donor)
	token := tokenForStaffUser(t, pool, staff)
	path := fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID)

	t.Run("requester missing from members", func(t *testing.T) {
		code, body := postAs(t, r, token, path,
			map[string]any{"kind": "masked", "members": []map[string]any{{"user_id": other, "role_in_group": "beneficiary"}}})
		assertChatGroupRefusal(t, code, body, wantGroupInvalidInput)
	})
	t.Run("unknown kind", func(t *testing.T) {
		code, body := postAs(t, r, token, path,
			map[string]any{"kind": "bogus", "members": []map[string]any{{"user_id": donor, "role_in_group": "donor"}}})
		assertChatGroupRefusal(t, code, body, wantGroupInvalidInput)
	})

	req, err := chatgroups.New(pool).GetConnectRequest(context.Background(), reqID)
	if err != nil {
		t.Fatalf("read request back: %v", err)
	}
	if req.Status != chatgroups.RequestPending {
		t.Errorf("request status = %q after refused approvals, want pending", req.Status)
	}
}
