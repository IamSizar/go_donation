// chatgroups_admin_kind_test.go — GroupKind, the one-column lookup the admin
// read routes run before deciding whether the caller must hold sensitive_data
// (OPOS #26409, user decision D1: masked groups need it, team groups do not).
//
// Needs the same throwaway Postgres as chatgroups_test.go — see newTestPool.
package chatgroups

import (
	"context"
	"errors"
	"testing"
)

// TestGroupKindReadsEachKind: GroupKind answers the kind the group was created
// with, for both kinds.
func TestGroupKindReadsEachKind(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	// A volunteer, not a donor: this test builds a group of BOTH kinds, and a
	// team group takes only volunteers and staff (ErrTeamMemberRole).
	member := makeTestUser(t, pool, "volunteer")

	for _, kind := range []Kind{KindMasked, KindTeam} {
		t.Run(string(kind), func(t *testing.T) {
			title := ""
			if kind == KindTeam {
				title = "Kind test team"
			}
			groupID, err := s.CreateGroup(ctx, kind, title, staff,
				[]MemberInput{{UserID: member, RoleInGroup: "volunteer"}})
			if err != nil {
				t.Fatalf("create %s group: %v", kind, err)
			}
			t.Cleanup(func() {
				ctx := context.Background()
				_, _ = pool.Exec(ctx, `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
				_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
				_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
			})

			got, err := s.GroupKind(ctx, groupID)

			if err != nil {
				t.Fatalf("GroupKind(%d): %v", groupID, err)
			}
			if got != kind {
				t.Fatalf("GroupKind(%d) = %q, want %q", groupID, got, kind)
			}
		})
	}
}

// TestGroupKindReturnsErrNotFoundForUnknownGroup: an id that names no group is
// ErrNotFound, which the handler turns into its usual 404.
func TestGroupKindReturnsErrNotFoundForUnknownGroup(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)

	_, err := s.GroupKind(context.Background(), 999999999)

	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
}
