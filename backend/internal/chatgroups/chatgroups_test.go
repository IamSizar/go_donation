package chatgroups

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newTestPool brings a throwaway database up to date with the real
// migrations. Skipped unless TEST_DATABASE_URL is set, so `go test ./...`
// stays green on a bare checkout:
//
//	createdb godonation_chatgroups
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups?sslmode=disable' \
//	  go test ./internal/chatgroups/ -v
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chatgroups integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestNewStoreConnects(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	if s.Pool != pool {
		t.Fatal("New did not wire the pool through")
	}
}

func TestCreateGroupMasked(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	donor2 := makeTestUser(t, pool, "donor")
	staff := makeTestUser(t, pool, "staff")

	groupID, err := s.CreateGroup(ctx, KindMasked, "ignored for masked groups", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
		{UserID: donor2, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if groupID == 0 {
		t.Fatal("expected a non-zero group id")
	}

	var kind, title string
	if err := pool.QueryRow(ctx,
		`SELECT kind, member_title FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&kind, &title); err != nil {
		t.Fatalf("read group: %v", err)
	}
	if kind != "masked" {
		t.Errorf("kind = %q, want masked", kind)
	}
	if title != "" {
		t.Errorf("member_title = %q, want empty — masked groups never carry a member-facing title", title)
	}

	rows, err := pool.Query(ctx,
		`SELECT user_id, role_in_group, masked, masked_label FROM chat_group_members WHERE group_id = $1 ORDER BY id`, groupID)
	if err != nil {
		t.Fatalf("read members: %v", err)
	}
	defer rows.Close()
	var got []struct {
		userID int64
		role   string
		masked bool
		label  string
	}
	for rows.Next() {
		var r struct {
			userID int64
			role   string
			masked bool
			label  string
		}
		if err := rows.Scan(&r.userID, &r.role, &r.masked, &r.label); err != nil {
			t.Fatalf("scan member: %v", err)
		}
		got = append(got, r)
	}
	if len(got) != 3 {
		t.Fatalf("got %d members, want 3", len(got))
	}
	if !got[0].masked || got[0].label != "Donor 1" {
		t.Errorf("donor member = %+v, want masked=true label=Donor 1", got[0])
	}
	if !got[1].masked || got[1].label != "Beneficiary 1" {
		t.Errorf("beneficiary member = %+v, want masked=true label=Beneficiary 1", got[1])
	}
	if !got[2].masked || got[2].label != "Donor 2" {
		t.Errorf("second donor member = %+v, want masked=true label=Donor 2", got[2])
	}
}

func TestCreateGroupTeamMembersAreNeverMasked(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	v1 := makeTestUser(t, pool, "volunteer")
	v2 := makeTestUser(t, pool, "volunteer")
	staff := makeTestUser(t, pool, "staff")

	groupID, err := s.CreateGroup(ctx, KindTeam, "Distribution team", staff, []MemberInput{
		{UserID: v1, RoleInGroup: "volunteer"},
		{UserID: v2, RoleInGroup: "volunteer"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	var title string
	if err := pool.QueryRow(ctx,
		`SELECT member_title FROM chat_group_threads WHERE id = $1`, groupID,
	).Scan(&title); err != nil {
		t.Fatalf("read group: %v", err)
	}
	if title != "Distribution team" {
		t.Errorf("member_title = %q, want %q", title, "Distribution team")
	}

	rows, err := pool.Query(ctx,
		`SELECT masked, masked_label FROM chat_group_members WHERE group_id = $1`, groupID)
	if err != nil {
		t.Fatalf("read members: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var masked bool
		var label *string
		if err := rows.Scan(&masked, &label); err != nil {
			t.Fatalf("scan: %v", err)
		}
		if masked {
			t.Error("team-group member has masked=true, want false")
		}
		if label != nil {
			t.Errorf("team-group member has a masked_label (%q), want NULL", *label)
		}
	}
}

func TestAddMemberDerivesMaskedFromGroupKind(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor1 := makeTestUser(t, pool, "donor")
	donor2 := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor1, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	if err := s.AddMember(ctx, groupID, MemberInput{UserID: donor2, RoleInGroup: "donor"}, staff); err != nil {
		t.Fatalf("AddMember: %v", err)
	}

	var masked bool
	var label string
	if err := pool.QueryRow(ctx,
		`SELECT masked, masked_label FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor2,
	).Scan(&masked, &label); err != nil {
		t.Fatalf("read added member: %v", err)
	}
	if !masked {
		t.Error("masked = false, want true — must be derived from the group's kind")
	}
	if label != "Donor 2" {
		t.Errorf("label = %q, want %q (continues the group's existing donor count)", label, "Donor 2")
	}
}

// TestAddMemberRespectsCallerLabelOverride covers the branch where a caller
// supplies an explicit Label for a masked-group member — the auto-label
// counter must be skipped entirely and the exact caller-supplied string
// stored, not a generated "Donor N".
func TestAddMemberRespectsCallerLabelOverride(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor1 := makeTestUser(t, pool, "donor")
	donor2 := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor1, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	if err := s.AddMember(ctx, groupID, MemberInput{UserID: donor2, RoleInGroup: "donor", Label: "Custom"}, staff); err != nil {
		t.Fatalf("AddMember: %v", err)
	}

	var label string
	if err := pool.QueryRow(ctx,
		`SELECT masked_label FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor2,
	).Scan(&label); err != nil {
		t.Fatalf("read added member: %v", err)
	}
	if label != "Custom" {
		t.Errorf("masked_label = %q, want the caller-supplied %q, not an auto-generated label", label, "Custom")
	}
}

func TestRemoveMemberIsSoftDelete(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	if err := s.RemoveMember(ctx, groupID, donor, staff); err != nil {
		t.Fatalf("RemoveMember: %v", err)
	}

	var removedAt *string
	var stillHasLabel string
	if err := pool.QueryRow(ctx,
		`SELECT removed_at::text, masked_label FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor,
	).Scan(&removedAt, &stillHasLabel); err != nil {
		t.Fatalf("row must still exist after removal (soft-delete only): %v", err)
	}
	if removedAt == nil {
		t.Error("removed_at is NULL, want a timestamp")
	}
	if stillHasLabel != "Donor 1" {
		t.Errorf("masked_label = %q, want it preserved for historical message resolution", stillHasLabel)
	}

	// A second removal of the same (already-removed) member is an error,
	// not a silent no-op — the caller asked to remove someone not currently
	// active.
	if err := s.RemoveMember(ctx, groupID, donor, staff); err == nil {
		t.Error("removing an already-removed member should return an error")
	}
}

func TestPostMessageRequiresActiveMembership(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	stranger := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	if _, err := s.PostMessage(ctx, groupID, stranger, "hello"); err == nil {
		t.Error("expected an error posting from a non-member")
	}

	// The non-member rejection must be an early return before any write —
	// no message row should exist for that attempt.
	var strangerMessageCount int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_messages WHERE group_id = $1 AND sender_user_id = $2`,
		groupID, stranger,
	).Scan(&strangerMessageCount); err != nil {
		t.Fatalf("count messages from stranger: %v", err)
	}
	if strangerMessageCount != 0 {
		t.Errorf("chat_group_messages has %d row(s) for the rejected non-member, want 0", strangerMessageCount)
	}

	msgID, err := s.PostMessage(ctx, groupID, donor, "hello from the donor")
	if err != nil {
		t.Fatalf("PostMessage from an active member: %v", err)
	}
	if msgID == 0 {
		t.Fatal("expected a non-zero message id")
	}

	// The sender's own cursor must advance to their own message — otherwise
	// they'd see their own message as unread.
	var lastRead int64
	if err := pool.QueryRow(ctx,
		`SELECT last_read_msg_id FROM chat_group_reads WHERE group_id = $1 AND user_id = $2`,
		groupID, donor,
	).Scan(&lastRead); err != nil {
		t.Fatalf("read cursor after posting: %v", err)
	}
	if lastRead != msgID {
		t.Errorf("sender's last_read_msg_id = %d, want %d (their own message)", lastRead, msgID)
	}
}

func TestPostMessageRejectsEmptyBody(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	groupID, _ := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	if _, err := s.PostMessage(ctx, groupID, donor, "   "); err == nil {
		t.Error("expected an error for a whitespace-only body")
	}
}

// TestPostMessageRollsBackOnReadCursorFailure proves PostMessage's message
// insert and its read-cursor advance (advanceReadCursor) run in the SAME
// transaction: forcing the SECOND statement to fail must roll back the
// FIRST statement's already-inserted message too, not just the failing
// statement on its own.
//
// chat_group_reads has no NOT NULL gap or FK to trip naturally, so this
// test injects a scratch CHECK constraint that only this test's donor's
// user_id can violate — named and scoped to that user_id so it can't
// affect any other test running against the same database — then confirms
// both the message row and the read-cursor row are absent afterward.
func TestPostMessageRollsBackOnReadCursorFailure(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	// donor's user_id is a fresh serial id from makeTestUser, not user
	// input, so building the constraint expression with fmt.Sprintf here
	// carries no injection risk.
	constraintName := fmt.Sprintf("test_fault_injection_%d", donor)
	if _, err := pool.Exec(ctx, fmt.Sprintf(
		`ALTER TABLE chat_group_reads ADD CONSTRAINT %s CHECK (user_id <> %d)`,
		constraintName, donor,
	)); err != nil {
		t.Fatalf("inject fault constraint: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), fmt.Sprintf(
			`ALTER TABLE chat_group_reads DROP CONSTRAINT IF EXISTS %s`, constraintName,
		))
	})

	if _, err := s.PostMessage(ctx, groupID, donor, "this must not survive"); err == nil {
		t.Fatal("expected PostMessage to fail when the read-cursor advance is forced to fail")
	}

	var messageCount int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_messages WHERE group_id = $1 AND sender_user_id = $2`,
		groupID, donor,
	).Scan(&messageCount); err != nil {
		t.Fatalf("count messages: %v", err)
	}
	if messageCount != 0 {
		t.Errorf("chat_group_messages has %d row(s) for this group/sender after a failed PostMessage, want 0 — the message insert was not rolled back with the failing read-cursor advance", messageCount)
	}

	var readCount int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_reads WHERE group_id = $1 AND user_id = $2`,
		groupID, donor,
	).Scan(&readCount); err != nil {
		t.Fatalf("count read cursors: %v", err)
	}
	if readCount != 0 {
		t.Errorf("chat_group_reads has %d row(s) for this group/user after a failed PostMessage, want 0 (the failing insert itself should not have committed)", readCount)
	}
}

func TestPostMessageAsStaffDoesNotRequireMembership(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staffCreator := makeTestUser(t, pool, "staff")
	otherAdmin := makeTestUser(t, pool, "staff") // not added as a member of this group
	donor := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staffCreator, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}

	msgID, err := s.PostMessageAsStaff(ctx, groupID, otherAdmin, "any admin can reply here")
	if err != nil {
		t.Fatalf("PostMessageAsStaff from a non-member admin: %v", err)
	}
	if msgID == 0 {
		t.Fatal("expected a non-zero message id")
	}
}

// ─── ListMessagesForMember ───────────────────────────────────────────────

// TestListMessagesForMemberMasksIdentity is the highest-value test in this
// phase: it is the executable statement of the privacy invariant the whole
// feature exists to provide. GroupMessage structurally cannot hold a user
// id, but SenderLabel is a plain string — nothing in the type system stops a
// wrong query from putting a REAL NAME in it. So the assertion below
// marshals the response exactly as an HTTP handler would and searches the
// raw bytes, which catches a leak through any field, not just the ones this
// test names.
func TestListMessagesForMemberMasksIdentity(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")

	// A distinctive real name, so a leak would be unmistakable in the
	// assertion below.
	setFullName(t, pool, donor, "Ahmad Distinctive Realname")
	setPhone(t, pool, donor, "+9647701234567")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if _, err := s.PostMessage(ctx, groupID, donor, "Hi, I wanted to check in"); err != nil {
		t.Fatalf("PostMessage: %v", err)
	}
	if _, err := s.PostMessageAsStaff(ctx, groupID, staff, "Thanks for reaching out"); err != nil {
		t.Fatalf("PostMessageAsStaff: %v", err)
	}

	msgs, err := s.ListMessagesForMember(ctx, groupID, beneficiary, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember: %v", err)
	}
	if len(msgs) != 2 {
		t.Fatalf("got %d messages, want 2", len(msgs))
	}

	if msgs[0].SenderLabel != "Donor 1" {
		t.Errorf("donor's message SenderLabel = %q, want %q", msgs[0].SenderLabel, "Donor 1")
	}
	if msgs[1].SenderLabel != "Support" {
		t.Errorf("staff's message SenderLabel = %q, want %q", msgs[1].SenderLabel, "Support")
	}

	// The structural check: marshal to JSON exactly as an HTTP handler
	// would, and assert the raw bytes contain neither the real name, the
	// phone, nor either sender's real user id anywhere.
	raw, err := json.Marshal(msgs)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	text := string(raw)
	for _, leaked := range []string{
		"Ahmad Distinctive Realname",
		"+9647701234567",
		fmt.Sprintf("%d", donor),
		fmt.Sprintf("%d", staff),
	} {
		if strings.Contains(text, leaked) {
			t.Errorf("masked response leaks %q: %s", leaked, text)
		}
	}
}

func TestListMessagesForMemberIsMineIsCorrect(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	groupID, _ := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})
	if _, err := s.PostMessage(ctx, groupID, donor, "from the donor"); err != nil {
		t.Fatalf("PostMessage: %v", err)
	}

	asDonor, err := s.ListMessagesForMember(ctx, groupID, donor, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember (donor view): %v", err)
	}
	if !asDonor[0].IsMine {
		t.Error("donor viewing their own message: IsMine = false, want true")
	}

	asBeneficiary, err := s.ListMessagesForMember(ctx, groupID, beneficiary, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember (beneficiary view): %v", err)
	}
	if asBeneficiary[0].IsMine {
		t.Error("beneficiary viewing the donor's message: IsMine = true, want false")
	}
}

func TestListMessagesForMemberCursorPagination(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	groupID, _ := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})

	var lastID int64
	for i := 0; i < 3; i++ {
		id, err := s.PostMessage(ctx, groupID, donor, fmt.Sprintf("message %d", i))
		if err != nil {
			t.Fatalf("PostMessage %d: %v", i, err)
		}
		lastID = id
	}
	_ = lastID

	first, err := s.ListMessagesForMember(ctx, groupID, donor, 0, 2)
	if err != nil {
		t.Fatalf("first page: %v", err)
	}
	if len(first) != 2 {
		t.Fatalf("first page len = %d, want 2", len(first))
	}

	second, err := s.ListMessagesForMember(ctx, groupID, donor, first[len(first)-1].ID, 50)
	if err != nil {
		t.Fatalf("second page: %v", err)
	}
	if len(second) != 1 {
		t.Fatalf("second page len = %d, want 1 (only the message after the cursor)", len(second))
	}

	// The critical polling property: re-polling with the LATEST id on hand
	// returns nothing new, not the whole history again.
	empty, err := s.ListMessagesForMember(ctx, groupID, donor, second[len(second)-1].ID, 50)
	if err != nil {
		t.Fatalf("re-poll: %v", err)
	}
	if len(empty) != 0 {
		t.Errorf("re-polling with the latest id returned %d messages, want 0", len(empty))
	}
}

func TestListMessagesForMemberTeamGroupUsesRealNames(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	v1 := makeTestUser(t, pool, "volunteer")
	// The viewer is a SECOND volunteer, not the staff creator: the creator
	// gets no chat_group_members row from CreateGroup, and the viewer gate
	// (see ListMessagesForMember) requires an active member. Staff read via
	// the Admin* methods, never through this one.
	v2 := makeTestUser(t, pool, "volunteer")
	setFullName(t, pool, v1, "Real Volunteer Name")

	groupID, _ := s.CreateGroup(ctx, KindTeam, "Distribution team", staff, []MemberInput{
		{UserID: v1, RoleInGroup: "volunteer"},
		{UserID: v2, RoleInGroup: "volunteer"},
	})
	if _, err := s.PostMessage(ctx, groupID, v1, "on my way"); err != nil {
		t.Fatalf("PostMessage: %v", err)
	}

	msgs, err := s.ListMessagesForMember(ctx, groupID, v2, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember: %v", err)
	}
	if msgs[0].SenderLabel != "Real Volunteer Name" {
		t.Errorf("team-group SenderLabel = %q, want the real name", msgs[0].SenderLabel)
	}
}

// TestListMessagesForMemberStaffWithMemberRowShowsSupport covers the
// `mem.role_in_group = 'staff'` arm of the masking CASE, which every other
// test in this file misses: they only ever use donor/beneficiary/volunteer
// roles, so a staff member WITH a chat_group_members row is never exercised.
//
// Design §9 makes that row the NORMAL case — staff rows exist for
// notification targeting and ownership — so this is not an exotic path.
// Without the OR-clause such a message would take the non-staff branch,
// resolve to the member's own masked_label, and because autoLabelName has no
// "staff" entry that label reads "Member 1": a distinct pseudonymous speaker
// that a member could count and fingerprint across messages, which is the
// exact harm the single fixed "Support" label exists to prevent.
//
// It deliberately posts via PostMessage, not PostMessageAsStaff: the no-row
// path (mem.id IS NULL) is already covered by
// TestListMessagesForMemberMasksIdentity, and the point here is the
// row-based path.
func TestListMessagesForMemberStaffWithMemberRowShowsSupport(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staffCreator := makeTestUser(t, pool, "staff")
	staffMember := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	// A distinctive real name on the staff member, so a leak through the
	// team/real-name branch would be unmistakable below.
	setFullName(t, pool, staffMember, "Sara Staff Realname")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staffCreator, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: staffMember, RoleInGroup: "staff"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if _, err := s.PostMessage(ctx, groupID, staffMember, "how can we help?"); err != nil {
		t.Fatalf("PostMessage as the staff member: %v", err)
	}

	// Viewed by a DIFFERENT member — the donor, the person the masking
	// protects against.
	msgs, err := s.ListMessagesForMember(ctx, groupID, donor, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember: %v", err)
	}
	if len(msgs) != 1 {
		t.Fatalf("got %d messages, want 1", len(msgs))
	}
	if msgs[0].SenderLabel != "Support" {
		t.Errorf("staff member WITH a member row: SenderLabel = %q, want %q — a per-admin label lets a member fingerprint individual staff", msgs[0].SenderLabel, "Support")
	}

	raw, err := json.Marshal(msgs)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(raw), "Sara Staff Realname") {
		t.Errorf("staff member's message leaks their real name: %s", raw)
	}
}

// TestListMessagesForMemberRequiresActiveMembership is the read-side twin of
// TestPostMessageRequiresActiveMembership. The store gates reads on the same
// predicate as writes, so neither a stranger who was never in the group nor
// a member RemoveMember has since revoked can pull the history.
func TestListMessagesForMemberRequiresActiveMembership(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	removed := makeTestUser(t, pool, "beneficiary")
	stranger := makeTestUser(t, pool, "donor") // never added to this group

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: removed, RoleInGroup: "beneficiary"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if _, err := s.PostMessage(ctx, groupID, donor, "members-only history"); err != nil {
		t.Fatalf("PostMessage: %v", err)
	}

	// A user who was never a member gets an error and no messages.
	msgs, err := s.ListMessagesForMember(ctx, groupID, stranger, 0, 50)
	if err == nil {
		t.Errorf("a non-member read succeeded, want an error; got %d messages", len(msgs))
	}
	if len(msgs) != 0 {
		t.Errorf("a non-member read returned %d messages, want 0", len(msgs))
	}

	// A removed former member loses read access too — RemoveMember keeps
	// the row for historical LABEL resolution, not as continued access.
	if err := s.RemoveMember(ctx, groupID, removed, staff); err != nil {
		t.Fatalf("RemoveMember: %v", err)
	}
	msgs, err = s.ListMessagesForMember(ctx, groupID, removed, 0, 50)
	if err == nil {
		t.Errorf("a removed member's read succeeded, want an error; got %d messages", len(msgs))
	}
	if len(msgs) != 0 {
		t.Errorf("a removed member's read returned %d messages, want 0", len(msgs))
	}

	// The gate must not lock out the people it is meant to serve.
	msgs, err = s.ListMessagesForMember(ctx, groupID, donor, 0, 50)
	if err != nil {
		t.Fatalf("an active member's read failed: %v", err)
	}
	if len(msgs) != 1 {
		t.Errorf("active member got %d messages, want 1", len(msgs))
	}
}

// TestListMessagesForMemberKeepsRemovedMembersLabel is the reason
// RemoveMember soft-deletes instead of DELETEing: both the migration's
// comment on chat_group_members.removed_at and RemoveMember's own doc
// comment promise the row survives so THIS query can still resolve that
// member's historical messages. If the label join filtered on
// `removed_at IS NULL`, the surviving row would be invisible here — the
// soft-delete would buy nothing, and in a masked group a removed donor's
// past messages would fall through to the staff branch and be presented to
// everyone as having come from "Support", i.e. the organisation would
// appear to have said what a donor actually said.
func TestListMessagesForMemberKeepsRemovedMembersLabel(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	setFullName(t, pool, donor, "Ahmad Distinctive Realname")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if _, err := s.PostMessage(ctx, groupID, donor, "said this before being removed"); err != nil {
		t.Fatalf("PostMessage: %v", err)
	}
	if err := s.RemoveMember(ctx, groupID, donor, staff); err != nil {
		t.Fatalf("RemoveMember: %v", err)
	}

	msgs, err := s.ListMessagesForMember(ctx, groupID, beneficiary, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember: %v", err)
	}
	if len(msgs) != 1 {
		t.Fatalf("got %d messages, want 1", len(msgs))
	}
	if msgs[0].SenderLabel != "Donor 1" {
		t.Errorf("removed member's historical SenderLabel = %q, want %q — the soft-deleted row must still resolve the label", msgs[0].SenderLabel, "Donor 1")
	}

	// Removal must not become a leak route either.
	raw, err := json.Marshal(msgs)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(raw), "Ahmad Distinctive Realname") {
		t.Errorf("removed member's message leaks the real name: %s", raw)
	}
}

// setFullName / setPhone give a test user real profile data so the masking
// test can assert that data does NOT leak.
//
// Deviates from the task brief's version, which does not run against this
// schema: user_profiles has NO unique constraint on user_id (only the `id`
// primary key), so the brief's `ON CONFLICT (user_id)` raises "there is no
// unique or exclusion constraint matching the ON CONFLICT specification";
// and `address` is NOT NULL with no default, so omitting it raises a
// not-null violation. A plain INSERT supplying both `gender` and `address`
// is enough here because makeTestUser always creates a brand-new user with
// no profile row — there is nothing to conflict with.
func setFullName(t *testing.T, pool *pgxpool.Pool, userID int64, name string) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `
		INSERT INTO user_profiles (user_id, full_name, gender, address)
		VALUES ($1, $2, 'Male', '')`,
		userID, name,
	); err != nil {
		t.Fatalf("set full name: %v", err)
	}
	// users has an ON DELETE CASCADE FK from user_profiles (migration 002),
	// so makeTestUser's own cleanup removes this row too.
}

func setPhone(t *testing.T, pool *pgxpool.Pool, userID int64, phone string) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `UPDATE users SET phone = $2 WHERE id = $1`, userID, phone); err != nil {
		t.Fatalf("set phone: %v", err)
	}
}

// makeTestUser inserts a minimal users row and removes it on cleanup. role
// is informational only here (chatgroups doesn't read users.role_id); it's
// recorded so test failures are easier to read.
func makeTestUser(t *testing.T, pool *pgxpool.Pool, role string) int64 {
	t.Helper()
	ctx := context.Background()
	raiseUserIDFloor(t, pool)
	phone := "9647" + randomDigits(t, 8)
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		phone,
	).Scan(&id); err != nil {
		t.Fatalf("insert test user (%s): %v", role, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// testUserIDFloor makes every test user's id a wide, distinctive number
// instead of the single- or double-digit ids a freshly created test database
// hands out.
//
// This is not cosmetic. TestListMessagesForMemberMasksIdentity proves the
// masked response leaks no real user id by searching the raw response JSON
// for the id's decimal digits — the strongest form of the check, because it
// catches a leak through ANY field rather than only the ones the test names.
// With a two-digit id that search is unsound: on a fresh database the donor
// drew id 21 and the substring "21" duly turned up inside the legitimate
// `"created_at":"2026-09-12T17:38:21.223297Z"`, failing the test on digits
// that were never an id at all. Real ids are never that small, so raising
// the floor removes the false positive without weakening the assertion —
// a nine-digit id appearing anywhere in the payload is a genuine leak.
const testUserIDFloor = 700000000

// raiseUserIDFloor pushes users' id sequence above testUserIDFloor, once per
// test process. setval with GREATEST never moves the sequence backwards, so
// it is safe to run against a database that already holds higher ids.
// users.id is a 32-bit integer, so the floor leaves ~1.4 billion ids of
// headroom.
var raiseUserIDFloorOnce sync.Once

func raiseUserIDFloor(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	raiseUserIDFloorOnce.Do(func() {
		if _, err := pool.Exec(context.Background(), `
			SELECT setval(
				pg_get_serial_sequence('users', 'id'),
				GREATEST((SELECT COALESCE(MAX(id), 0) FROM users), $1))`,
			testUserIDFloor,
		); err != nil {
			t.Fatalf("raise test user id floor: %v", err)
		}
	})
}

// testUserPhoneSeq gives each makeTestUser call a distinct phone number.
// randomDigits alone (seeded only from t.Name() and the digit index) repeats
// identically across multiple calls within the SAME test — every
// multi-member test (e.g. TestCreateGroupMasked, which inserts a donor and a
// beneficiary under one *testing.T) hit a real `users_phone_key` collision
// because of this before the counter was added.
var testUserPhoneSeq int64

func randomDigits(t *testing.T, n int) string {
	t.Helper()
	seq := atomic.AddInt64(&testUserPhoneSeq, 1)
	b := make([]byte, n)
	for i := range b {
		b[i] = byte('0' + (seq+int64(i))%10)
	}
	return string(b)
}
