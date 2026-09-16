// chatgroups_connect_party_test.go — the OTHER PARTY of a connect request, at
// the store: approving a request adds the person the context belongs to as a
// member of the new group, automatically, in the approval's own transaction.
//
// # THE BUG THIS PINS
//
// A donor asked to connect from a beneficiary case and a Super-Admin approved
// it. The group came out with ONE member — the donor — because nothing in the
// flow ever resolved who owns the case, so there was nobody in the group to
// talk to. The client found this on a live deployment.
//
// # THE RULE
//
//   - context_type 'case'     → beneficiary_cases.user_id, the case's owner.
//   - context_type 'donation' → campaigns.owner_user_id of the campaign the
//     donation was made to, when that campaign has an owner. A donation to the
//     general fund (campaign_id NULL) has no other party, and approve then
//     behaves exactly as it did before.
//
// The owner is added whether or not the caller listed them, never twice, and
// an empty members list is approved as the two people the request is about:
// the requester and the owner.
//
// Needs the same throwaway Postgres as chatgroups_test.go — see newTestPool.
package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixtures ────────────────────────────────────────────────────────────

// partyCaseSeq numbers this file's fixture case codes; case_code is UNIQUE and
// other packages insert cases into the same database concurrently, so the code
// carries a package prefix and a nanosecond timestamp as well as a counter.
var partyCaseSeq int64

// makePartyCase inserts a beneficiary_cases row owned by ownerID and deletes
// it on cleanup. beneficiary_cases.user_id is the owning member — the column
// the case's own dashboard and mobile reads filter by
// (internal/dashboard/dashboard.go:250).
func makePartyCase(t *testing.T, pool *pgxpool.Pool, ownerID int64) int64 {
	t.Helper()
	code := fmt.Sprintf("CG-PARTY-%d-%d", time.Now().UnixNano(), atomic.AddInt64(&partyCaseSeq, 1))
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO beneficiary_cases (user_id, case_code, public_title, verification_status)
		VALUES ($1, $2, 'other-party fixture', 'approved')
		RETURNING id`, ownerID, code,
	).Scan(&id); err != nil {
		t.Fatalf("insert case fixture: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, id) })
	return id
}

// makePartyCampaign inserts a campaigns row owned by ownerID (NULL when
// ownerID is 0, which is what an admin-curated campaign looks like) and
// deletes it on cleanup. Every NOT NULL column of the table is given a value.
func makePartyCampaign(t *testing.T, pool *pgxpool.Pool, ownerID int64) int64 {
	t.Helper()
	var owner *int64
	if ownerID != 0 {
		owner = &ownerID
	}
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO campaigns (title, title_ar, description, description_ar, address,
		                       beneficiaries, goal_amount, raised_amount, owner_user_id)
		VALUES ('Other party fixture', 'حملة اختبار', 'fixture', 'وصف', 'Erbil', '10', '1000', '0', $1)
		RETURNING id`, owner,
	).Scan(&id); err != nil {
		t.Fatalf("insert campaign fixture: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM campaigns WHERE id = $1`, id) })
	return id
}

// makePartyDonation inserts a donation by donorID to campaignID (the general
// fund when campaignID is 0) and deletes it on cleanup.
func makePartyDonation(t *testing.T, pool *pgxpool.Pool, donorID, campaignID int64) int64 {
	t.Helper()
	var campaign *int64
	if campaignID != 0 {
		campaign = &campaignID
	}
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO donations (user_id, campaign_id, message, amount, payment_method)
		VALUES ($1, $2, 'other-party fixture', '1000', 'cash')
		RETURNING id`, donorID, campaign,
	).Scan(&id); err != nil {
		t.Fatalf("insert donation fixture: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE id = $1`, id) })
	return id
}

// partyMember is one active chat_group_members row, as these tests read it.
type partyMember struct {
	userID int64
	role   string
	label  string
}

