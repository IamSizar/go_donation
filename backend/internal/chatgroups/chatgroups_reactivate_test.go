// chatgroups_reactivate_test.go pins the user's decision D3 for OPOS #26410:
// re-adding a REMOVED member reactivates their existing chat_group_members
// row instead of refusing, keeping its member id, masked label and role, so
// the messages they sent before and after the removal resolve to one speaker.
// It has two limits: a label that went to someone else meanwhile is a
// conflict (ErrLabelConflict), and a guest account is never reactivated
// (ErrGuestMember).
//
// Split from chatgroups_conflict_test.go so both stay under the 500-line cap.
// Uses that file's harness (memberState, onlyMemberRow, conflictGroup,
// createConflictGroup), newTestPool and makeTestUser from chatgroups_test.go,
// and makeGuestTestUser from chatgroups_guest_test.go. Needs a throwaway
// Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatgroups_reactivate
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatgroups_reactivate?sslmode=disable' \
//	  go test ./internal/chatgroups/ -run Reactivat -v
package chatgroups

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

// TestAddMemberReactivatesRemovedMember removes a masked member who has
// spoken, then adds them back with a different role and label. The same row
// comes back: same member id, removed_at and removed_by cleared, old label
// and role kept. Their old message and a new one resolve to that one speaker.
func TestAddMemberReactivatesRemovedMember(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	groupID := createConflictGroup(t, s, conflictGroup{kind: KindMasked, staffID: staff, members: []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	}})
	if _, err := s.PostMessage(ctx, groupID, donor, "said before being removed"); err != nil {
		t.Fatalf("PostMessage before removal: %v", err)
	}
	original := onlyMemberRow(t, pool, groupID, donor)
	if err := s.RemoveMember(ctx, groupID, donor, staff); err != nil {
		t.Fatalf("RemoveMember: %v", err)
	}

	// A different role and label on purpose: reactivation must ignore both.
	err := s.AddMember(ctx, groupID, MemberInput{UserID: donor, RoleInGroup: "volunteer", Label: "A Brand New Label"}, staff)

	if err != nil {
		t.Fatalf("re-adding a removed member: %v", err)
	}
	got := onlyMemberRow(t, pool, groupID, donor)
	want := memberState{id: original.id, role: "donor", label: "Donor 1"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("reactivated row = %+v, want %+v — the same row, active, with its old label and role", got, want)
	}
	if _, err := s.PostMessage(ctx, groupID, donor, "said after coming back"); err != nil {
		t.Fatalf("PostMessage after reactivation: %v — the member must be active again", err)
	}
	msgs, err := s.ListMessagesForMember(ctx, groupID, beneficiary, 0, 50)
	if err != nil {
		t.Fatalf("ListMessagesForMember: %v", err)
	}
	if len(msgs) != 2 {
		t.Fatalf("got %d messages, want 2", len(msgs))
	}
	for _, m := range msgs {
		if m.SenderMemberID != original.id || m.SenderLabel != "Donor 1" {
			t.Errorf("message %q resolves to member %d %q, want member %d \"Donor 1\" — old and new messages must line up",
				m.Body, m.SenderMemberID, m.SenderLabel, original.id)
		}
	}
}

// TestAddMemberReactivatesRemovedTeamMember is the team-group case: no label
// to keep, but the same row and role still come back.
func TestAddMemberReactivatesRemovedTeamMember(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	volunteer := makeTestUser(t, pool, "volunteer")
	groupID := createConflictGroup(t, s, conflictGroup{kind: KindTeam, staffID: staff,
		members: []MemberInput{{UserID: volunteer, RoleInGroup: "volunteer"}}})
	original := onlyMemberRow(t, pool, groupID, volunteer)
	if err := s.RemoveMember(ctx, groupID, volunteer, staff); err != nil {
		t.Fatalf("RemoveMember: %v", err)
	}

	if err := s.AddMember(ctx, groupID, MemberInput{UserID: volunteer, RoleInGroup: "donor"}, staff); err != nil {
		t.Fatalf("re-adding a removed team member: %v", err)
	}

	got := onlyMemberRow(t, pool, groupID, volunteer)
	if want := (memberState{id: original.id, role: "volunteer"}); !reflect.DeepEqual(got, want) {
		t.Errorf("reactivated row = %+v, want %+v", got, want)
	}
}

// TestAddMemberReactivationRefusedWhenLabelTaken covers a removed member whose
// label went to someone else meanwhile. Bringing them back would give two
// active members one label, so it fails with ErrLabelConflict and the old row
// stays removed with its label.
func TestAddMemberReactivationRefusedWhenLabelTaken(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	first := makeTestUser(t, pool, "donor")
	second := makeTestUser(t, pool, "donor")
	groupID := createConflictGroup(t, s, conflictGroup{kind: KindMasked, staffID: staff,
		members: []MemberInput{{UserID: first, RoleInGroup: "donor", Label: "Blue Door"}}})
	if err := s.RemoveMember(ctx, groupID, first, staff); err != nil {
		t.Fatalf("RemoveMember: %v", err)
	}
	// The label index covers active members only, so a removed member's label
	// is free for someone new...
	if err := s.AddMember(ctx, groupID, MemberInput{UserID: second, RoleInGroup: "donor", Label: "blue door"}, staff); err != nil {
		t.Fatalf("giving a removed member's label to someone new: %v", err)
	}

	// ...after which its original holder cannot come back under it.
	err := s.AddMember(ctx, groupID, MemberInput{UserID: first, RoleInGroup: "donor", Label: "Anything Else"}, staff)

	if !errors.Is(err, ErrLabelConflict) {
		t.Fatalf("reactivation onto a taken label = %v, want errors.Is(err, ErrLabelConflict)", err)
	}
	if got := onlyMemberRow(t, pool, groupID, first); !got.isRemoved || got.label != "Blue Door" {
		t.Errorf("original holder = %+v, want still removed with label \"Blue Door\"", got)
	}
	if newer := onlyMemberRow(t, pool, groupID, second); newer.isRemoved {
		t.Errorf("newer holder = %+v, want still active", newer)
	}
}

// TestAddMemberRefusesReactivatingGuest re-adds a removed guest membership
// written before OPOS #26355. Reactivating it would make a guest an active
// member after all, so it fails with ErrGuestMember and stays removed.
func TestAddMemberRefusesReactivatingGuest(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	guest := makeGuestTestUser(t, pool)
	groupID := createConflictGroup(t, s, conflictGroup{kind: KindMasked, staffID: staff,
		members: []MemberInput{{UserID: donor, RoleInGroup: "donor"}}})
	if _, err := pool.Exec(ctx, `
		INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, masked_label, added_by_staff_id, removed_at, removed_by)
		VALUES ($1, $2, 'beneficiary', TRUE, 'Beneficiary 1', $3, now(), $3)`,
		groupID, guest, staff,
	); err != nil {
		t.Fatalf("insert removed legacy guest membership: %v", err)
	}

	err := s.AddMember(ctx, groupID, MemberInput{UserID: guest, RoleInGroup: "beneficiary"}, staff)

	if !errors.Is(err, ErrGuestMember) {
		t.Fatalf("reactivating a guest = %v, want errors.Is(err, ErrGuestMember)", err)
	}
	if got := onlyMemberRow(t, pool, groupID, guest); !got.isRemoved {
		t.Errorf("guest row = %+v, want still removed", got)
	}
}
