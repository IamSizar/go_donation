// chatgroups_conflict_test.go pins OPOS #26410's membership conflicts at the
// store.
//
// Migration 120 puts two unique rules on chat_group_members: UNIQUE (group_id,
// user_id), and uq_chat_group_members_active_label, which ignores case and
// covers active masked members only. Until #26410 a write that broke either
// one surfaced as a raw Postgres unique violation, so the admin routes
// answered 500 "Database error.". Now:
//   - someone who is already an active member → ErrMemberConflict;
//   - a label another active member holds, ignoring case → ErrLabelConflict;
//   - a label carrying a phone number or email → ErrLabelContact, which still
//     matches ErrInvalidInput for callers written before it existed;
//
// each with nothing written, and a whole CreateGroup or ApproveConnectRequest
// rolled back. Re-adding a REMOVED member is not a conflict: it reactivates
// the member (decision D3), pinned in chatgroups_reactivate_test.go, which
// uses this file's harness.
//
// Kept apart from chatgroups_test.go (far past the 500-line cap). Shares
// newTestPool and makeTestUser from that file, and makeGuestTestUser,
// memberRowWatermark, membershipRowsSince, connectRequestStatus and
// removeGroupOnCleanup from chatgroups_guest_test.go. Needs a throwaway
// Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_conflicts
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_conflicts?sslmode=disable' \
//	  go test ./internal/chatgroups/ -run 'ActiveMember|DuplicateLabel|DuplicateMembers|ContactDetails' -v
package chatgroups

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────

// memberState is the part of one chat_group_members row these tests reason
// about, read straight from the table rather than through the store.
type memberState struct {
	id        int64
	role      string
	label     string
	isRemoved bool
	removedBy *int64
}

// memberRowsFor returns userID's rows in groupID, oldest first. UNIQUE
// (group_id, user_id) allows at most one; a slice lets a test prove that a
// re-add did not write a second.
func memberRowsFor(t *testing.T, pool *pgxpool.Pool, groupID, userID int64) []memberState {
	t.Helper()
	rows, err := pool.Query(context.Background(), `
		SELECT id, role_in_group, COALESCE(masked_label, ''), removed_at IS NOT NULL, removed_by
		  FROM chat_group_members WHERE group_id = $1 AND user_id = $2 ORDER BY id`,
		groupID, userID)
	if err != nil {
		t.Fatalf("read rows of user %d in group %d: %v", userID, groupID, err)
	}
	defer rows.Close()
	var out []memberState
	for rows.Next() {
		var m memberState
		if err := rows.Scan(&m.id, &m.role, &m.label, &m.isRemoved, &m.removedBy); err != nil {
			t.Fatalf("scan member row: %v", err)
		}
		out = append(out, m)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("read rows of user %d in group %d: %v", userID, groupID, err)
	}
	return out
}

// onlyMemberRow is memberRowsFor for a user who must have exactly one row.
func onlyMemberRow(t *testing.T, pool *pgxpool.Pool, groupID, userID int64) memberState {
	t.Helper()
	rows := memberRowsFor(t, pool, groupID, userID)
	if len(rows) != 1 {
		t.Fatalf("user %d has %d rows in group %d, want exactly 1: %+v", userID, len(rows), groupID, rows)
	}
	return rows[0]
}

// writeWatermark records the highest thread and membership ids at one moment,
// so a test can prove a refused call wrote nothing afterwards. Both columns
// are identity columns whose values are never reused, so every row above a
// mark was written after it was taken (see memberRowWatermark).
type writeWatermark struct {
	pool    *pgxpool.Pool
	threads int64
	members int64
}

// takeWriteWatermark takes a writeWatermark now.
func takeWriteWatermark(t *testing.T, pool *pgxpool.Pool) writeWatermark {
	t.Helper()
	var threads int64
	if err := pool.QueryRow(context.Background(),
		`SELECT COALESCE(MAX(id), 0) FROM chat_group_threads`,
	).Scan(&threads); err != nil {
		t.Fatalf("read thread watermark: %v", err)
	}
	return writeWatermark{pool: pool, threads: threads, members: memberRowWatermark(t, pool)}
}