// readPartyMembers lists a group's active members, oldest row first, so a test
// can assert exactly who ended up in the group and under which label.
func readPartyMembers(t *testing.T, pool *pgxpool.Pool, groupID int64) []partyMember {
	t.Helper()
	rows, err := pool.Query(context.Background(), `
		SELECT user_id, role_in_group, COALESCE(masked_label, '')
		  FROM chat_group_members
		 WHERE group_id = $1 AND removed_at IS NULL
		 ORDER BY id`, groupID)
	if err != nil {
		t.Fatalf("read members of group %d: %v", groupID, err)
	}
	defer rows.Close()
	var out []partyMember
	for rows.Next() {
		var m partyMember
		if err := rows.Scan(&m.userID, &m.role, &m.label); err != nil {
			t.Fatalf("scan member: %v", err)
		}
		out = append(out, m)
	}
	return out
}

// submitPartyRequest files a connect request and removes it on cleanup.
func submitPartyRequest(t *testing.T, s *Store, requesterID int64, contextType string, contextID int64) int64 {
	t.Helper()
	reqID, err := s.SubmitConnectRequest(context.Background(), requesterID, contextType, contextID, nil, "please connect me")
	if err != nil {
		t.Fatalf("submit %s connect request: %v", contextType, err)
	}
	t.Cleanup(func() {
		_, _ = s.Pool.Exec(context.Background(), `DELETE FROM chat_group_connect_requests WHERE id = $1`, reqID)
	})
	return reqID
}

// ─── The client's case ───────────────────────────────────────────────────

// TestApproveConnectRequest_AddsCaseOwnerWithNoMembersGiven is the bug the
// client hit, at the store: a donor asks from a beneficiary case, staff
// approve with NO members at all, and the group holds both of them — the donor
// first, then the case's owner, each under the auto-generated label for their
// own account role.
func TestApproveConnectRequest_AddsCaseOwnerWithNoMembersGiven(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "beneficiary")
	reqID := submitPartyRequest(t, s, donor, "case", makePartyCase(t, pool, owner))

	groupID, err := s.ApproveConnectRequest(context.Background(), reqID, KindMasked, "", staff, nil)
	if err != nil {
		t.Fatalf("approve with no members: %v", err)
	}

	got := readPartyMembers(t, pool, groupID)
	want := []partyMember{
		{userID: donor, role: "donor", label: "Donor 1"},
		{userID: owner, role: "beneficiary", label: "Beneficiary 1"},
	}
	if len(got) != len(want) {
		t.Fatalf("members = %+v, want the requester and the case owner", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("member %d = %+v, want %+v", i+1, got[i], want[i])
		}
	}
}

// ─── Every context ───────────────────────────────────────────────────────

