package chatgroups

import (
	"context"
	"errors"
	"testing"
)

func TestGetGroupReturnsThreadAndMembers(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(context.Background(), KindMasked, "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}

	detail, err := s.GetGroup(context.Background(), groupID)
	if err != nil {
		t.Fatalf("get group: %v", err)
	}
	if detail.ID != groupID || detail.Kind != KindMasked {
		t.Fatalf("detail = %+v, want ID=%d Kind=masked", detail, groupID)
	}
	if len(detail.Members) != 1 {
		t.Fatalf("got %d members, want 1", len(detail.Members))
	}
	if detail.Members[0].UserID != donor || detail.Members[0].MaskedLabel == "" {
		t.Fatalf("member = %+v, want UserID=%d with a non-empty label", detail.Members[0], donor)
	}
}

func TestGetGroupReturnsErrNotFoundForUnknownGroup(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)

	_, err := s.GetGroup(context.Background(), 999999999)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}

func TestRecordAndListContactBlocks(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	groupID, err := s.CreateGroup(context.Background(), KindMasked, "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}

	if err := s.RecordContactBlock(context.Background(), groupID, donor, "phone", 1, "call me on •••"); err != nil {
		t.Fatalf("record contact block: %v", err)
	}

	blocks, err := s.ListContactBlocks(context.Background(), groupID)
	if err != nil {
		t.Fatalf("list contact blocks: %v", err)
	}
	if len(blocks) != 1 {
		t.Fatalf("got %d blocks, want 1", len(blocks))
	}
	if blocks[0].Kind != "phone" || blocks[0].MatchCount != 1 {
		t.Fatalf("block = %+v, want Kind=phone MatchCount=1", blocks[0])
	}
	if blocks[0].RedactedBody == "" {
		t.Fatal("RedactedBody was empty")
	}
}

func TestCreateGroupInvalidKindReturnsErrInvalidInput(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	_, err := s.CreateGroup(context.Background(), Kind("bogus"), "", staff,
		[]MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("err = %v, want ErrInvalidInput", err)
	}
}

func TestAddMemberToUnknownGroupReturnsErrNotFound(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	err := s.AddMember(context.Background(), 999999999, MemberInput{UserID: donor, RoleInGroup: "donor"}, staff)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}

// ─── OPOS #25544: moderation.ScanContact on staff-typed masked_label ────────
//
// Design spec §5's "Alias quality" requires ScanContact to run over a
// caller-supplied masked_label at write time (a staff member pasting a phone
// number into a label is a realistic slip). These tests pin that the check
// is actually wired into insertMembers (via CreateGroup) and AddMember, that
// it REFUSES rather than redacts-and-stores (nothing carrying the raw number
// may reach the database), that it never touches an auto-generated label,
// and that an ordinary caller-supplied label is unaffected.

// TestCreateGroupRefusesPhoneNumberLabel is insertMembers' half: a
// phone-number-shaped label supplied on CreateGroup's initial member batch
// must be refused with ErrInvalidInput, and — because insertMembers runs
// inside CreateGroup's transaction — the whole group (thread row included)
// must roll back rather than leaving a half-created group behind.
func TestCreateGroupRefusesPhoneNumberLabel(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor", Label: "call me on 07701234567"},
	})
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("err = %v, want ErrInvalidInput", err)
	}
	if groupID != 0 {
		t.Fatalf("groupID = %d, want 0 — a refused label must not create a group", groupID)
	}

	var memberCount int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_members WHERE user_id = $1`, donor,
	).Scan(&memberCount); err != nil {
		t.Fatalf("count members: %v", err)
	}
	if memberCount != 0 {
		t.Fatalf("chat_group_members has %d row(s) for the refused label, want 0 — nothing carrying the raw number may be stored", memberCount)
	}

	var threadCount int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_threads WHERE created_by_staff_id = $1`, staff,
	).Scan(&threadCount); err != nil {
		t.Fatalf("count threads: %v", err)
	}
	if threadCount != 0 {
		t.Fatalf("chat_group_threads has %d row(s) after a refused label, want 0 — the whole transaction must roll back", threadCount)
	}
}

// TestAddMemberRefusesPhoneNumberLabel is AddMember's half of the same rule,
// on an already-existing group rather than inside CreateGroup's transaction.
func TestAddMemberRefusesPhoneNumberLabel(t *testing.T) {
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

	err = s.AddMember(ctx, groupID, MemberInput{
		UserID: donor2, RoleInGroup: "donor", Label: "reach me at 07701234567",
	}, staff)
	if !errors.Is(err, ErrInvalidInput) {
		t.Fatalf("err = %v, want ErrInvalidInput", err)
	}

	var memberCount int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor2,
	).Scan(&memberCount); err != nil {
		t.Fatalf("count members: %v", err)
	}
	if memberCount != 0 {
		t.Fatalf("chat_group_members has %d row(s) for the refused label, want 0 — nothing carrying the raw number may be stored", memberCount)
	}
}

// TestAddMemberAllowsCleanLabel proves the new check does not overreach: an
// ordinary caller-supplied label with no contact info must still be stored
// exactly as given.
func TestAddMemberAllowsCleanLabel(t *testing.T) {
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

	if err := s.AddMember(ctx, groupID, MemberInput{
		UserID: donor2, RoleInGroup: "donor", Label: "Kind Donor",
	}, staff); err != nil {
		t.Fatalf("AddMember with a clean label: %v", err)
	}

	var label string
	if err := pool.QueryRow(ctx,
		`SELECT masked_label FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor2,
	).Scan(&label); err != nil {
		t.Fatalf("read added member: %v", err)
	}
	if label != "Kind Donor" {
		t.Fatalf("masked_label = %q, want %q — a clean caller-supplied label must not be refused", label, "Kind Donor")
	}
}

// TestAddMemberEmptyLabelStillAutoGeneratesForMaskedGroup is the sanity check
// for the other side of the guard: an auto-generated label must never be
// scanned or rejected, since it is never staff-typed free text. Leaving
// Label blank cannot realistically produce something phone-shaped, so this
// cannot really "fail" on the scan — its job is proving the new check did
// not accidentally start scanning (or otherwise break) the empty-label,
// auto-generate path.
func TestAddMemberEmptyLabelStillAutoGeneratesForMaskedGroup(t *testing.T) {
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
		t.Fatalf("AddMember with an empty label: %v", err)
	}

	var label string
	if err := pool.QueryRow(ctx,
		`SELECT masked_label FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor2,
	).Scan(&label); err != nil {
		t.Fatalf("read added member: %v", err)
	}
	if label != "Donor 2" {
		t.Fatalf("masked_label = %q, want the auto-generated %q", label, "Donor 2")
	}
}
