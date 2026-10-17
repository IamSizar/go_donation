// R2 #35/#37 — the «مستخدم عام» (general user): a signed-in account with
// limited access, chosen at registration, approved at once, and upgraded later
// by choosing a real role (which staff approve like any new registration).
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set.
package users

import (
	"context"
	"errors"
	"testing"
)

func regStatusOf(t *testing.T, s *Store, uid int64) (status string, role *int) {
	t.Helper()
	if err := s.Pool.QueryRow(context.Background(),
		`SELECT registration_status, role_id FROM users WHERE id = $1`, uid).Scan(&status, &role); err != nil {
		t.Fatalf("read status: %v", err)
	}
	return status, role
}

func TestGeneralUserIsApprovedAtOnceWithoutAnAddress(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	uid := makeUser(t, pool, 0)

	status, err := s.SubmitRegistration(context.Background(), uid, "Sara", "", "", RoleGeneral, RegistrationExtras{})
	if err != nil {
		t.Fatalf("SubmitRegistration general: %v", err)
	}
	if status != "approved" {
		t.Fatalf("status = %q, want approved (a general user needs no review)", status)
	}
	if st, role := regStatusOf(t, s, uid); st != "approved" || role == nil || *role != RoleGeneral {
		t.Fatalf("stored status=%q role=%v", st, role)
	}
}

func TestGeneralUserUpgradeGoesToStaffReview(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	uid := makeUser(t, pool, 0)
	ctx := context.Background()

	if _, err := s.SubmitRegistration(ctx, uid, "Sara", "", "", RoleGeneral, RegistrationExtras{}); err != nil {
		t.Fatalf("general: %v", err)
	}
	status, err := s.SubmitRegistration(ctx, uid, "Sara", "", "Erbil", 3, RegistrationExtras{})
	if err != nil {
		t.Fatalf("upgrade to volunteer: %v", err)
	}
	if status != "pending" {
		t.Fatalf("upgrade status = %q, want pending (staff must approve a real role)", status)
	}
}

func TestApprovedRealRoleIsNeverDowngradedToGeneral(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	uid := makeUser(t, pool, 1) // donor
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `UPDATE users SET registration_status='approved' WHERE id=$1`, uid); err != nil {
		t.Fatal(err)
	}
	_, err := s.SubmitRegistration(ctx, uid, "Test Person", "", "", RoleGeneral, RegistrationExtras{})
	if !errors.Is(err, ErrRegistrationNotSubmittable) {
		t.Fatalf("err = %v, want ErrRegistrationNotSubmittable", err)
	}
	if _, role := regStatusOf(t, s, uid); role == nil || *role != 1 {
		t.Fatalf("role changed to %v, want it to stay a donor", role)
	}
}