// TestApproveConnectRequest_OtherPartyPerContext walks the three shapes a
// context can have: a case (its owner), a donation to a campaign that has an
// owner (that owner), and a donation to the general fund (nobody — approve
// behaves exactly as it did before).
func TestApproveConnectRequest_OtherPartyPerContext(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	for _, tc := range []struct {
		name      string
		context   func(t *testing.T, requester, owner int64) (string, int64)
		wantOwner bool
	}{
		{
			name: "case",
			context: func(t *testing.T, _, owner int64) (string, int64) {
				return "case", makePartyCase(t, pool, owner)
			},
			wantOwner: true,
		},
		{
			name: "donation to an owned campaign",
			context: func(t *testing.T, requester, owner int64) (string, int64) {
				return "donation", makePartyDonation(t, pool, requester, makePartyCampaign(t, pool, owner))
			},
			wantOwner: true,
		},
		{
			name: "donation to the general fund",
			context: func(t *testing.T, requester, _ int64) (string, int64) {
				return "donation", makePartyDonation(t, pool, requester, 0)
			},
			wantOwner: false,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			donor := makeTestUser(t, pool, "donor")
			owner := makeTestUser(t, pool, "beneficiary")
			contextType, contextID := tc.context(t, donor, owner)
			reqID := submitPartyRequest(t, s, donor, contextType, contextID)

			groupID, err := s.ApproveConnectRequest(ctx, reqID, KindMasked, "", staff,
				[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
			if err != nil {
				t.Fatalf("approve: %v", err)
			}

			got := readPartyMembers(t, pool, groupID)
			wantLen := 1
			if tc.wantOwner {
				wantLen = 2
			}
			if len(got) != wantLen {
				t.Fatalf("members = %+v, want %d", got, wantLen)
			}
			if tc.wantOwner && got[1].userID != owner {
				t.Fatalf("second member = %+v, want the owner %d", got[1], owner)
			}
		})
	}
}

// TestApproveConnectRequest_DoesNotAddTheOwnerTwice: the dashboard may well
// send the owner itself (it pre-fills them). The approval must then write ONE
// membership row for them, not fail on the (group_id, user_id) unique rule.
func TestApproveConnectRequest_DoesNotAddTheOwnerTwice(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "beneficiary")
	reqID := submitPartyRequest(t, s, donor, "case", makePartyCase(t, pool, owner))

	groupID, err := s.ApproveConnectRequest(context.Background(), reqID, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: owner, RoleInGroup: "beneficiary", Label: "Case owner"},
	})
	if err != nil {
		t.Fatalf("approve with the owner already listed: %v", err)
	}

	got := readPartyMembers(t, pool, groupID)
	if len(got) != 2 {
		t.Fatalf("members = %+v, want exactly two rows", got)
	}
	// The caller's own row wins: their label is kept, not replaced by an
	// auto-generated one.
	if got[1].userID != owner || got[1].label != "Case owner" {
		t.Fatalf("owner row = %+v, want the caller's own label kept", got[1])
	}
}

// TestApproveConnectRequest_OwnerIsTheRequester: a member asking about their
// OWN case is both parties. One row, no duplicate-member failure.
func TestApproveConnectRequest_OwnerIsTheRequester(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	owner := makeTestUser(t, pool, "beneficiary")
	reqID := submitPartyRequest(t, s, owner, "case", makePartyCase(t, pool, owner))

	groupID, err := s.ApproveConnectRequest(context.Background(), reqID, KindMasked, "", staff, nil)
	if err != nil {
		t.Fatalf("approve a request about the requester's own case: %v", err)
	}

	if got := readPartyMembers(t, pool, groupID); len(got) != 1 || got[0].userID != owner {
		t.Fatalf("members = %+v, want the requester alone", got)
	}
}

// ─── The team-group rule (#137) ──────────────────────────────────────────

// TestApproveConnectRequest_TeamGroupRefusesAnIneligibleOwner: a team group
// takes only volunteers and staff. A case owner who is a beneficiary account
// is exactly who that rule excludes, so the approval is REFUSED by name —
// ErrTeamMemberRole, the same sentinel staff already get when they add such a
// person by hand — rather than silently dropping the other party and
// recreating the one-member group this whole change exists to prevent.
// Nothing is written: the request stays pending.
func TestApproveConnectRequest_TeamGroupRefusesAnIneligibleOwner(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	volunteer := makeTestUser(t, pool, "volunteer")
	owner := makeTestUser(t, pool, "beneficiary")
	reqID := submitPartyRequest(t, s, volunteer, "case", makePartyCase(t, pool, owner))

	_, err := s.ApproveConnectRequest(ctx, reqID, KindTeam, "Case team", staff,
		[]MemberInput{{UserID: volunteer, RoleInGroup: "volunteer"}})

	if !errors.Is(err, ErrTeamMemberRole) {
		t.Fatalf("err = %v, want errors.Is(err, ErrTeamMemberRole)", err)
	}
	req, err := s.GetConnectRequest(ctx, reqID)
	if err != nil {
		t.Fatalf("re-read the request: %v", err)
	}
	if req.Status != RequestPending || req.GroupID != nil {
		t.Fatalf("request = status %q group %v, want it still pending with no group", req.Status, req.GroupID)
	}
}
