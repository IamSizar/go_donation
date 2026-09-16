// chatgroups_guest_test.go pins OPOS #26355: a guest account
// (users.is_guest = TRUE) can never be written into chat_group_members.
//
// Every participant chat-group route refuses guest sessions
// (auth.RequireNotGuest, OPOS #26347), so a guest added to a group would be a
// member who can never read, post or mark read — locked out of a group staff
// believe they are in, with nobody told. The store refuses the add instead,
// with ErrGuestMember, on all three paths that write a membership row:
// CreateGroup, AddMember and ApproveConnectRequest.
//
// Kept apart from chatgroups_test.go (already far past the 500-line cap), the
// same way chatgroups_admin_test.go and chatgroups_audit_test.go are. Shares
// that file's newTestPool, makeTestUser and raiseUserIDFloor helpers. Needs a
// throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_guest_members
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_guest_members?sslmode=disable' \
//	  go test ./internal/chatgroups/ -run Guest -v
package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"sync/atomic"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────

// guestTestUserSeq keeps every guest username this file creates distinct
// within one test process. It is separate from testUserPhoneSeq so adding a
// guest never shifts the phone numbers makeTestUser hands out.
var guestTestUserSeq int64

// makeGuestTestUser inserts a real guest row the way users.InsertGuest does —
// a username and password hash, no phone, is_guest TRUE, already approved —
// and removes it on cleanup.
func makeGuestTestUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	raiseUserIDFloor(t, pool)
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (username, password_hash, role_id, active, staff_tier, is_guest, registration_status)
		 VALUES ($1, 'x', NULL, 1, 'user', TRUE, 'approved') RETURNING id`,
		fmt.Sprintf("cgguest%d", atomic.AddInt64(&guestTestUserSeq, 1)),
	).Scan(&id); err != nil {
		t.Fatalf("insert guest user: %v", err)
	}
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id); err != nil {
			t.Logf("cleanup: deleting guest user %d: %v", id, err)
		}
	})
	return id
}

// memberRowWatermark returns the highest chat_group_members.id written so far.
// Take it just before the call under test, then count with
// membershipRowsSince.
//
// Counting every row a user id has would be unsound here. raiseUserIDFloor
// derives the users sequence from MAX(users.id), which drops once tests delete
// their users, so a later test process can be handed a user id again — and
// earlier tests leave that id's membership rows behind. chat_group_members.id
// is an identity column that is never reused, so the rows above the watermark
// are exactly the rows written after it was taken.
func memberRowWatermark(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`SELECT COALESCE(MAX(id), 0) FROM chat_group_members`,
	).Scan(&id); err != nil {
		t.Fatalf("read membership watermark: %v", err)
	}
	return id
}

// membershipRowsSince counts userID's chat_group_members rows, in any group,
// written after watermark (see memberRowWatermark).
func membershipRowsSince(t *testing.T, pool *pgxpool.Pool, userID, watermark int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_members WHERE user_id = $1 AND id > $2`, userID, watermark,
	).Scan(&n); err != nil {
		t.Fatalf("count memberships for user %d: %v", userID, err)
	}
	return n
}

// connectRequestStatus reads a connect request's status straight from the
// table, bypassing the store method under test.
func connectRequestStatus(t *testing.T, pool *pgxpool.Pool, requestID int64) string {
	t.Helper()
	var status string
	if err := pool.QueryRow(context.Background(),
		`SELECT status FROM chat_group_connect_requests WHERE id = $1`, requestID,
	).Scan(&status); err != nil {
		t.Fatalf("read status of connect request %d: %v", requestID, err)
	}
	return status
}

