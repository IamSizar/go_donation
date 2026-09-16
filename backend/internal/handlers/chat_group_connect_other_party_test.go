// chat_group_connect_other_party_test.go — the OTHER PARTY of a connect
// request over HTTP: who the case or campaign behind the request belongs to.
//
// # WHAT THESE PIN
//
//   - GET …/connect-requests and GET …/connect-requests/:id carry
//     other_party_user_id (and other_party_name) for a case request and for a
//     donation to an owned campaign, and carry NEITHER for a donation to the
//     general fund, which has no other party;
//   - other_party_name follows requester_name exactly: present only for a
//     caller who may view sensitive data, resolved per user (decision D6). The
//     ID is NOT gated — see the handler's own comment for why;
//   - the client's case end to end: a donor asks from a beneficiary case,
//     staff approve with NO members typed at all, and the group that opens
//     holds the donor AND the case's owner.
//
// Needs the same throwaway Postgres as chat_group_test.go — see
// newChatGroupPool.
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// The response keys under test, pinned as literals so renaming either is a
// deliberate, visible break for the dashboard rather than a silent one.
const (
	otherPartyIDKey   = "other_party_user_id"
	otherPartyNameKey = "other_party_name"
)

// otherPartyOwnerName is the case/campaign owner's profile name in these
// fixtures. A response that must not name them is searched for it.
const otherPartyOwnerName = "Other Party Owner Name"

// ─── Fixtures ────────────────────────────────────────────────────────────

// makeOtherPartyCampaign inserts a campaigns row owned by ownerID (NULL when
// ownerID is 0) and deletes it on cleanup. campaigns.owner_user_id is the
// column migration 007_campaigns_owner.sql added for exactly this question.
func makeOtherPartyCampaign(t *testing.T, pool *pgxpool.Pool, ownerID int64) int64 {
	t.Helper()
	var owner *int64
	if ownerID != 0 {
		owner = &ownerID
	}
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO campaigns (title, title_ar, description, description_ar, address,
		                       beneficiaries, goal_amount, raised_amount, owner_user_id)
		VALUES ('Other party campaign', 'حملة', 'fixture', 'وصف', 'Erbil', '10', '1000', '0', $1)
		RETURNING id`, owner,
	).Scan(&id); err != nil {
		t.Fatalf("insert campaign fixture: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM campaigns WHERE id = $1`, id) })
	return id
}

// makeCampaignDonation inserts a donation by donorID to campaignID and deletes
// it on cleanup — makeChatGroupDonation's twin for a donation that is not to
// the general fund.
func makeCampaignDonation(t *testing.T, pool *pgxpool.Pool, donorID, campaignID int64) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO donations (user_id, campaign_id, message, amount, payment_method)
		VALUES ($1, $2, 'other-party fixture', '1000', 'cash')
		RETURNING id`, donorID, campaignID,
	).Scan(&id); err != nil {
		t.Fatalf("insert donation fixture: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE id = $1`, id) })
	return id
}

// submitOtherPartyRequest files a connect request for contextType/contextID
// and removes it on cleanup.
func submitOtherPartyRequest(t *testing.T, pool *pgxpool.Pool, requesterID int64, contextType string, contextID int64) int64 {
	t.Helper()
	reqID, err := chatgroups.New(pool).SubmitConnectRequest(context.Background(),
		requesterID, contextType, contextID, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit %s connect request: %v", contextType, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_group_connect_requests WHERE id = $1`, reqID)
	})
	return reqID
}

// otherPartyItem reads one request off both admin reads — the list (found by
// id) and the detail — and returns the two decoded bodies, so every assertion
// below covers both screens instead of just one.
func otherPartyItem(t *testing.T, r *gin.Engine, token string, reqID int64) (list, detail map[string]any) {
	t.Helper()
	listCode, listRaw, listBody := getRawAdminAs(t, r, token, "/api/admin/chat-groups/connect-requests")
	if listCode != http.StatusOK {
		t.Fatalf("list status = %d (body %s)", listCode, listRaw)
	}
	items, _ := listBody["items"].([]any)
	for _, raw := range items {
		item, _ := raw.(map[string]any)
		if id, ok := item["id"].(float64); ok && int64(id) == reqID {
			list = item
		}
	}
	if list == nil {
		t.Fatalf("request %d is not in the inbox listing: %s", reqID, listRaw)
	}
	detailCode, detailRaw, detailBody := getRawAdminAs(t, r, token,
		fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d", reqID))
	if detailCode != http.StatusOK {
		t.Fatalf("detail status = %d (body %s)", detailCode, detailRaw)
	}
	detail, _ = detailBody["request"].(map[string]any)
	if detail == nil {
		t.Fatalf("detail has no request object: %s", detailRaw)
	}
	return list, detail
}

// ─── The other party, per context ────────────────────────────────────────

// TestAdminConnectRequests_OtherPartyPerContext: a case request names the
// case's owner, a donation to an owned campaign names that campaign's owner,
// and a donation to the general fund names nobody — the keys are simply
// absent, and the inbox still lists the request.
func TestAdminConnectRequests_OtherPartyPerContext(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	_, token := staffActor(t, pool, "Super Admin Reader", "super_admin")
	donor := makeChatGroupUser(t, pool, "Donor Name")
	owner := makeChatGroupUser(t, pool, otherPartyOwnerName)

	for _, tc := range []struct {
		name      string
		request   func(t *testing.T) int64
		wantOwner bool
	}{
		{
			name: "case",
			request: func(t *testing.T) int64 {
				return submitOtherPartyRequest(t, pool, donor, "case", makeChatGroupCase(t, pool, owner, "approved"))
			},
			wantOwner: true,
		},
		{
			name: "donation to an owned campaign",
			request: func(t *testing.T) int64 {
				donation := makeCampaignDonation(t, pool, donor, makeOtherPartyCampaign(t, pool, owner))
				return submitOtherPartyRequest(t, pool, donor, "donation", donation)
			},
			wantOwner: true,
		},
		{
			name: "donation to the general fund",
			request: func(t *testing.T) int64 {
				return submitOtherPartyRequest(t, pool, donor, "donation", makeChatGroupDonation(t, pool, donor))
			},
			wantOwner: false,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			reqID := tc.request(t)

			list, detail := otherPartyItem(t, r, token, reqID)

			for where, body := range map[string]map[string]any{"list": list, "detail": detail} {
				id, hasID := body[otherPartyIDKey].(float64)
				name, hasName := body[otherPartyNameKey].(string)
				if !tc.wantOwner {
					if hasID || hasName {
						t.Fatalf("%s: a general-fund donation carries an other party: %v", where, body)
					}
					continue
				}
				if !hasID || int64(id) != owner {
					t.Fatalf("%s: %s = %v, want the owner %d", where, otherPartyIDKey, body[otherPartyIDKey], owner)
				}
				if !hasName || name != otherPartyOwnerName {
					t.Fatalf("%s: %s = %v, want %q", where, otherPartyNameKey, body[otherPartyNameKey], otherPartyOwnerName)
				}
			}
		})
	}
}

