// chat_group_team_roles_test.go pins the team-group membership rule at the
// HTTP layer (Zaid's decision, 2026-09-16): a team group is for volunteers and
// staff only, so the admin create and add-member routes refuse a donor or
// beneficiary account with 400 team_member_role_not_allowed, and write
// nothing. Masked groups are unaffected and still take any mix.
//
// The store rule and what makes it true (users.role_id and users.staff_tier,
// never the free-text role_in_group) are covered by
// internal/chatgroups/chatgroups_team_roles_test.go. Needs a throwaway
// Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_team_roles
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_team_roles?sslmode=disable' \
//	  go test ./internal/handlers/ -run TeamRole -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
)

// wantTeamMemberRole is the refusal both routes must send. The code is a
// contract with admin-web's locale files: never rename it.
var wantTeamMemberRole = chatGroupRefusal{
	http.StatusBadRequest,
	"team_member_role_not_allowed",
	"A team group can only include volunteers and staff.",
}

// makeChatGroupRoleUser is makeChatGroupUser with a chosen users.role_id:
// 1 donor, 2 beneficiary, 3 volunteer (handlers/registration.go). The plain
// helper always inserts 1, which the team-group rule now refuses.
func makeChatGroupRoleUser(t *testing.T, pool *pgxpool.Pool, name string, roleID int) int64 {
	t.Helper()
	id := makeChatGroupUser(t, pool, name)
	setChatGroupRole(t, pool, id, roleID)
	return id
}

// setChatGroupRole puts roleID on an existing test user, for the helpers that
// build a user some other way (makeChatGroupUserWithoutProfile).
func setChatGroupRole(t *testing.T, pool *pgxpool.Pool, userID int64, roleID int) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`UPDATE users SET role_id = $2 WHERE id = $1`, userID, roleID); err != nil {
		t.Fatalf("set role_id %d on user %d: %v", roleID, userID, err)
	}
}

// TestAdminCreateGroup_TeamRoleRefusesDonor: creating a team group whose
// member list names a donor is refused, and no group is created.
func TestAdminCreateGroup_TeamRoleRefusesDonor(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	donor := makeChatGroupRoleUser(t, pool, "Donor Name", 1)
	token := tokenForStaffUser(t, pool, staff)
	mark := takeChatGroupWriteMark(t, pool)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind":         "team",
		"member_title": "Distribution team",
		"members":      []map[string]any{{"user_id": donor, "role_in_group": "volunteer"}},
	})

	assertChatGroupRefusal(t, code, body, wantTeamMemberRole)
	mark.assertNothingWritten(t, staff, donor)
}

// TestAdminCreateGroup_TeamRoleRefusesBeneficiary: the same for a
// beneficiary account.
func TestAdminCreateGroup_TeamRoleRefusesBeneficiary(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	beneficiary := makeChatGroupRoleUser(t, pool, "Beneficiary Name", 2)
	token := tokenForStaffUser(t, pool, staff)
	mark := takeChatGroupWriteMark(t, pool)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind":         "team",
		"member_title": "Distribution team",
		"members":      []map[string]any{{"user_id": beneficiary, "role_in_group": "staff"}},
	})

	assertChatGroupRefusal(t, code, body, wantTeamMemberRole)
	mark.assertNothingWritten(t, staff, beneficiary)
}

// TestAdminCreateGroup_TeamRoleAcceptsVolunteer: the accounts a team group is
// for still go in, so the rule refuses and nothing more.
func TestAdminCreateGroup_TeamRoleAcceptsVolunteer(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	volunteer := makeChatGroupRoleUser(t, pool, "Volunteer Name", 3)
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, "/api/admin/chat-groups", map[string]any{
		"kind":         "team",
		"member_title": "Distribution team",
		"members":      []map[string]any{{"user_id": volunteer, "role_in_group": "volunteer"}},
	})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	groupID, ok := body["group_id"].(float64)
	if !ok {
		t.Fatalf("no group_id in %v", body)
	}
	removeChatGroupAuditOnCleanup(t, pool, int64(groupID))
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, int64(groupID))
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, int64(groupID))
	})
}

// TestAdminAddMember_TeamRoleRefusesDonor: adding a donor to an existing team
// group is refused, and no membership row is written.
func TestAdminAddMember_TeamRoleRefusesDonor(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	volunteer := makeChatGroupRoleUser(t, pool, "Volunteer Name", 3)
	donor := makeChatGroupRoleUser(t, pool, "Donor Name", 1)
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindTeam,
		[]chatgroups.MemberInput{{UserID: volunteer, RoleInGroup: "volunteer"}})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	token := tokenForStaffUser(t, pool, staff)
	mark := takeChatGroupWriteMark(t, pool)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": donor, "role_in_group": "volunteer"})

	assertChatGroupRefusal(t, code, body, wantTeamMemberRole)
	mark.assertNothingWritten(t, staff, donor)
}

// TestAdminAddMember_MaskedGroupStillTakesADonor: the add-member route for a
// masked group is unchanged — that is where a donor belongs.
func TestAdminAddMember_MaskedGroupStillTakesADonor(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminChatGroupRouter(pool)
	staff := makeChatGroupUser(t, pool, "Staff")
	beneficiary := makeChatGroupRoleUser(t, pool, "Beneficiary Name", 2)
	donor := makeChatGroupRoleUser(t, pool, "Donor Name", 1)
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked,
		[]chatgroups.MemberInput{{UserID: beneficiary, RoleInGroup: "beneficiary"}})
	removeChatGroupAuditOnCleanup(t, pool, groupID)
	token := tokenForStaffUser(t, pool, staff)

	code, body := postAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d/members", groupID),
		map[string]any{"user_id": donor, "role_in_group": "donor"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
}
