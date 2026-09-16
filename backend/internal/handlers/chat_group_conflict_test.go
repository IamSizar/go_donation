// chat_group_conflict_test.go pins OPOS #26410 at the HTTP layer, on the admin
// routes that write members — create group, add member, approve connect
// request:
//   - a person already active in the group → 409 group_member_conflict;
//   - a masked label another active member holds, ignoring case → 409
//     group_label_conflict;
//   - a label carrying a phone number or email → 400 group_label_contact;
//
// each with nothing written. It also pins the user's decision D3: re-adding a
// REMOVED member reactivates their row with its old label and role.
//
// The conflicts used to answer 500 "Database error.", because migration 120's
// unique violations reached chatErr unmapped. The store rules are covered by
// internal/chatgroups/chatgroups_conflict_test.go; the expected responses are
// the want* values in chat_group_error_codes_test.go. Needs a throwaway
// Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_conflicts_http
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_conflicts_http?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'Conflict|Reactivat|ContactDetails' -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"reflect"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// ─── Harness ────────────────────────────────────────────────────────────

// removeChatGroupAuditOnCleanup deletes groupID's chat_group_audit_log rows
// when the test ends. The add-member route writes one on success, and
// makeChatGroup's own cleanup does not reach that table.
func removeChatGroupAuditOnCleanup(t *testing.T, pool *pgxpool.Pool, groupID int64) {
	t.Helper()
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(), `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID); err != nil {
			t.Logf("cleanup: audit rows for group %d: %v", groupID, err)
		}
	})
}

// chatGroupRoster reads groupID's member roster through the admin detail
// route, the way the dashboard sees it.
func chatGroupRoster(t *testing.T, r *gin.Engine, token string, groupID int64) []map[string]any {
	t.Helper()
	code, body := getAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))
	if code != http.StatusOK {
		t.Fatalf("group detail: status = %d, want 200 (body %v)", code, body)
	}
	group, _ := body["group"].(map[string]any)
	raw, _ := group["members"].([]any)
	roster := make([]map[string]any, 0, len(raw))
	for _, entry := range raw {
		member, ok := entry.(map[string]any)
		if !ok {
			t.Fatalf("roster entry %v is not an object", entry)
		}
		roster = append(roster, member)
	}
	return roster
}

// rosterEntriesFor returns userID's entries in roster.
func rosterEntriesFor(roster []map[string]any, userID int64) []map[string]any {
	var entries []map[string]any
	for _, member := range roster {
		if member["user_id"] == float64(userID) {
			entries = append(entries, member)
		}
	}
	return entries
}

// chatGroupWriteMark mirrors internal/chatgroups' writeWatermark: the highest
// thread and membership ids at one moment, so a test can prove a refused
// request wrote nothing afterwards. Identity values are never reused, so
// every row above a mark was written after it.
type chatGroupWriteMark struct {
	pool    *pgxpool.Pool
	threads int64
	members int64
}

// takeChatGroupWriteMark takes a chatGroupWriteMark now.
func takeChatGroupWriteMark(t *testing.T, pool *pgxpool.Pool) chatGroupWriteMark {
	t.Helper()
	var threads int64
	if err := pool.QueryRow(context.Background(),
		`SELECT COALESCE(MAX(id), 0) FROM chat_group_threads`,
	).Scan(&threads); err != nil {
		t.Fatalf("read thread watermark: %v", err)
	}
	return chatGroupWriteMark{pool: pool, threads: threads, members: chatGroupMemberRowWatermark(t, pool)}
}

// assertNothingWritten fails the test if staffID created a group, or any of
// userIDs gained a membership row, since the mark was taken.
func (m chatGroupWriteMark) assertNothingWritten(t *testing.T, staffID int64, userIDs ...int64) {
	t.Helper()
	var threads int
	if err := m.pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_threads WHERE created_by_staff_id = $1 AND id > $2`,
		staffID, m.threads,
	).Scan(&threads); err != nil {
		t.Fatalf("count groups created by staff %d: %v", staffID, err)
	}
	if threads != 0 {
		t.Errorf("staff %d created %d groups despite the refusal, want 0", staffID, threads)
	}
	for _, id := range userIDs {
		if n := chatGroupMembershipRowsSince(t, m.pool, id, m.members); n != 0 {
			t.Errorf("user %d gained %d membership rows despite the refusal, want 0", id, n)
		}
	}
}

// duplicateMembersRequest is a member list that collides with itself, as the
// JSON staff send, with the refusal it must get.
type duplicateMembersRequest struct {
	name string
	body map[string]any
	want chatGroupRefusal
}

// duplicateMembersRequests builds the two collisions for users first and
// second. first is also the requester when the body approves a request.
func duplicateMembersRequests(first, second int64) []duplicateMembersRequest {
	return []duplicateMembersRequest{
		{
			name: "same user twice",
			body: map[string]any{"kind": "masked", "members": []map[string]any{
				{"user_id": first, "role_in_group": "donor"},
				{"user_id": first, "role_in_group": "donor"},
			}},
			want: wantGroupMemberConflict,
		},
		{
			name: "labels differing only in case",
			body: map[string]any{"kind": "masked", "members": []map[string]any{
				{"user_id": first, "role_in_group": "donor", "label": "Case Lead"},
				{"user_id": second, "role_in_group": "beneficiary", "label": "case LEAD"},
			}},
			want: wantGroupLabelConflict,
		},
	}
}