// ─── D6: the name follows sensitive_data, the id does not ───────────────

// TestAdminConnectRequests_OtherPartyNameNeedsSensitiveData: an employee whose
// tier does not hold sensitive_data reads the request — with the other party's
// ID, which the dialog needs to pre-fill a member, and WITHOUT their name,
// which it does not. The same employee granted the permission for themselves
// reads the name too, so it is the permission that decides.
func TestAdminConnectRequests_OtherPartyNameNeedsSensitiveData(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newAdminGroupReadRouter(pool)
	requireTierPermission(t, pool, "employee", sensitive.Module, false)
	requireTierPermission(t, pool, "employee", "messages", true)
	donor := makeChatGroupUser(t, pool, "Donor Name")
	owner := makeChatGroupUser(t, pool, otherPartyOwnerName)
	reqID := submitOtherPartyRequest(t, pool, donor, "case", makeChatGroupCase(t, pool, owner, "approved"))

	_, plainToken := staffActor(t, pool, "Plain Employee Party", "employee")
	list, detail := otherPartyItem(t, r, plainToken, reqID)
	for where, body := range map[string]map[string]any{"list": list, "detail": detail} {
		if id, ok := body[otherPartyIDKey].(float64); !ok || int64(id) != owner {
			t.Fatalf("%s: %s = %v, want the owner id %d even without sensitive_data",
				where, otherPartyIDKey, body[otherPartyIDKey], owner)
		}
		if _, ok := body[otherPartyNameKey]; ok {
			t.Fatalf("%s: %s reached staff without sensitive_data: %v", where, otherPartyNameKey, body)
		}
	}

	granted, grantedToken := staffActor(t, pool, "Granted Employee Party", "employee")
	grantSensitiveForUser(t, pool, granted, "employee")
	list, detail = otherPartyItem(t, r, grantedToken, reqID)
	for where, body := range map[string]map[string]any{"list": list, "detail": detail} {
		if name, _ := body[otherPartyNameKey].(string); name != otherPartyOwnerName {
			t.Fatalf("%s: %s = %v, want %q for a granted employee",
				where, otherPartyNameKey, body[otherPartyNameKey], otherPartyOwnerName)
		}
	}
}

// ─── The client's case, end to end ───────────────────────────────────────

// TestAdminApproveConnectRequest_AddsTheCaseOwnerWithNoMembersTyped is exactly
// what the client did: a donor asked to connect from a beneficiary case, staff
// approved it as a masked group WITHOUT typing any members, and the group that
// opened must hold both the donor and the case's owner — not the donor alone,
// with nobody to talk to.
func TestAdminApproveConnectRequest_AddsTheCaseOwnerWithNoMembersTyped(t *testing.T) {
	pool := newChatGroupPool(t)
	r, _ := newAdminConnectRequestRouter(pool)
	staff := makeChatGroupUser(t, pool, "Approving Staff")
	token := tokenForStaffUser(t, pool, staff)
	donor := makeChatGroupUser(t, pool, "Donor Name")
	owner := makeChatGroupUser(t, pool, otherPartyOwnerName)
	reqID := submitOtherPartyRequest(t, pool, donor, "case", makeChatGroupCase(t, pool, owner, "approved"))

	code, body := postAs(t, r, token,
		fmt.Sprintf("/api/admin/chat-groups/connect-requests/%d/approve", reqID),
		map[string]any{"kind": "masked"})

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	groupID, ok := body["group_id"].(float64)
	if !ok {
		t.Fatalf("no group_id in response: %v", body)
	}
	members := readGroupMemberIDs(t, pool, int64(groupID))
	if len(members) != 2 || members[0] != donor || members[1] != owner {
		t.Fatalf("members = %v, want the donor %d and the case owner %d", members, donor, owner)
	}
}

// readGroupMemberIDs lists a group's active members' user ids, oldest row
// first.
func readGroupMemberIDs(t *testing.T, pool *pgxpool.Pool, groupID int64) []int64 {
	t.Helper()
	rows, err := pool.Query(context.Background(),
		`SELECT user_id FROM chat_group_members WHERE group_id = $1 AND removed_at IS NULL ORDER BY id`, groupID)
	if err != nil {
		t.Fatalf("read members of group %d: %v", groupID, err)
	}
	defer rows.Close()
	var out []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			t.Fatalf("scan member: %v", err)
		}
		out = append(out, id)
	}
	return out
}