// removeGroupOnCleanup deletes every row a successfully created test group
// wrote, once the test ends. Registered after the test's users, so it runs
// before their cleanup does.
func removeGroupOnCleanup(t *testing.T, pool *pgxpool.Pool, groupID int64) {
	t.Helper()
	t.Cleanup(func() {
		ctx := context.Background()
		for _, stmt := range []string{
			`DELETE FROM chat_group_connect_requests WHERE group_id = $1`,
			`DELETE FROM chat_group_audit_log WHERE group_id = $1`,
			`DELETE FROM chat_group_members WHERE group_id = $1`,
			`DELETE FROM chat_group_threads WHERE id = $1`,
		} {
			if _, err := pool.Exec(ctx, stmt, groupID); err != nil {
				t.Logf("cleanup: group %d: %q: %v", groupID, stmt, err)
			}
		}
	})
}

// ─── CreateGroup ────────────────────────────────────────────────────────

// TestCreateGroupRefusesGuestMember lists a guest after a full account, for
// both group kinds. The create must fail with ErrGuestMember and roll back
// entirely — the full account, inserted first in the same transaction, must
// not be left behind in a half-built group. The same create without the guest
// then succeeds, so the refusal is about the guest and nothing else.
func TestCreateGroupRefusesGuestMember(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	for _, kind := range []Kind{KindMasked, KindTeam} {
		t.Run(string(kind), func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			// A VOLUNTEER, not a donor: a team group takes only volunteers and
			// staff (ErrTeamMemberRole), and a masked group takes a volunteer
			// just as happily, so one account serves both kinds here and this
			// test stays about the guest rule.
			volunteer := makeTestUser(t, pool, "volunteer")
			guest := makeGuestTestUser(t, pool)
			before := memberRowWatermark(t, pool)

			_, err := s.CreateGroup(ctx, kind, "Distribution team", staff, []MemberInput{
				{UserID: volunteer, RoleInGroup: "volunteer"},
				{UserID: guest, RoleInGroup: "volunteer"},
			})

			if !errors.Is(err, ErrGuestMember) {
				t.Fatalf("CreateGroup with a guest member = %v, want errors.Is(err, ErrGuestMember)", err)
			}
			if n := membershipRowsSince(t, pool, guest, before); n != 0 {
				t.Errorf("guest gained %d membership rows, want 0", n)
			}
			if n := membershipRowsSince(t, pool, volunteer, before); n != 0 {
				t.Errorf("the volunteer gained %d membership rows from the refused create, want 0 — the transaction must roll back", n)
			}

			groupID, err := s.CreateGroup(ctx, kind, "Distribution team", staff, []MemberInput{
				{UserID: volunteer, RoleInGroup: "volunteer"},
			})
			if err != nil {
				t.Fatalf("CreateGroup with only a full account: %v", err)
			}
			removeGroupOnCleanup(t, pool, groupID)
			if n := membershipRowsSince(t, pool, volunteer, before); n != 1 {
				t.Errorf("the volunteer gained %d membership rows, want 1", n)
			}
		})
	}
}

// ─── AddMember ──────────────────────────────────────────────────────────

// TestAddMemberRefusesGuest adds a guest to an existing group. The add must
// fail with ErrGuestMember and write no membership row.
func TestAddMemberRefusesGuest(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	guest := makeGuestTestUser(t, pool)
	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	removeGroupOnCleanup(t, pool, groupID)
	before := memberRowWatermark(t, pool)

	err = s.AddMember(ctx, groupID, MemberInput{UserID: guest, RoleInGroup: "beneficiary"}, staff)

	if !errors.Is(err, ErrGuestMember) {
		t.Fatalf("AddMember with a guest = %v, want errors.Is(err, ErrGuestMember)", err)
	}
	if n := membershipRowsSince(t, pool, guest, before); n != 0 {
		t.Errorf("guest gained %d membership rows, want 0", n)
	}
}

