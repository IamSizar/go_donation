// H23 — a donor (grantor) had no identity code, so only their real name
// identified them.
//
// THE SHAPE OF THE GAP
// The client asked for auto-generated identity codes "instead of real names"
// for donors AND beneficiaries, so a person can be referred to without
// exposing who they are. Two of the three roles got one:
//
//	role 2 (eligible recipient) -> ER-%06d, assigned in SubmitRegistration
//	role 3 (volunteer)          -> VL-%06d, assigned by EnsureVolunteerCode
//	role 1 (grantor / donor)    -> nothing at all
//
// So the one role the client named FIRST was the one with no code, and staff
// had no way to refer to a donor except by name or phone number. The staff
// search made the asymmetry concrete: it matches recipient_code and
// volunteer_code, so quoting an ER- or VL- code found a person while a donor
// could only be found by typing their real name.
//
// These tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_h23          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h23?sslmode=disable' \
//	  go test ./internal/users/ -run GrantorCode -v
package users

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newGrantorTestPool brings a throwaway database up to date with the real
// migrations — the backfill in migration 105 is part of what is under test, so
// a fixture schema would not exercise it.
func newGrantorTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping grantor-code integration test")
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

// makeUser inserts a user + profile for the given role and removes both when
// the test finishes, so the table is left as found. The phone is derived from
// the test name because users.phone is UNIQUE and two tests in this file each
// need their own donor.
func makeUser(t *testing.T, pool *pgxpool.Pool, roleID int) int64 {
	t.Helper()
	ctx := context.Background()
	// Reserved-range number, unique per test, so a real account can never
	// collide with a fixture and a failed cleanup cannot break the next run.
	phone := "96470000" + pad6(int64(len(t.Name())))[1:] + itoaLast(t.Name())
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, $2, 1) RETURNING id`,
		phone, roleID,
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	// gender is NOT NULL on user_profiles, so the fixture has to supply it.
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, address, gender)
		 VALUES ($1, 'Test Person', 'Erbil', 'Male')`,
		id); err != nil {
		t.Fatalf("insert profile: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// itoaLast returns two digits derived from a test name, giving each test in
// this file its own fixture phone number without a shared counter.
func itoaLast(name string) string {
	sum := 0
	for _, r := range name {
		sum += int(r)
	}
	return pad6(int64(sum % 100))[4:]
}

func grantorCodeOf(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	var code string
	if err := pool.QueryRow(context.Background(),
		`SELECT grantor_code FROM user_profiles WHERE user_id = $1`, userID).Scan(&code); err != nil {
		t.Fatalf("read grantor_code for %d: %v", userID, err)
	}
	return code
}

// ─── The gap ────────────────────────────────────────────────────────────

// TestGrantorCodeIsAssignedOnce is the H23 row: a donor must get an identity
// code the same way a recipient and a volunteer already do.
func TestGrantorCodeIsAssignedOnce(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	uid := makeUser(t, pool, 1)

	if err := s.EnsureGrantorCode(context.Background(), uid); err != nil {
		t.Fatalf("EnsureGrantorCode: %v", err)
	}
	got := grantorCodeOf(t, pool, uid)
	want := "GR-" + pad6(uid)
	if got != want {
		t.Fatalf("donor got no identity code: grantor_code = %q, want %q", got, want)
	}
}

// TestGrantorCodeIsStableOnceAssigned pins the "assigned once" half. A code is
// an identifier staff quote in conversation and write on paperwork; if a later
// profile save could regenerate it, it would stop identifying anybody.
func TestGrantorCodeIsStableOnceAssigned(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 1)

	// Someone edited the code by hand, the way an operator might.
	if _, err := pool.Exec(ctx,
		`UPDATE user_profiles SET grantor_code = 'GR-CUSTOM' WHERE user_id = $1`, uid); err != nil {
		t.Fatalf("seed custom code: %v", err)
	}
	if err := s.EnsureGrantorCode(ctx, uid); err != nil {
		t.Fatalf("EnsureGrantorCode: %v", err)
	}
	if got := grantorCodeOf(t, pool, uid); got != "GR-CUSTOM" {
		t.Fatalf("an existing identity code was overwritten: got %q, want %q", got, "GR-CUSTOM")
	}
}

// TestGrantorCodeRejectsInvalidUser — a guard clause, mirroring
// EnsureVolunteerCode. Silently succeeding on a bad id would hide a caller bug.
func TestGrantorCodeRejectsInvalidUser(t *testing.T) {
	s := &Store{} // no pool needed: the guard returns before any query
	if err := s.EnsureGrantorCode(context.Background(), 0); err == nil {
		t.Fatal("EnsureGrantorCode(0) returned nil; want an error")
	}
}

// TestExistingGrantorsWereBackfilled proves migration 105 did not leave the
// donors who registered before it without a code — a code that only new donors
// get would not answer the client's ask for the people already in the system.
func TestExistingGrantorsWereBackfilled(t *testing.T) {
	pool := newGrantorTestPool(t)
	var missing int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*)
		   FROM user_profiles p
		   JOIN users u ON u.id = p.user_id
		  WHERE u.role_id = 1 AND p.grantor_code = ''`).Scan(&missing); err != nil {
		t.Fatalf("count un-backfilled grantors: %v", err)
	}
	if missing != 0 {
		t.Errorf("%d existing donors still have no identity code after migration 105", missing)
	}
}
