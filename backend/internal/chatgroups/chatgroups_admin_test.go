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