// ─── Conflicts ──────────────────────────────────────────────────────────

// TestAdminAddMember_ActiveMemberIsAConflict adds someone already in the
// group. The roster the dashboard reads is unchanged afterwards.
func TestAdminAddMember_ActiveMemberIsAConflict(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	token := tokenForStaffUser(t, pool, staff)
	before := chatGroupRoster(t, r, token, groupID)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": donor, "role_in_group": "volunteer", "label": "Someone Else"})

	assertChatGroupRefusal(t, code, body, wantGroupMemberConflict)
	if after := chatGroupRoster(t, r, token, groupID); !reflect.DeepEqual(before, after) {
		t.Errorf("roster changed by a refused add:\n before %v\n after  %v", before, after)
	}
}

// TestAdminAddMember_DuplicateLabelIsAConflict gives a new member a label an
// active member holds, differing only in case.
func TestAdminAddMember_DuplicateLabelIsAConflict(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked,
		[]chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor", Label: "Blue Door"}})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	token := tokenForStaffUser(t, pool, staff)
	mark := takeChatGroupWriteMark(t, pool)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": beneficiary, "role_in_group": "beneficiary", "label": "BLUE door"})

	assertChatGroupRefusal(t, code, body, wantGroupLabelConflict)
	mark.assertNothingWritten(t, staff, beneficiary)
}

// TestAdminCreateGroup_DuplicateMembersAreConflicts creates a group whose
// member list collides with itself. No group is created.
func TestAdminCreateGroup_DuplicateMembersAreConflicts(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	first := makeChatGroupUser(t, pool, "Donor Name")
	second := makeChatGroupUser(t, pool, "Beneficiary Name")
	token := tokenForStaffUser(t, pool, staff)

	for _, tc := range duplicateMembersRequests(first, second) {
		t.Run(tc.name, func(t *testing.T) {
			mark := takeChatGroupWriteMark(t, pool)

			code, body := postAs(t, r, token, "/api/admin/chat-groups", tc.body)

			assertChatGroupRefusal(t, code, body, tc.want)
			mark.assertNothingWritten(t, staff, first, second)
		})
	}
}

// TestAdminApproveConnectRequest_DuplicateMembersAreConflicts approves with a
// colliding member list. No group is created and the request stays pending.
func TestAdminApproveConnectRequest_DuplicateMembersAreConflicts(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	requester := makeChatGroupUser(t, pool, "Donor Name")
	second := makeChatGroupUser(t, pool, "Beneficiary Name")
	reqID := submitTestConnectRequest(t, pool, requester)
	token := tokenForStaffUser(t, pool, staff)

	for _, tc := range duplicateMembersRequests(requester, second) {
		t.Run(tc.name, func(t *testing.T) {
			mark := takeChatGroupWriteMark(t, pool)

			code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID), tc.body)

			assertChatGroupRefusal(t, code, body, tc.want)
			mark.assertNothingWritten(t, staff, requester, second)
			req, err := chatgroups.New(pool).GetConnectRequest(context.Background(), reqID)
			if err != nil {
				t.Fatalf("read request back: %v", err)
			}
			if req.Status != chatgroups.RequestPending {
				t.Errorf("request status = %q after the refused approval, want pending", req.Status)
			}
		})
	}
}

// ─── Reactivation (D3) ──────────────────────────────────────────────────

