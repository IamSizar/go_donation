// chat_group_guest_member_test.go pins OPOS #26355 at the HTTP layer: staff
// cannot put a guest account into a chat group through any admin route, and
// the refusal carries a machine-readable code the admin dashboard can act on.
//
// The rule itself lives in the store (chatgroups.ErrGuestMember, covered by
// internal/chatgroups/chatgroups_guest_test.go). What is pinned here is what
// the dashboard sees on each of the three routes that add members — create
// group, add member, approve connect request: a 400, the
// "guest_member_not_allowed" code, and nothing written.
//
// The routers are chat_group_test.go's newAdminChatGroupRouter and
// newAdminConnectRequestRouter; the guest row comes from
// chat_guest_support_test.go's makeGuestUser. Needs a throwaway Postgres;
// skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_guest_members_http
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_guest_members_http?sslmode=disable' \
//	  go test ./internal/handlers/ -run GuestMember -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// ─── Harness ────────────────────────────────────────────────────────────

// Expected refusal, spelled out once so every route below is held to the
// identical response.
const (
	guestMemberWantCode  = "guest_member_not_allowed"
	guestMemberWantError = "Guest accounts cannot be added to a chat group."
)

// assertGuestMemberRefused checks the exact response every admin route in this
// file must return when a guest is listed as a member.
func assertGuestMemberRefused(t *testing.T, code int, body map[string]any) {
	t.Helper()
	if code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %v)", code, body)
	}
	if body["code"] != guestMemberWantCode {
		t.Fatalf("code = %v, want %q so the dashboard can explain the refusal (body %v)", body["code"], guestMemberWantCode, body)
	}
	if body["error"] != guestMemberWantError {
		t.Errorf("error = %v, want %q", body["error"], guestMemberWantError)
	}
	if body["success"] != false {
		t.Errorf("success = %v, want false", body["success"])
	}
}

// chatGroupMemberRowWatermark returns the highest chat_group_members.id
// written so far. Take it just before the request under test, then count with
// chatGroupMembershipRowsSince.
//
// Counting every row a user id has would be unsound. `go test ./...` runs
// internal/chatgroups alongside this package against the same database, and
// that package's raiseUserIDFloor can move the shared users sequence backward
// (see chatGroupUserIDFloor's doc comment), so a "new" user may carry an id
// whose membership rows an earlier test left behind. chat_group_members.id is
// an identity column that is never reused, so the rows above the watermark are
// exactly the rows written after it was taken.
func chatGroupMemberRowWatermark(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`SELECT COALESCE(MAX(id), 0) FROM chat_group_members`,
	).Scan(&id); err != nil {
		t.Fatalf("read membership watermark: %v", err)
	}
	return id
}

// chatGroupMembershipRowsSince counts userID's chat_group_members rows, in any
// group, written after watermark (see chatGroupMemberRowWatermark).
func chatGroupMembershipRowsSince(t *testing.T, pool *pgxpool.Pool, userID, watermark int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_members WHERE user_id = $1 AND id > $2`, userID, watermark,
	).Scan(&n); err != nil {
		t.Fatalf("count memberships for user %d: %v", userID, err)
	}
	return n
}

// insertLegacyGuestMembership writes a guest's membership row straight into
// chat_group_members, bypassing the store. The store has refused guests since
// OPOS #26355, but a row written before that fix can still exist in
// production — and it is exactly the worst case the participant routes' guest
// gate has to hold against (see TestChatGroupReads_RefuseGuest). The row is
// removed with its group by makeChatGroup's cleanup.
func insertLegacyGuestMembership(t *testing.T, pool *pgxpool.Pool, groupID, guestID, staffID int64) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id)
		 VALUES ($1, $2, 'donor', TRUE, 'Donor 1', $3)`,
		groupID, guestID, staffID,
	); err != nil {
		t.Fatalf("insert legacy guest membership: %v", err)
	}
}

// ─── Create group ───────────────────────────────────────────────────────

// TestAdminCreateGroup_RefusesGuestMember lists a guest after a full account.
// Neither may end up in a group: the whole create is refused.
func TestAdminCreateGroup_RefusesGuestMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	guest := makeGuestUser(t, pool)
	token := tokenForStaffUser(t, pool, staff)
	before := chatGroupMemberRowWatermark(t, pool)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind": "masked",
		"members": []map[string]any{
			{"user_id": donor, "role_in_group": "donor"},
			{"user_id": guest, "role_in_group": "beneficiary"},
		},
	})

	assertGuestMemberRefused(t, code, body)
	if n := chatGroupMembershipRowsSince(t, pool, guest, before) + chatGroupMembershipRowsSince(t, pool, donor, before); n != 0 {
		t.Errorf("the refused create wrote %d membership rows, want 0", n)
	}
}

