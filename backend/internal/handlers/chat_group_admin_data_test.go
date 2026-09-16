// chat_group_admin_data_test.go — the data the admin dashboard's chat-group
// screens need (part of OPOS #26410), and the proof that none of it reaches a
// member's app.
//
//   - The group detail's roster carries each member's real name, full_name.
//   - The group detail carries lifecycle_reason and is_archived beside
//     lifecycle, the way every other thread read does (mergeChatLifecycle).
//   - The connect-request inbox, list and detail, carries requester_name only
//     when the caller may view sensitive data, resolved per user (user
//     decision D6).
//   - The member routes — GET /api/chat-groups, GET /api/chat-groups/:id/messages
//     and GET /api/chat-groups/connect-requests/mine — still expose no real
//     identity for a masked group, now that the store loads names.
//
// Routers: newAdminGroupReadRouter (chat_group_admin_sensitive_test.go) for the
// admin reads, newWriteChatGroupRouter and newConnectRequestRouter
// (chat_group_test.go) for the member reads. All three wire main.go's chains.
//
// Needs the same throwaway Postgres as chat_group_test.go — see
// newChatGroupPool.
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// ─── Fixtures ────────────────────────────────────────────────────────────

// makeChatGroupUserWithoutProfile creates an approved app user with NO
// user_profiles row: the case in which a roster member's full_name is null.
func makeChatGroupUserWithoutProfile(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	chatGroupUserSeq++
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (phone, role_id, active, registration_status) VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("9647720%06d", chatGroupUserSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert user without profile: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// submitAdminDataRequest files a connect request from requesterID about a
// fresh donation of theirs, and deletes the request on cleanup.
func submitAdminDataRequest(t *testing.T, pool *pgxpool.Pool, requesterID int64) int64 {
	t.Helper()
	donationID := makeChatGroupDonation(t, pool, requesterID)
	id, err := chatgroups.New(pool).SubmitConnectRequest(context.Background(),
		requesterID, "donation", donationID, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit connect request: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_group_connect_requests WHERE id = $1`, id)
	})
	return id
}

// rosterMember finds userID's entry in a group-detail response's roster.
func rosterMember(t *testing.T, body map[string]any, userID int64) map[string]any {
	t.Helper()
	group, _ := body["group"].(map[string]any)
	members, _ := group["members"].([]any)
	for _, m := range members {
		row, _ := m.(map[string]any)
		if id, _ := row["user_id"].(float64); int64(id) == userID {
			return row
		}
	}
	t.Fatalf("user %d not in the roster: %v", userID, body)
	return nil
}

// connectRequestItem finds requestID in a connect-request list response.
func connectRequestItem(t *testing.T, body map[string]any, requestID int64) map[string]any {
	t.Helper()
	items, _ := body["items"].([]any)
	for _, item := range items {
		row, _ := item.(map[string]any)
		if id, _ := row["id"].(float64); int64(id) == requestID {
			return row
		}
	}
	t.Fatalf("request %d not in the inbox list (%d items)", requestID, len(items))
	return nil
}

// assertRequesterName checks one connect-request object against D6: the name
// present when the caller may view sensitive data, and otherwise no key at all
// and no trace of the name anywhere in the raw body.
func assertRequesterName(t *testing.T, request map[string]any, raw, name string, wantName bool) {
	t.Helper()
	got, present := request["requester_name"]
	if wantName {
		if got != name {
			t.Fatalf("requester_name = %v (present %v), want %q", got, present, name)
		}
		return
	}
	if present {
		t.Fatalf("requester_name = %v, want the key omitted for a caller without sensitive_data", got)
	}
	if strings.Contains(raw, name) {
		t.Fatalf("response leaks the requester's name %q: %s", name, raw)
	}
}

// ─── Group detail: names and lifecycle ──────────────────────────────────

// TestAdminGetGroup_RosterCarriesFullName: each roster member carries
// full_name — their profile name, or null when they have no profile.
func TestAdminGetGroup_RosterCarriesFullName(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	creator := makeChatGroupStaffUser(t, pool, "Roster Creator", "admin")
	named := makeChatGroupUser(t, pool, "Roster Donor Real Name")
	unnamed := makeChatGroupUserWithoutProfile(t, pool)
	groupID := makeChatGroup(t, pool, creator, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: named, RoleInGroup: "donor"},
		{UserID: unnamed, RoleInGroup: "beneficiary"},
	})
	_, token := staffActor(t, pool, "Roster Admin", "admin")

	code, raw, body := getRawAdminAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", code, raw)
	}
	if got := rosterMember(t, body, named)["full_name"]; got != "Roster Donor Real Name" {
		t.Fatalf("named member full_name = %v, want \"Roster Donor Real Name\" (body %s)", got, raw)
	}
	got, present := rosterMember(t, body, unnamed)["full_name"]
	if !present || got != nil {
		t.Fatalf("unnamed member full_name = %v (present %v), want null (body %s)", got, present, raw)
	}
}

// TestAdminGetGroup_TeamRosterCarriesFullNameWithoutSensitive: a TEAM group's
// roster carries full_name too — the profile name, or null without a profile —
// and reaches a caller who holds messages:view but not sensitive_data. By D1 a
// team group's members already see each other's real names, so the names are
// no disclosure there.
func TestAdminGetGroup_TeamRosterCarriesFullNameWithoutSensitive(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "employee", sensitive.Module, false)
	requireTierPermission(t, pool, "employee", "messages", true)
	creator := makeChatGroupStaffUser(t, pool, "Team Roster Creator", "admin")
	// Real VOLUNTEER accounts (role_id 3): a team group takes only volunteers
	// and staff, so the plain helper's role_id 1 would be refused.
	named := makeChatGroupRoleUser(t, pool, "Team Volunteer Real Name", 3)
	unnamed := makeChatGroupUserWithoutProfile(t, pool)
	setChatGroupRole(t, pool, unnamed, 3)
	groupID := makeChatGroup(t, pool, creator, chatgroups.KindTeam, []chatgroups.MemberInput{
		{UserID: named, RoleInGroup: "volunteer"},
		{UserID: unnamed, RoleInGroup: "volunteer"},
	})
	_, token := staffActor(t, pool, "Team Roster Employee", "employee")

	code, raw, body := getRawAdminAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", code, raw)
	}
	group, _ := body["group"].(map[string]any)
	if group["kind"] != "team" {
		t.Fatalf("group kind = %v, want \"team\" (body %s)", group["kind"], raw)
	}
	if got := rosterMember(t, body, named)["full_name"]; got != "Team Volunteer Real Name" {
		t.Fatalf("named member full_name = %v, want \"Team Volunteer Real Name\" (body %s)", got, raw)
	}
	got, present := rosterMember(t, body, unnamed)["full_name"]
	if !present || got != nil {
		t.Fatalf("unnamed member full_name = %v (present %v), want null (body %s)", got, present, raw)
	}
}

// TestAdminGetGroup_CarriesLifecycleFields: the detail carries lifecycle,
// lifecycle_reason and is_archived at the top level, the dashboard's lifecycle
// controls' inputs, for an open group and for a paused, archived one.
func TestAdminGetGroup_CarriesLifecycleFields(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	creator := makeChatGroupStaffUser(t, pool, "Lifecycle Creator", "admin")
	donor := makeChatGroupUser(t, pool, "Lifecycle Donor")
	_, token := staffActor(t, pool, "Lifecycle Admin", "admin")
	members := []chatgroups.MemberInput{{UserID: donor, RoleInGroup: "donor"}}

	t.Run("open group", func(t *testing.T) {
		groupID := makeChatGroup(t, pool, creator, chatgroups.KindMasked, members)

		code, raw, body := getRawAdminAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))

		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body %s)", code, raw)
		}
		if body["lifecycle"] != "open" || body["lifecycle_reason"] != "" || body["is_archived"] != false {
			t.Fatalf("lifecycle fields = (%v, %v, %v), want (open, \"\", false) (body %s)",
				body["lifecycle"], body["lifecycle_reason"], body["is_archived"], raw)
		}
	})

	t.Run("paused and archived group", func(t *testing.T) {
		groupID := makeChatGroup(t, pool, creator, chatgroups.KindMasked, members)
		const reason = "Cooling off after a dispute"
		if _, err := pool.Exec(context.Background(),
			`UPDATE chat_group_threads SET lifecycle = 'paused', lifecycle_reason = $2, archived_at = now() WHERE id = $1`,
			groupID, reason); err != nil {
			t.Fatalf("pause and archive group: %v", err)
		}

		code, raw, body := getRawAdminAs(t, r, token, fmt.Sprintf("/api/admin/chat-groups/%d", groupID))

		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body %s)", code, raw)
		}
		if body["lifecycle"] != "paused" || body["lifecycle_reason"] != reason || body["is_archived"] != true {
			t.Fatalf("lifecycle fields = (%v, %v, %v), want (paused, %q, true) (body %s)",
				body["lifecycle"], body["lifecycle_reason"], body["is_archived"], reason, raw)
		}
	})
}

// ─── Connect-request inbox: requester_name (D6) ─────────────────────────

// TestAdminConnectRequests_RequesterNameFollowsPerUserSensitive: the same
// request, read by four callers. Only the two who may view sensitive data —
// resolved per user, so a per-user grant and a per-user revoke both count —
// receive requester_name, on the list and on the detail.
func TestAdminConnectRequests_RequesterNameFollowsPerUserSensitive(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "admin", sensitive.Module, true)
	requireTierPermission(t, pool, "employee", sensitive.Module, false)
	const requesterName = "Inbox Requester Real Name"
	requester := makeChatGroupUser(t, pool, requesterName)
	requestID := submitAdminDataRequest(t, pool, requester)

	_, adminToken := staffActor(t, pool, "Inbox Admin", "admin")
	revokedAdmin, revokedToken := staffActor(t, pool, "Revoked Inbox Admin", "admin")
	denySensitiveForUser(t, pool, revokedAdmin, "admin")
	grantedEmployee, grantedToken := staffActor(t, pool, "Granted Inbox Employee", "employee")
	grantSensitiveForUser(t, pool, grantedEmployee, "employee")
	_, plainToken := staffActor(t, pool, "Plain Inbox Employee", "employee")

	callers := []struct {
		name     string
		token    string
		wantName bool
	}{
		{"admin by tier", adminToken, true},
		{"admin revoked per user", revokedToken, false},
		{"employee granted per user", grantedToken, true},
		{"employee by tier", plainToken, false},
	}
	for _, caller := range callers {
		t.Run(caller.name, func(t *testing.T) {
			t.Run("list", func(t *testing.T) {
				code, raw, body := getRawAdminAs(t, r, caller.token, "/api/admin/chat-groups/connect-requests")
				if code != http.StatusOK {
					t.Fatalf("status = %d, want 200 (body %s)", code, raw)
				}
				assertRequesterName(t, connectRequestItem(t, body, requestID), raw, requesterName, caller.wantName)
			})
			t.Run("detail", func(t *testing.T) {
				code, raw, body := getRawAdminAs(t, r, caller.token,
					fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d", requestID))
				if code != http.StatusOK {
					t.Fatalf("status = %d, want 200 (body %s)", code, raw)
				}
				request, _ := body["request"].(map[string]any)
				assertRequesterName(t, request, raw, requesterName, caller.wantName)
				// The detail's request object is the list item's shape, and the
				// top-level context_label stays for existing callers.
				if label, _ := request["context_label"].(string); label == "" {
					t.Fatalf("request.context_label missing (body %s)", raw)
				}
				if label, _ := body["context_label"].(string); label == "" {
					t.Fatalf("top-level context_label missing (body %s)", raw)
				}
			})
		})
	}
}

// ─── Member routes: still no real identity ──────────────────────────────

// TestChatGroupMemberReads_MaskedGroupLeaksNoRealIdentity walks every member
// read route a masked-group member can call and searches the RAW body for any
// real identity — every member's name, id and phone — and for the admin-only
// keys this work adds or that carry an identity (full_name, members, user_id,
// requester_name, sender_name). The store now loads names for GetGroup and the
// connect-request reads; this is the proof none of them reaches the app.
//
// It adds to TestChatGroupMessages_HTTPResponseNeverLeaksRealIdentity
// (chat_group_test.go), which stays as it is.
func TestChatGroupMemberReads_MaskedGroupLeaksNoRealIdentity(t *testing.T) {
	pool := newChatGroupPool(t)
	mobileRouter, _ := newWriteChatGroupRouter(pool)
	connectRouter, _ := newConnectRequestRouter(pool)
	staff := makeChatGroupStaffUser(t, pool, "Leak Staff Real Name", "supervisor")
	reader := makeChatGroupUser(t, pool, "Leak Reader Real Name")
	other := makeChatGroupUser(t, pool, "Leak Beneficiary Real Name")
	groupID := makeChatGroup(t, pool, staff, chatgroups.KindMasked, []chatgroups.MemberInput{
		{UserID: reader, RoleInGroup: "donor"},
		{UserID: other, RoleInGroup: "beneficiary"},
		{UserID: staff, RoleInGroup: "staff"},
	})
	store := chatgroups.New(pool)
	for sender, body := range map[int64]string{other: "from the beneficiary", staff: "from the case worker"} {
		if _, err := store.PostMessage(context.Background(), groupID, sender, body); err != nil {
			t.Fatalf("seed message from %d: %v", sender, err)
		}
	}
	submitAdminDataRequest(t, pool, reader)
	token := tokenForChatGroupUser(t, pool, reader)

	forbidden := []string{
		"Leak Staff Real Name", "Leak Reader Real Name", "Leak Beneficiary Real Name",
		fmt.Sprintf("%d", staff), fmt.Sprintf("%d", reader), fmt.Sprintf("%d", other),
		lookUpUserPhone(t, pool, staff), lookUpUserPhone(t, pool, reader), lookUpUserPhone(t, pool, other),
		`"full_name"`, `"members"`, `"user_id"`, `"requester_name"`, `"sender_name"`,
	}
	routes := []struct {
		name   string
		router *gin.Engine
		path   string
	}{
		{"group list", mobileRouter, "/api/chat-groups"},
		{"messages", mobileRouter, fmt.Sprintf("/api/chat-groups/%d/messages", groupID)},
		{"my connect requests", connectRouter, "/api/chat-groups/connect-requests/mine"},
	}
	for _, route := range routes {
		t.Run(route.name, func(t *testing.T) {
			code, raw, _ := getRawAdminAs(t, route.router, token, route.path)
			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %s)", code, raw)
			}
			for _, needle := range forbidden {
				if strings.Contains(raw, needle) {
					t.Fatalf("member route leaks %q: %s", needle, raw)
				}
			}
			// The search is only meaningful on a body with the real content in
			// it: the messages route must carry the labels that stand in for
			// the names.
			if route.name == "messages" && (!strings.Contains(raw, "Beneficiary 1") || !strings.Contains(raw, "Support")) {
				t.Fatalf("messages response lacks the masked labels, so the leak search proved nothing: %s", raw)
			}
		})
	}
}