// assertNothingWritten fails the test if staffID created a group, or any of
// userIDs gained a membership row, since the mark was taken — a refused create
// or approval must roll back as a whole.
func (w writeWatermark) assertNothingWritten(t *testing.T, staffID int64, userIDs ...int64) {
	t.Helper()
	var threads int
	if err := w.pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_threads WHERE created_by_staff_id = $1 AND id > $2`,
		staffID, w.threads,
	).Scan(&threads); err != nil {
		t.Fatalf("count groups created by staff %d: %v", staffID, err)
	}
	if threads != 0 {
		t.Errorf("staff %d created %d groups despite the refusal, want 0 — the transaction must roll back", staffID, threads)
	}
	for _, id := range userIDs {
		if n := membershipRowsSince(t, w.pool, id, w.members); n != 0 {
			t.Errorf("user %d gained %d membership rows despite the refusal, want 0", id, n)
		}
	}
}

// conflictGroup describes a group for createConflictGroup to build.
type conflictGroup struct {
	kind    Kind
	staffID int64
	members []MemberInput
}

// createConflictGroup creates g and deletes it, with its messages and read
// cursors, when the test ends.
func createConflictGroup(t *testing.T, s *Store, g conflictGroup) int64 {
	t.Helper()
	title := ""
	if g.kind == KindTeam {
		title = "Distribution team"
	}
	groupID, err := s.CreateGroup(context.Background(), g.kind, title, g.staffID, g.members)
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	removeGroupOnCleanup(t, s.Pool, groupID)
	t.Cleanup(func() {
		for _, stmt := range []string{
			`DELETE FROM chat_group_reads WHERE group_id = $1`,
			`DELETE FROM chat_group_messages WHERE group_id = $1`,
		} {
			if _, err := s.Pool.Exec(context.Background(), stmt, groupID); err != nil {
				t.Logf("cleanup: group %d: %q: %v", groupID, stmt, err)
			}
		}
	})
	return groupID
}

// removeConnectRequestOnCleanup deletes a connect request when the test ends.
// A refused approval leaves the request pending with no group, so
// removeGroupOnCleanup never reaches it.
func removeConnectRequestOnCleanup(t *testing.T, pool *pgxpool.Pool, requestID int64) {
	t.Helper()
	t.Cleanup(func() {
		if _, err := pool.Exec(context.Background(),
			`DELETE FROM chat_group_connect_requests WHERE id = $1`, requestID,
		); err != nil {
			t.Logf("cleanup: connect request %d: %v", requestID, err)
		}
	})
}

// duplicateMembersCases are the two ways a member list collides with itself,
// each with the sentinel it must produce. members receives two distinct user
// ids; the first is also the connect-request requester where one is needed.
var duplicateMembersCases = []struct {
	name    string
	kind    Kind
	members func(first, second int64) []MemberInput
	want    error
}{
	{
		name: "same user twice in a masked group",
		kind: KindMasked,
		// Blank labels auto-number "Donor 1" and "Donor 2", so only the user
		// collides, not the label.
		members: func(first, _ int64) []MemberInput {
			return []MemberInput{{UserID: first, RoleInGroup: "donor"}, {UserID: first, RoleInGroup: "donor"}}
		},
		want: ErrMemberConflict,
	},
	{
		name: "same user twice in a team group",
		kind: KindTeam,
		members: func(first, _ int64) []MemberInput {
			return []MemberInput{{UserID: first, RoleInGroup: "volunteer"}, {UserID: first, RoleInGroup: "volunteer"}}
		},
		want: ErrMemberConflict,
	},
	{
		name: "two labels differing only in case",
		kind: KindMasked,
		members: func(first, second int64) []MemberInput {
			return []MemberInput{
				{UserID: first, RoleInGroup: "donor", Label: "Case Lead"},
				{UserID: second, RoleInGroup: "beneficiary", Label: "case LEAD"},
			}
		},
		want: ErrLabelConflict,
	},
}

// ─── Conflicts ──────────────────────────────────────────────────────────

// TestAddMemberRefusesActiveMember adds someone who is already an active
// member, for both kinds. It fails with ErrMemberConflict and the roster is
// exactly as it was.
func TestAddMemberRefusesActiveMember(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	for _, kind := range []Kind{KindMasked, KindTeam} {
		t.Run(string(kind), func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			// A VOLUNTEER account, so the one member suits both kinds: a team
			// group takes only volunteers and staff (ErrTeamMemberRole), and a
			// masked group takes anyone.
			member := makeTestUser(t, pool, "volunteer")
			groupID := createConflictGroup(t, s, conflictGroup{kind: kind, staffID: staff,
				members: []MemberInput{{UserID: member, RoleInGroup: "volunteer"}}})
			before, err := s.GetGroup(ctx, groupID)
			if err != nil {
				t.Fatalf("GetGroup before: %v", err)
			}

			err = s.AddMember(ctx, groupID, MemberInput{UserID: member, RoleInGroup: "volunteer", Label: "Someone Else"}, staff)

			if !errors.Is(err, ErrMemberConflict) {
				t.Fatalf("AddMember for an active member = %v, want errors.Is(err, ErrMemberConflict)", err)
			}
			after, err := s.GetGroup(ctx, groupID)
			if err != nil {
				t.Fatalf("GetGroup after: %v", err)
			}
			if !reflect.DeepEqual(before.Members, after.Members) {
				t.Errorf("roster changed by a refused add:\n before %+v\n after  %+v", before.Members, after.Members)
			}
		})
	}
}

// TestAddMemberRefusesDuplicateLabelIgnoringCase gives a new member a label an
// active member already holds, differing only in case and surrounding spaces.
func TestAddMemberRefusesDuplicateLabelIgnoringCase(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	groupID := createConflictGroup(t, s, conflictGroup{kind: KindMasked, staffID: staff,
		members: []MemberInput{{UserID: donor, RoleInGroup: "donor", Label: "Blue Door"}}})

	err := s.AddMember(context.Background(), groupID,
		MemberInput{UserID: beneficiary, RoleInGroup: "beneficiary", Label: "  blue DOOR "}, staff)

	if !errors.Is(err, ErrLabelConflict) {
		t.Fatalf("AddMember with a label differing only in case = %v, want errors.Is(err, ErrLabelConflict)", err)
	}
	if rows := memberRowsFor(t, pool, groupID, beneficiary); len(rows) != 0 {
		t.Errorf("beneficiary has %d rows after the refused add, want 0: %+v", len(rows), rows)
	}
}

// TestCreateGroupRefusesDuplicateMembers creates a group whose own member list
// collides. The create fails with the matching sentinel and no group exists.
func TestCreateGroupRefusesDuplicateMembers(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)

	for _, tc := range duplicateMembersCases {
		t.Run(tc.name, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			// A volunteer account: one of these cases builds a TEAM group,
			// which takes only volunteers and staff. The RoleInGroup strings
			// the cases pass are unaffected — they are free text and decide
			// nothing.
			first := makeTestUser(t, pool, "volunteer")
			second := makeTestUser(t, pool, "beneficiary")
			mark := takeWriteWatermark(t, pool)

			groupID, err := s.CreateGroup(context.Background(), tc.kind, "Distribution team", staff, tc.members(first, second))

			if groupID != 0 {
				removeGroupOnCleanup(t, pool, groupID)
			}
			if !errors.Is(err, tc.want) {
				t.Fatalf("CreateGroup = (%d, %v), want errors.Is(err, %v)", groupID, err, tc.want)
			}
			mark.assertNothingWritten(t, staff, first, second)
		})
	}
}

// TestApproveConnectRequestRefusesDuplicateMembers is the same collision on
// approval. It is refused, no group exists, and the request stays pending so
// staff can fix the member list. Donation 1 is a demo seed row from
// migrations/001_full_v2.sql, as in chatgroups_guest_test.go.
func TestApproveConnectRequestRefusesDuplicateMembers(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	for _, tc := range duplicateMembersCases {
		t.Run(tc.name, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			requester := makeTestUser(t, pool, "volunteer") // see duplicateMembersCases: one case is a team group
			second := makeTestUser(t, pool, "beneficiary")
			reqID, err := s.SubmitConnectRequest(ctx, requester, "donation", 1, nil, "please connect me")
			if err != nil {
				t.Fatalf("SubmitConnectRequest: %v", err)
			}
			removeConnectRequestOnCleanup(t, pool, reqID)
			mark := takeWriteWatermark(t, pool)

			groupID, err := s.ApproveConnectRequest(ctx, reqID, tc.kind, "Distribution team", staff, tc.members(requester, second))

			if groupID != 0 {
				removeGroupOnCleanup(t, pool, groupID)
			}
			if !errors.Is(err, tc.want) {
				t.Fatalf("ApproveConnectRequest = (%d, %v), want errors.Is(err, %v)", groupID, err, tc.want)
			}
			if status := connectRequestStatus(t, pool, reqID); status != string(RequestPending) {
				t.Errorf("request status = %q after the refused approval, want pending", status)
			}
			mark.assertNothingWritten(t, staff, requester, second)
		})
	}
}

// ─── Contact details in a label ─────────────────────────────────────────

// contactLabelCases are labels moderation.ScanContact blocks, one of each kind
// it detects.
var contactLabelCases = []struct{ name, label string }{
	{"phone number", "call me on 07701234567"},
	{"email address", "write to someone@example.com"},
}

// assertLabelContactRefusal checks err is ErrLabelContact and still matches
// ErrInvalidInput, which callers written before #26410 test for.
func assertLabelContactRefusal(t *testing.T, err error) {
	t.Helper()
	if !errors.Is(err, ErrLabelContact) {
		t.Fatalf("err = %v, want errors.Is(err, ErrLabelContact)", err)
	}
	if !errors.Is(err, ErrInvalidInput) {
		t.Errorf("err = %v no longer matches ErrInvalidInput, which older callers rely on", err)
	}
}

// TestMemberLabelWithContactDetailsIsRefused refuses a phone number or email in
// a label on every path that takes one, writing nothing.
func TestMemberLabelWithContactDetailsIsRefused(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	for _, tc := range contactLabelCases {
		t.Run("AddMember/"+tc.name, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			donor := makeTestUser(t, pool, "donor")
			other := makeTestUser(t, pool, "beneficiary")
			groupID := createConflictGroup(t, s, conflictGroup{kind: KindMasked, staffID: staff,
				members: []MemberInput{{UserID: donor, RoleInGroup: "donor"}}})

			err := s.AddMember(ctx, groupID, MemberInput{UserID: other, RoleInGroup: "beneficiary", Label: tc.label}, staff)

			assertLabelContactRefusal(t, err)
			if rows := memberRowsFor(t, pool, groupID, other); len(rows) != 0 {
				t.Errorf("refused label wrote %d rows, want 0: %+v", len(rows), rows)
			}
		})
		t.Run("CreateGroup/"+tc.name, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			donor := makeTestUser(t, pool, "donor")
			mark := takeWriteWatermark(t, pool)

			groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor", Label: tc.label}})

			if groupID != 0 {
				removeGroupOnCleanup(t, pool, groupID)
			}
			assertLabelContactRefusal(t, err)
			mark.assertNothingWritten(t, staff, donor)
		})
		// A re-added member's label is never stored — the row keeps its old
		// one — but contact details are refused as input all the same.
		t.Run("re-adding a removed member/"+tc.name, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			donor := makeTestUser(t, pool, "donor")
			groupID := createConflictGroup(t, s, conflictGroup{kind: KindMasked, staffID: staff,
				members: []MemberInput{{UserID: donor, RoleInGroup: "donor"}}})
			if err := s.RemoveMember(ctx, groupID, donor, staff); err != nil {
				t.Fatalf("RemoveMember: %v", err)
			}

			err := s.AddMember(ctx, groupID, MemberInput{UserID: donor, RoleInGroup: "donor", Label: tc.label}, staff)

			assertLabelContactRefusal(t, err)
			if got := onlyMemberRow(t, pool, groupID, donor); !got.isRemoved || got.label != "Donor 1" {
				t.Errorf("row = %+v, want still removed with label \"Donor 1\"", got)
			}
		})
	}
}
