// chatgroups_duplicate_profiles_test.go — AdminListMessages and
// ListMessagesForMember must list every message exactly once, even when its
// sender has two user_profiles rows.
//
// WHY THIS CAN HAPPEN
// user_profiles.user_id carries no UNIQUE constraint (001_full_v2.sql; migration
// 124 adds only a plain index), and three writers create a profile by checking
// for a row and then INSERTing with no lock in between — users.UpsertProfile,
// users.SubmitRegistration and handlers.AdminEditHandler.User. Two concurrent
// saves for a user without a profile can therefore leave that user with two
// rows. A plain `LEFT JOIN user_profiles ON user_id = …` then returns each of
// their messages twice, and because LIMIT counts the duplicated rows, a page
// can also come back short.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set (see newTestPool in chatgroups_test.go).
package chatgroups

import (
	"context"
	"strings"
	"testing"
)

// TestAdminListMessagesListsEachMessageOnceWhenSenderHasTwoProfiles seeds a
// sender with two profile rows and checks that staff see the message once,
// named from the OLDEST profile row (lowest user_profiles.id), so the name
// shown does not depend on which row the planner happens to reach first.
func TestAdminListMessagesListsEachMessageOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	// setFullName is a plain INSERT, so calling it twice leaves two rows for
	// the same user_id, the older one first.
	setFullName(t, pool, donor, "Oldest Profile Name")
	setFullName(t, pool, donor, "Newer Duplicate Profile Name")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{{UserID: donor, RoleInGroup: "donor"}})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	if _, err := s.PostMessage(ctx, groupID, donor, "posted exactly once"); err != nil {
		t.Fatalf("PostMessage: %v", err)
	}

	msgs, err := s.AdminListMessages(ctx, groupID, 0, 50)
	if err != nil {
		t.Fatalf("AdminListMessages: %v", err)
	}
	if len(msgs) != 1 {
		t.Fatalf("got %d messages, want 1: a sender with two user_profiles rows must not duplicate their message", len(msgs))
	}
	if msgs[0].SenderName != "Oldest Profile Name" {
		t.Errorf("SenderName = %q, want %q (the oldest profile row)", msgs[0].SenderName, "Oldest Profile Name")
	}
}

// TestListMessagesForMemberListsEachMessageOnceWhenSenderHasTwoProfiles is the
// member-side twin, and it checks both group kinds because one join serves
// both. In a TEAM group the label is the sender's real full_name, so a
// repeated row would show one message twice under two different names. In a
// MASKED group the label never reads the profile, but the row would still
// repeat, and the page would still come back short.
func TestListMessagesForMemberListsEachMessageOnceWhenSenderHasTwoProfiles(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	staff := makeTestUser(t, pool, "staff")
	sender := makeTestUser(t, pool, "volunteer")
	// The viewer is a second member: ListMessagesForMember requires an active
	// member, and CreateGroup gives the staff creator no member row.
	viewer := makeTestUser(t, pool, "volunteer")
	setFullName(t, pool, sender, "Oldest Profile Name")
	setFullName(t, pool, sender, "Newer Duplicate Profile Name")

	cases := []struct {
		name string
		kind Kind
		// wantLabel is the exact label expected; "" means "any label that
		// names neither profile row", which is all a masked group promises.
		wantLabel string
	}{
		{name: "team", kind: KindTeam, wantLabel: "Oldest Profile Name"},
		{name: "masked", kind: KindMasked, wantLabel: ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			groupID, err := s.CreateGroup(ctx, tc.kind, "Distribution team", staff, []MemberInput{
				{UserID: sender, RoleInGroup: "volunteer"},
				{UserID: viewer, RoleInGroup: "volunteer"},
			})
			if err != nil {
				t.Fatalf("CreateGroup: %v", err)
			}
			if _, err := s.PostMessage(ctx, groupID, sender, "posted exactly once"); err != nil {
				t.Fatalf("PostMessage: %v", err)
			}

			msgs, err := s.ListMessagesForMember(ctx, groupID, viewer, 0, 50)
			if err != nil {
				t.Fatalf("ListMessagesForMember: %v", err)
			}
			if len(msgs) != 1 {
				t.Fatalf("got %d messages, want 1: a sender with two user_profiles rows must not duplicate their message", len(msgs))
			}
			label := msgs[0].SenderLabel
			if tc.wantLabel != "" && label != tc.wantLabel {
				t.Errorf("SenderLabel = %q, want %q (the oldest profile row)", label, tc.wantLabel)
			}
			if tc.wantLabel == "" && strings.Contains(label, "Profile Name") {
				t.Errorf("masked SenderLabel = %q leaks a real profile name", label)
			}
		})
	}
}