// TestAdminAddMember_ReactivatesRemovedMember removes a member who has spoken
// and adds them back with a different role and label. The roster shows the
// same member entry, active, with its old label and role, and the member can
// read the group again with their old message still attributed to them.
func TestAdminAddMember_ReactivatesRemovedMember(t *testing.T) {
	pool := newChatGroupPool(t)
	adminRouter, _ := newAdminChatGroupRouter(pool)
	memberRouter, _ := newWriteChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	beneficiary := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	store := chatgroups.New(pool)
	ctx := context.Background()
	oldMessageID, err := store.PostMessage(ctx, groupID, donor, "said before being removed")
	if err != nil {
		t.Fatalf("seed message: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)
	original := rosterEntriesFor(chatGroupRoster(t, adminRouter, token, groupID), donor)
	if len(original) != 1 {
		t.Fatalf("donor has %d roster entries before removal, want 1", len(original))
	}
	if err := store.RemoveMember(ctx, groupID, donor, staff); err != nil {
		t.Fatalf("remove member: %v", err)
	}

	code, body := postAs(t, adminRouter, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": donor, "role_in_group": "volunteer", "label": "A Brand New Label"})

	if code != http.StatusOK {
		t.Fatalf("re-add: status = %d, want 200 (body %v)", code, body)
	}
	entries := rosterEntriesFor(chatGroupRoster(t, adminRouter, token, groupID), donor)
	if len(entries) != 1 {
		t.Fatalf("donor has %d roster entries after re-adding, want 1: %v", len(entries), entries)
	}
	got := entries[0]
	if got["id"] != original[0]["id"] {
		t.Errorf("member id = %v, want the original %v — the old row must come back", got["id"], original[0]["id"])
	}
	if _, removed := got["removed_at"]; removed {
		t.Errorf("roster entry still carries removed_at: %v", got)
	}
	if got["masked_label"] != "Donor 1" || got["role_in_group"] != "donor" {
		t.Errorf("label/role = %v/%v, want the kept \"Donor 1\"/\"donor\"", got["masked_label"], got["role_in_group"])
	}
	assertOwnMessageListed(t, memberRouter, tokenForChatGroupUser(t, pool, donor), ownMessage{
		groupID: groupID, messageID: oldMessageID, memberID: got["id"], label: "Donor 1",
	})
}

// ownMessage is a message a member expects to find in their group, attributed
// to themselves.
type ownMessage struct {
	groupID   int64
	messageID int64
	memberID  any
	label     string
}

// assertOwnMessageListed reads want.groupID's messages as the token's member
// and checks want.messageID is there, marked as theirs, under their member id
// and label.
func assertOwnMessageListed(t *testing.T, r *gin.Engine, token string, want ownMessage) {
	t.Helper()
	code, body := getAs(t, r, token, fmt.Sprintf("/api/chat-groups/%d/messages", want.groupID))
	if code != http.StatusOK {
		t.Fatalf("member read: status = %d, want 200 (body %v)", code, body)
	}
	items, _ := body["items"].([]any)
	for _, item := range items {
		message, _ := item.(map[string]any)
		if message["id"] != float64(want.messageID) {
			continue
		}
		if message["sender_member_id"] != want.memberID || message["sender_label"] != want.label || message["is_mine"] != true {
			t.Errorf("message %d = %v, want sender_member_id %v, sender_label %q, is_mine true", want.messageID, message, want.memberID, want.label)
		}
		return
	}
	t.Errorf("message %d is missing from the member's read: %v", want.messageID, items)
}

// TestAdminAddMember_ReactivationRefusedWhenLabelTaken re-adds a removed
// member whose label went to someone else meanwhile. It is a label conflict
// and the member stays removed.
func TestAdminAddMember_ReactivationRefusedWhenLabelTaken(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	first := makeChatGroupUser(t, pool, "Donor Name")
	second := makeChatGroupUser(t, pool, "Second Donor")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked,
		[]chatgroups.MemberInput{{UserID: first, RoleInGroup: "donor", Label: "Blue Door"}})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	store := chatgroups.New(pool)
	ctx := context.Background()
	if err := store.RemoveMember(ctx, groupID, first, staff); err != nil {
		t.Fatalf("remove member: %v", err)
	}
	if err := store.AddMember(ctx, groupID, chatgroups.MemberInput{UserID: second, RoleInGroup: "donor", Label: "blue door"}, staff); err != nil {
		t.Fatalf("give the freed label to someone new: %v", err)
	}
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": first, "role_in_group": "donor"})

	assertChatGroupRefusal(t, code, body, wantGroupLabelConflict)
	entries := rosterEntriesFor(chatGroupRoster(t, r, token, groupID), first)
	if len(entries) != 1 {
		t.Fatalf("original holder has %d roster entries, want 1: %v", len(entries), entries)
	}
	if _, removed := entries[0]["removed_at"]; !removed || entries[0]["masked_label"] != "Blue Door" {
		t.Errorf("original holder = %v, want still removed with label \"Blue Door\"", entries[0])
	}
}

// ─── Contact details in a label ─────────────────────────────────────────

// TestAdminMemberRoutes_ContactDetailsInALabelAreRefused sends a phone number
// and an email as a label through add member and create group.
func TestAdminMemberRoutes_ContactDetailsInALabelAreRefused(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	other := makeChatGroupUser(t, pool, "Beneficiary Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	token := tokenForStaffUser(t, pool, staff)
	labels := []struct{ name, label string }{
		{"phone number", "call me on 07701234567"},
		{"email address", "write to someone@example.com"},
	}

	for _, tc := range labels {
		member := map[string]any{"user_id": other, "role_in_group": "beneficiary", "label": tc.label}
		t.Run("add member/"+tc.name, func(t *testing.T) {
			mark := takeChatGroupWriteMark(t, pool)
			code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID), member)
			assertChatGroupRefusal(t, code, body, wantGroupLabelContact)
			mark.assertNothingWritten(t, staff, other)
		})
		t.Run("create group/"+tc.name, func(t *testing.T) {
			mark := takeChatGroupWriteMark(t, pool)
			code, body := postAs(t, r, token, "/api/admin/chat-groups",
				map[string]any{"kind": "masked", "members": []map[string]any{member}})
			assertChatGroupRefusal(t, code, body, wantGroupLabelContact)
			mark.assertNothingWritten(t, staff, other)
		})
	}
}