// TestAddMemberAcceptsUpgradedGuest is the control for the test above. A
// guest who upgraded (users.UpgradeGuestPhone flips is_guest to FALSE) is a
// full account from then on and must be accepted — the rule reads the current
// flag, not how the account was first created.
func TestAddMemberAcceptsUpgradedGuest(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	upgraded := makeGuestTestUser(t, pool)
	if _, err := pool.Exec(ctx, `UPDATE users SET is_guest = FALSE WHERE id = $1`, upgraded); err != nil {
		t.Fatalf("upgrade guest: %v", err)
	}
	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	removeGroupOnCleanup(t, pool, groupID)
	before := memberRowWatermark(t, pool)

	if err := s.AddMember(ctx, groupID, MemberInput{UserID: upgraded, RoleInGroup: "beneficiary"}, staff); err != nil {
		t.Fatalf("AddMember with an upgraded account: %v", err)
	}
	if n := membershipRowsSince(t, pool, upgraded, before); n != 1 {
		t.Errorf("upgraded account gained %d membership rows, want 1", n)
	}
}

// ─── ApproveConnectRequest ──────────────────────────────────────────────

// TestApproveConnectRequestRefusesGuestMember approves a full account's
// request but lists a guest as a second member. Approval fails with
// ErrGuestMember and nothing of it sticks: the request stays pending, so staff
// can correct the member list, and no membership row exists. Approving again
// without the guest then works.
func TestApproveConnectRequestRefusesGuestMember(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	guest := makeGuestTestUser(t, pool)
	reqID, err := s.SubmitConnectRequest(ctx, donor, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("SubmitConnectRequest: %v", err)
	}
	before := memberRowWatermark(t, pool)

	_, err = s.ApproveConnectRequest(ctx, reqID, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: guest, RoleInGroup: "beneficiary"},
	})

	if !errors.Is(err, ErrGuestMember) {
		t.Fatalf("ApproveConnectRequest with a guest member = %v, want errors.Is(err, ErrGuestMember)", err)
	}
	if status := connectRequestStatus(t, pool, reqID); status != string(RequestPending) {
		t.Errorf("request status = %q after the refused approval, want pending", status)
	}
	if n := membershipRowsSince(t, pool, guest, before) + membershipRowsSince(t, pool, donor, before); n != 0 {
		t.Errorf("the refused approval wrote %d membership rows, want 0 — the transaction must roll back", n)
	}

	groupID, err := s.ApproveConnectRequest(ctx, reqID, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("ApproveConnectRequest without the guest: %v", err)
	}
	removeGroupOnCleanup(t, pool, groupID)
	if status := connectRequestStatus(t, pool, reqID); status != string(RequestApproved) {
		t.Errorf("request status = %q, want approved", status)
	}
}

// TestApproveConnectRequestRefusesGuestRequester covers a pending request
// whose requester is itself a guest. POST /api/chat-groups/connect-requests is
// behind auth.RequireNotGuest, so a guest cannot file one today, but a request
// filed before that gate existed can still be pending. ApproveConnectRequest
// insists the requester is a member, so approving it would add the guest: it
// must refuse, and leave the request pending so staff can decline it instead.
func TestApproveConnectRequestRefusesGuestRequester(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	guest := makeGuestTestUser(t, pool)
	reqID, err := s.SubmitConnectRequest(ctx, guest, "donation", 1, nil, "please connect me")
	if err != nil {
		t.Fatalf("SubmitConnectRequest: %v", err)
	}
	before := memberRowWatermark(t, pool)

	_, err = s.ApproveConnectRequest(ctx, reqID, KindMasked, "", staff, []MemberInput{
		{UserID: guest, RoleInGroup: "donor"},
	})

	if !errors.Is(err, ErrGuestMember) {
		t.Fatalf("ApproveConnectRequest for a guest requester = %v, want errors.Is(err, ErrGuestMember)", err)
	}
	if n := membershipRowsSince(t, pool, guest, before); n != 0 {
		t.Errorf("guest gained %d membership rows, want 0", n)
	}
	if err := s.DeclineConnectRequest(ctx, reqID, staff, "Please upgrade to a full account first."); err != nil {
		t.Fatalf("declining the refused request must still work: %v", err)
	}
}
