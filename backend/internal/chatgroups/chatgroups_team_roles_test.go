// chatgroups_team_roles_test.go — a team group is for volunteers and staff
// only (Zaid's decision, 2026-09-16).
//
// WHY THE RULE EXISTS
// A kind='team' group serves REAL NAMES to its members (chatgroups_reads.go's
// sender-label CASE). Nothing stopped staff putting a donor and a beneficiary
// in one, which would show them each other's real identity — exactly what
// OPOS #25284 built the masked kind to prevent. A masked group is where a
// donor and a beneficiary belong, and nothing about masked groups changes.
//
// WHAT IS AUTHORITATIVE
// users.role_id (1 donor, 2 beneficiary, 3 volunteer — handlers/registration.go
// accepts 1..3 and branches on each) and users.staff_tier (the single
// definition of a staff account — internal/auth/middleware.go,
// internal/notify). NOT chat_group_members.role_in_group, which is a
// staff-typed free-text column with no CHECK constraint (migration 120 calls
// it "informational") and so cannot be trusted to say who someone is.
//
// Needs the same throwaway Postgres as chatgroups_test.go — see newTestPool.
package chatgroups

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Helpers ────────────────────────────────────────────────────────────

// countMemberships counts userID's chat_group_members rows in ANY group.
// A refused write is proved by this being zero: the member list is the only
// thing a create writes besides the thread, so a member with no row anywhere
// means no group was left holding them.
//
// Counted per user rather than per group because a test database is reused
// across runs and hands out the same user ids each time (raiseUserIDFloor
// resets the sequence to the same floor), so a count keyed on a staff id would
// also see groups left behind by an earlier run.
func countMemberships(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_group_members WHERE user_id = $1`, userID,
	).Scan(&n); err != nil {
		t.Fatalf("count memberships for user %d: %v", userID, err)
	}
	return n
}

// makeTeamGroup creates a team group whose only member is a volunteer, and
// cleans it up. Every add-member test starts from one.
func makeTeamGroup(t *testing.T, pool *pgxpool.Pool, s *Store, staffID int64) int64 {
	t.Helper()
	ctx := context.Background()
	volunteer := makeTestUser(t, pool, "volunteer")
	groupID, err := s.CreateGroup(ctx, KindTeam, "Team roles test", staffID,
		[]MemberInput{{UserID: volunteer, RoleInGroup: "volunteer"}})
	if err != nil {
		t.Fatalf("create team group: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_audit_log WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})
	return groupID
}

// ─── CreateGroup ────────────────────────────────────────────────────────

// TestCreateTeamGroupRefusesDonorOrBeneficiary: neither a donor nor a
// beneficiary account can be in the member list of a new team group, and the
// refusal leaves nothing behind — not the thread, not the volunteer listed
// before them.
func TestCreateTeamGroupRefusesDonorOrBeneficiary(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()

	for _, role := range []string{"donor", "beneficiary"} {
		t.Run(role, func(t *testing.T) {
			staff := makeTestUser(t, pool, "staff")
			volunteer := makeTestUser(t, pool, "volunteer")
			refused := makeTestUser(t, pool, role)

			_, err := s.CreateGroup(ctx, KindTeam, "Distribution team", staff, []MemberInput{
				{UserID: volunteer, RoleInGroup: "volunteer"},
				{UserID: refused, RoleInGroup: role},
			})

			if !errors.Is(err, ErrTeamMemberRole) {
				t.Fatalf("CreateGroup with a %s = %v, want ErrTeamMemberRole", role, err)
			}
			if n := countMemberships(t, pool, volunteer); n != 0 {
				t.Fatalf("the volunteer listed first has %d membership(s), want 0 — a refused create must roll back", n)
			}
			if n := countMemberships(t, pool, refused); n != 0 {
				t.Fatalf("the refused %s has %d membership(s), want 0", role, n)
			}
		})
	}
}

// TestCreateTeamGroupAcceptsVolunteersAndStaff: the two kinds of account a
// team group is for go in exactly as before.
func TestCreateTeamGroupAcceptsVolunteersAndStaff(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	volunteer := makeTestUser(t, pool, "volunteer")
	coordinator := makeTestUser(t, pool, "staff")

	groupID, err := s.CreateGroup(ctx, KindTeam, "Distribution team", staff, []MemberInput{
		{UserID: volunteer, RoleInGroup: "volunteer"},
		{UserID: coordinator, RoleInGroup: "staff"},
	})

	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})
	var n int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM chat_group_members WHERE group_id = $1`, groupID).Scan(&n); err != nil {
		t.Fatalf("count members: %v", err)
	}
	if n != 2 {
		t.Fatalf("members = %d, want 2", n)
	}
}

