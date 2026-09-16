// chatgroups_contact_blocks_duplicate_profiles_test.go — ListContactBlocks
// must list each refused attempt once, even when its sender has two
// user_profiles rows (OPOS #26497).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows
// (see chatgroups_duplicate_profiles_test.go for how). A plain join on it then
// repeats every row it touches.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set (see newTestPool in chatgroups_test.go).
package chatgroups

import (
	"context"
	"testing"
)

// TestListContactBlocksListsEachBlockOnceWhenSenderHasTwoProfiles seeds one
// refused attempt from a sender with two profile rows and expects one block,
// named from the oldest profile row.
func TestListContactBlocksListsEachBlockOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	setFullName(t, pool, donor, "Oldest Profile Name")
	setFullName(t, pool, donor, "Newer Duplicate Profile Name")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if err := s.RecordContactBlock(ctx, groupID, donor, "phone", 1, "call me on [redacted]"); err != nil {
		t.Fatalf("RecordContactBlock: %v", err)
	}

	blocks, err := s.ListContactBlocks(ctx, groupID)
	if err != nil {
		t.Fatalf("ListContactBlocks: %v", err)
	}
	if len(blocks) != 1 {
		t.Fatalf("got %d contact blocks, want 1: a sender with two user_profiles rows must not duplicate the block", len(blocks))
	}
	if blocks[0].SenderName == nil || *blocks[0].SenderName != "Oldest Profile Name" {
		t.Errorf("SenderName = %v, want %q (the oldest profile row)", blocks[0].SenderName, "Oldest Profile Name")
	}
}