// TestAdminCreateGroup_OtherRefusalsCarryNoCode pins that only the guest
// refusal gained a "code" field: the generic invalid-input answer the
// dashboard already handles is unchanged.
func TestAdminCreateGroup_OtherRefusalsCarryNoCode(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind":    "bogus",
		"members": []map[string]any{{"user_id": donor, "role_in_group": "donor"}},
	})

	if code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %v)", code, body)
	}
	if _, has := body["code"]; has {
		t.Errorf("invalid-kind response gained a code field: %v", body)
	}
	if body["error"] != "Invalid request." {
		t.Errorf("error = %v, want the unchanged \"Invalid request.\"", body["error"])
	}
}

// ─── Add member ─────────────────────────────────────────────────────────

// TestAdminAddMember_RefusesGuestMember adds a guest to an existing group. It
// is refused, no membership row is written, and no member_added audit row
// claims otherwise.
func TestAdminAddMember_RefusesGuestMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	guest := makeGuestUser(t, pool)
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(), `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID); err != nil {
			t.Logf("cleanup: audit rows for group %d: %v", groupID, err)
		}
	})
	token := tokenForStaffUser(t, pool, staff)
	before := chatGroupMemberRowWatermark(t, pool)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": guest, "role_in_group": "beneficiary"})

	assertGuestMemberRefused(t, code, body)
	if n := chatGroupMembershipRowsSince(t, pool, guest, before); n != 0 {
		t.Errorf("guest gained %d membership rows, want 0", n)
	}
	var audits int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_audit_log WHERE group_id = $1 AND action = 'member_added'`, groupID,
	).Scan(&audits); err != nil {
		t.Fatalf("count audit rows: %v", err)
	}
	if audits != 0 {
		t.Errorf("found %d member_added audit rows for a refused add, want 0", audits)
	}
}

// ─── Approve connect request ────────────────────────────────────────────

// TestAdminApproveConnectRequest_RefusesGuestMember approves a full account's
// request with a guest listed as a second member. It is refused and the
// request stays pending, so staff can fix the member list and approve again.
func TestAdminApproveConnectRequest_RefusesGuestMember(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	guest := makeGuestUser(t, pool)
	reqID, err := chatgroups.New(pool).SubmitConnectRequest(context.Background(), donor, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)
	before := chatGroupMemberRowWatermark(t, pool)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID),
		map[string]any{
			"kind": "masked",
			"members": []map[string]any{
				{"user_id": donor, "role_in_group": "donor"},
				{"user_id": guest, "role_in_group": "beneficiary"},
			},
		})

	assertGuestMemberRefused(t, code, body)
	req, err := chatgroups.New(pool).GetConnectRequest(context.Background(), reqID)
	if err != nil {
		t.Fatalf("read request back: %v", err)
	}
	if req.Status != chatgroups.RequestPending {
		t.Errorf("request status = %q after the refused approval, want pending", req.Status)
	}
	if n := chatGroupMembershipRowsSince(t, pool, guest, before) + chatGroupMembershipRowsSince(t, pool, donor, before); n != 0 {
		t.Errorf("the refused approval wrote %d membership rows, want 0", n)
	}
}

// TestAdminApproveConnectRequest_RefusesGuestRequester covers a still-pending
// request filed by a guest before POST /api/chat-groups/connect-requests was
// guest-gated. The requester must be a member of the approved group, so the
// approval is refused — and declining it, the dashboard's way out, still works.
func TestAdminApproveConnectRequest_RefusesGuestRequester(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	guest := makeGuestUser(t, pool)
	reqID, err := chatgroups.New(pool).SubmitConnectRequest(context.Background(), guest, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)
	before := chatGroupMemberRowWatermark(t, pool)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID),
		map[string]any{
			"kind":    "masked",
			"members": []map[string]any{{"user_id": guest, "role_in_group": "donor"}},
		})

	assertGuestMemberRefused(t, code, body)
	if n := chatGroupMembershipRowsSince(t, pool, guest, before); n != 0 {
		t.Errorf("guest gained %d membership rows, want 0", n)
	}
	declineCode, declineBody := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/decline", reqID),
		map[string]any{"reason": "Please upgrade to a full account first."})
	if declineCode != http.StatusOK {
		t.Fatalf("decline after the refused approval: status = %d, want 200 (body %v)", declineCode, declineBody)
	}
}