// TestCreateTeamGroupAcceptsStaffHoldingTheDonorRole: staff_tier is what makes
// an account staff. A coordinator whose users.role_id is still 1 — they
// registered as a donor before being given dashboard access — is staff, and a
// team group takes them.
func TestCreateTeamGroupAcceptsStaffHoldingTheDonorRole(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donorRoleStaff := makeTestUser(t, pool, "donor")
	if _, err := pool.Exec(ctx,
		`UPDATE users SET staff_tier = 'supervisor' WHERE id = $1`, donorRoleStaff); err != nil {
		t.Fatalf("give the donor a staff tier: %v", err)
	}

	groupID, err := s.CreateGroup(ctx, KindTeam, "Distribution team", staff,
		[]MemberInput{{UserID: donorRoleStaff, RoleInGroup: "staff"}})

	if err != nil {
		t.Fatalf("CreateGroup with a staff account whose role_id is 1: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})
}

// TestCreateMaskedGroupStillTakesAnyMix: the rule is about team groups only.
// A masked group is exactly where a donor and a beneficiary belong, and it
// still takes them — they see each other's label, never a name.
func TestCreateMaskedGroupStillTakesAnyMix(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	donor := makeTestUser(t, pool, "donor")
	beneficiary := makeTestUser(t, pool, "beneficiary")

	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff, []MemberInput{
		{UserID: donor, RoleInGroup: "donor"},
		{UserID: beneficiary, RoleInGroup: "beneficiary"},
	})

	if err != nil {
		t.Fatalf("CreateGroup(masked): %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})
}

// ─── AddMember ──────────────────────────────────────────────────────────

// TestAddMemberToTeamGroupRefusesDonorOrBeneficiary: the same rule on the
// other path staff use, adding one person to a group that already exists.
// Nothing is written.
func TestAddMemberToTeamGroupRefusesDonorOrBeneficiary(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	groupID := makeTeamGroup(t, pool, s, staff)

	for _, role := range []string{"donor", "beneficiary"} {
		t.Run(role, func(t *testing.T) {
			refused := makeTestUser(t, pool, role)

			err := s.AddMember(ctx, groupID, MemberInput{UserID: refused, RoleInGroup: role}, staff)

			if !errors.Is(err, ErrTeamMemberRole) {
				t.Fatalf("AddMember(%s) = %v, want ErrTeamMemberRole", role, err)
			}
			var n int
			if err := pool.QueryRow(ctx,
				`SELECT COUNT(*) FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
				groupID, refused).Scan(&n); err != nil {
				t.Fatalf("count member rows: %v", err)
			}
			if n != 0 {
				t.Fatalf("%d row(s) written for the refused %s, want 0", n, role)
			}
		})
	}
}

// TestAddMemberToTeamGroupIgnoresTheTypedRoleInGroup: role_in_group is
// staff-typed free text with no constraint behind it, so it decides nothing.
// Typing "volunteer" over a donor account does not get them in, and typing
// "donor" over a volunteer account does not keep them out.
func TestAddMemberToTeamGroupIgnoresTheTypedRoleInGroup(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	groupID := makeTeamGroup(t, pool, s, staff)
	donor := makeTestUser(t, pool, "donor")
	volunteer := makeTestUser(t, pool, "volunteer")

	t.Run("a donor typed as a volunteer is still refused", func(t *testing.T) {
		err := s.AddMember(ctx, groupID, MemberInput{UserID: donor, RoleInGroup: "volunteer"}, staff)
		if !errors.Is(err, ErrTeamMemberRole) {
			t.Fatalf("AddMember = %v, want ErrTeamMemberRole", err)
		}
	})
	t.Run("a volunteer typed as a donor is still accepted", func(t *testing.T) {
		if err := s.AddMember(ctx, groupID, MemberInput{UserID: volunteer, RoleInGroup: "donor"}, staff); err != nil {
			t.Fatalf("AddMember = %v, want nil", err)
		}
	})
}

// TestAddMemberDoesNotReactivateADonorInATeamGroup: OPOS #26410 brings a
// REMOVED member back rather than refusing them. That path obeys this rule
// too, so a donor who is in a team group from before the rule existed cannot
// be brought back after being removed. The row stays removed.
func TestAddMemberDoesNotReactivateADonorInATeamGroup(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	groupID := makeTeamGroup(t, pool, s, staff)
	donor := makeTestUser(t, pool, "donor")

	// Written straight to the table: a row the rule would refuse today, which
	// is exactly what an existing production team group may hold.
	if _, err := pool.Exec(ctx, `
		INSERT INTO chat_group_members (group_id, user_id, role_in_group, masked, added_by_staff_id, removed_at, removed_by)
		VALUES ($1, $2, 'donor', false, $3, now(), $3)`, groupID, donor, staff); err != nil {
		t.Fatalf("seed the removed donor: %v", err)
	}

	err := s.AddMember(ctx, groupID, MemberInput{UserID: donor, RoleInGroup: "volunteer"}, staff)

	if !errors.Is(err, ErrTeamMemberRole) {
		t.Fatalf("AddMember (reactivating) = %v, want ErrTeamMemberRole", err)
	}
	var stillRemoved bool
	if err := pool.QueryRow(ctx,
		`SELECT removed_at IS NOT NULL FROM chat_group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, donor).Scan(&stillRemoved); err != nil {
		t.Fatalf("read the seeded row: %v", err)
	}
	if !stillRemoved {
		t.Fatal("the removed donor was reactivated into a team group")
	}
}

// TestAddMemberToMaskedGroupStillTakesADonor: the add-member path for masked
// groups is untouched.
func TestAddMemberToMaskedGroupStillTakesADonor(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	ctx := context.Background()
	staff := makeTestUser(t, pool, "staff")
	beneficiary := makeTestUser(t, pool, "beneficiary")
	donor := makeTestUser(t, pool, "donor")
	groupID, err := s.CreateGroup(ctx, KindMasked, "", staff,
		[]MemberInput{{UserID: beneficiary, RoleInGroup: "beneficiary"}})
	if err != nil {
		t.Fatalf("create masked group: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_members WHERE group_id = $1`, groupID)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_group_threads WHERE id = $1`, groupID)
	})

	if err := s.AddMember(ctx, groupID, MemberInput{UserID: donor, RoleInGroup: "donor"}, staff); err != nil {
		t.Fatalf("AddMember(masked) = %v, want nil", err)
	}
}
