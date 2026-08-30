// J1 — the guest sign-up form has no "الاسم" (name) field, and the reason is
// not cosmetic.
//
// THE SHAPE OF THE GAP
// InsertGuest wrote a `users` row and nothing else. It created NO
// `user_profiles` row at all, which has two consequences:
//
//  1. There is nowhere to put a name, so the app cannot honestly show the
//     field the client asked for.
//  2. Far worse, and the actual root cause: every writer in the codebase that
//     does `UPDATE user_profiles … WHERE user_id = $1` silently updates ZERO
//     rows for a guest. SetFieldPrivacy, SetPrivacyExtras and friends all
//     return a nil error while storing nothing — a guest could toggle their
//     privacy switches all day and nothing would persist.
//
// These tests pin both halves: the profile row must exist after a guest
// registers, and an UPDATE keyed on user_id must actually hit it.
//
// They need a throwaway Postgres and are skipped unless TEST_DATABASE_URL is
// set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_j1          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_j1?sslmode=disable' \
//	  go test ./internal/users/ -run GuestProfile -v
package users

import (
	"context"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────

// makeGuest registers a guest through the real store method and removes the
// account (profile row included) when the test finishes.
func makeGuest(t *testing.T, pool *pgxpool.Pool, username, fullName string) int64 {
	t.Helper()
	ctx := context.Background()
	s := NewStore(pool)
	id, err := s.InsertGuest(ctx, username, "$2a$10$notarealhashjustfortests000000000000000000000000000000", fullName)
	if err != nil {
		t.Fatalf("InsertGuest: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// ─── Tests ──────────────────────────────────────────────────────────────

// A guest account must own exactly one user_profiles row the moment it is
// created — one, not zero (nothing to write to) and not two (the upgrade path
// would then update an arbitrary one of them).
func TestGuestProfileRowIsCreated(t *testing.T) {
	pool := newGrantorTestPool(t)
	id := makeGuest(t, pool, "j1rowcreated", "")

	var rows int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM user_profiles WHERE user_id = $1`, id).Scan(&rows); err != nil {
		t.Fatalf("count profiles: %v", err)
	}
	if rows != 1 {
		t.Fatalf("guest %d has %d user_profiles rows, want exactly 1", id, rows)
	}
}

// The name the guest typed at sign-up must actually be stored, not discarded.
func TestGuestProfileStoresName(t *testing.T) {
	pool := newGrantorTestPool(t)
	const name = "زيد العقراوي"
	id := makeGuest(t, pool, "j1namestored", "  "+name+"  ") // padded: must be trimmed

	var got string
	if err := pool.QueryRow(context.Background(),
		`SELECT full_name FROM user_profiles WHERE user_id = $1`, id).Scan(&got); err != nil {
		t.Fatalf("read full_name: %v", err)
	}
	if got != name {
		t.Fatalf("full_name = %q, want %q", got, name)
	}
}

// A guest who supplied no name — since one-tap guest entry, that is every
// guest — must still get a profile row, and that row must carry the
// placeholder rather than a blank.
//
// Blank was the previous behaviour and it is what this test used to assert.
// It was wrong in the same way the legacy "1" placeholder was wrong, just
// quieter: staff read an empty cell, which says "this account's name failed
// to save", not "this is a guest". gender and address stay blank — those are
// genuinely unknown, and nothing renders them as an identity.
func TestGuestProfileWithoutNameGetsThePlaceholder(t *testing.T) {
	pool := newGrantorTestPool(t)
	id := makeGuest(t, pool, "j1noname", "")

	var name, gender, address string
	if err := pool.QueryRow(context.Background(),
		`SELECT full_name, gender, address FROM user_profiles WHERE user_id = $1`, id,
	).Scan(&name, &gender, &address); err != nil {
		t.Fatalf("read profile: %v", err)
	}
	if name != DefaultGuestFullName {
		t.Fatalf("nameless guest got full_name=%q, want %q", name, DefaultGuestFullName)
	}
	if gender != "" || address != "" {
		t.Fatalf("nameless guest got gender=%q address=%q, want both empty", gender, address)
	}
}

// Whitespace is not a name. A client that posts "   " must be treated exactly
// like one that posts nothing, rather than storing a blank-looking name that
// defeats the placeholder.
func TestGuestProfileWhitespaceNameGetsThePlaceholder(t *testing.T) {
	pool := newGrantorTestPool(t)
	id := makeGuest(t, pool, "j1blankname", "   ")

	var name string
	if err := pool.QueryRow(context.Background(),
		`SELECT full_name FROM user_profiles WHERE user_id = $1`, id).Scan(&name); err != nil {
		t.Fatalf("read full_name: %v", err)
	}
	if name != DefaultGuestFullName {
		t.Fatalf("whitespace-name guest got full_name=%q, want %q", name, DefaultGuestFullName)
	}
}

// The root cause, stated as a test: an UPDATE keyed on user_id must affect a
// row. Before the fix every one of these silently affected zero rows, so the
// privacy setters reported success while storing nothing.
func TestGuestProfileUpdatesAffectARow(t *testing.T) {
	pool := newGrantorTestPool(t)
	ctx := context.Background()
	id := makeGuest(t, pool, "j1updatehits", "Guest Person")
	s := NewStore(pool)

	// The two app-reachable privacy writers, both of which are plain UPDATEs.
	if err := s.SetFieldPrivacy(ctx, id, []string{"phone"}); err != nil {
		t.Fatalf("SetFieldPrivacy: %v", err)
	}
	hidden, err := s.GetFieldPrivacy(ctx, id)
	if err != nil {
		t.Fatalf("GetFieldPrivacy: %v", err)
	}
	if len(hidden) != 1 || hidden[0] != "phone" {
		t.Fatalf("field_privacy = %v, want [phone] — the UPDATE hit no row", hidden)
	}

	if err := s.SetPrivacyExtras(ctx, id, PrivacyExtras{
		DisplayNameMode: "alias",
		AliasName:       "Anon",
	}); err != nil {
		t.Fatalf("SetPrivacyExtras: %v", err)
	}
	extras, err := s.GetPrivacyExtras(ctx, id)
	if err != nil {
		t.Fatalf("GetPrivacyExtras: %v", err)
	}
	if extras.DisplayNameMode != "alias" || extras.AliasName != "Anon" {
		t.Fatalf("privacy extras = %+v, want alias/Anon — the UPDATE hit no row", extras)
	}
}

// A guest who later attaches a phone flows through SubmitRegistration, which
// upserts on user_profiles. Now that the row already exists it must take the
// UPDATE branch: still one row afterwards, carrying the registration name.
func TestGuestProfileSurvivesUpgradeToFullAccount(t *testing.T) {
	pool := newGrantorTestPool(t)
	ctx := context.Background()
	id := makeGuest(t, pool, "j1upgrade", "Temporary Name")
	s := NewStore(pool)

	phone := fmt.Sprintf("9647000%06d", id%1000000)
	if err := s.UpgradeGuestPhone(ctx, id, phone); err != nil {
		t.Fatalf("UpgradeGuestPhone: %v", err)
	}
	if _, err := s.SubmitRegistration(ctx, id, "Real Name", "1990-01-01", "Erbil", 1,
		RegistrationExtras{Gender: "Male"}); err != nil {
		t.Fatalf("SubmitRegistration: %v", err)
	}

	var rows int
	var name string
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*), COALESCE(MAX(full_name), '') FROM user_profiles WHERE user_id = $1`, id,
	).Scan(&rows, &name); err != nil {
		t.Fatalf("count profiles: %v", err)
	}
	if rows != 1 {
		t.Fatalf("after upgrade the guest has %d user_profiles rows, want exactly 1", rows)
	}
	if name != "Real Name" {
		t.Fatalf("after upgrade full_name = %q, want %q", name, "Real Name")
	}
}
