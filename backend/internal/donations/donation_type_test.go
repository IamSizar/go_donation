// M7 — a donation type added from the dashboard must actually be honoured.
//
// THE SHAPE OF THE BUG
// The client asked for "التحكم الكامل بجميع الخيارات من لوحة الإدارة دون
// الحاجة إلى تحديث برمجي" over four things. Three are rows already: projects
// (project_categories), editing/deleting them, and payment methods. The
// donor-facing giving TYPE was not. normalizeDonationType was a closed switch:
//
//	case "zakat":            return "zakat"
//	case "sadaqah", "sadaqa": return "sadaqah"
//	default:                 return "general"
//
// So an operator could add nothing. Worse than a rejection, the `default` arm
// made the failure SILENT: had a fourth type ever reached this function it
// would have been quietly rewritten to "general" and filed under the general
// fund — the donor's stated intent replaced with a different one, with no
// error anywhere. That silent-rewrite property is exactly why this is tested
// rather than eyeballed.
//
// WHAT IS DELIBERATELY NOT TESTED HERE
// donation_kind. It is a different column with a live CHECK constraint
// (001_full_v2.sql:390) and a code flow behind each value; extending it is an
// owner decision, not this fix. See migration 103's header.
//
// The DB-backed cases need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/handlers/admin_delete_trash_test.go):
//
//	createdb godonation_m7          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_m7?sslmode=disable' \
//	  go test ./internal/donations/ -run DonationType -v
package donations

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/donationtypes"
)

// ─── Harness ────────────────────────────────────────────────────────────

// testPool opens the throwaway database and brings its schema up to date, or
// skips the test when none is configured. Same harness as
// internal/auth/dashboard_access_test.go — real migrations rather than a
// hand-written fixture, so migration 103 is exercised by this test too.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping DB-backed donation-type test")
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

// addType inserts a donation type the way the dashboard's Add button does, and
// removes it again when the test finishes so the table is left as found.
func addType(t *testing.T, pool *pgxpool.Pool, slug, nameEN string) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx,
		`INSERT INTO donation_types (slug, name_en, display_order)
		 VALUES ($1, $2, 99) ON CONFLICT (slug) DO NOTHING`, slug, nameEN); err != nil {
		t.Fatalf("seed donation type %q: %v", slug, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM donation_types WHERE slug = $1`, slug)
	})
}

// ─── The defect ─────────────────────────────────────────────────────────

// TestDonationTypeAddedFromDashboardIsHonoured is the row M7 is about: an
// operator adds a type in the dashboard, a donor picks it, and the stored
// donation must carry it rather than "general".
func TestDonationTypeAddedFromDashboardIsHonoured(t *testing.T) {
	pool := testPool(t)
	addType(t, pool, "kaffara", "Kaffara")

	s := NewStore(pool)
	s.Types = donationtypes.New(pool)

	got := s.normalizeDonationType(context.Background(), "kaffara")
	if got != "kaffara" {
		t.Fatalf("a dashboard-added donation type was discarded: got %q, want %q.\n"+
			"This is the silent rewrite M7 reports — the donor's choice was filed as something else.", got, "kaffara")
	}
}

// TestDonationTypeDeactivatedIsNotAccepted pins the other half of admin
// control: switching a type off in the dashboard must stop new donations from
// using it. Without this, "active" would be a decoration on the list screen.
func TestDonationTypeDeactivatedIsNotAccepted(t *testing.T) {
	pool := testPool(t)
	addType(t, pool, "retired_type", "Retired type")
	if _, err := pool.Exec(context.Background(),
		`UPDATE donation_types SET active = 0 WHERE slug = 'retired_type'`); err != nil {
		t.Fatalf("deactivate: %v", err)
	}

	s := NewStore(pool)
	s.Types = donationtypes.New(pool)

	if got := s.normalizeDonationType(context.Background(), "retired_type"); got != "general" {
		t.Fatalf("a deactivated donation type was still accepted: got %q, want %q", got, "general")
	}
}

// TestDonationTypeSeededSetStillWorks guards the three shipped types against
// this change. Migration 103 seeds them, so they must resolve through the
// table exactly as the old switch resolved them.
func TestDonationTypeSeededSetStillWorks(t *testing.T) {
	pool := testPool(t)
	s := NewStore(pool)
	s.Types = donationtypes.New(pool)

	for _, tc := range []struct{ in, want string }{
		{"zakat", "zakat"},
		{"sadaqah", "sadaqah"},
		{"general", "general"},
		{"ZAKAT", "zakat"},         // case-insensitive, as before
		{"  sadaqah  ", "sadaqah"}, // whitespace-tolerant, as before
		{"nonsense", "general"},    // unknown still falls back, as before
		{"", "general"},            // empty still falls back, as before
	} {
		if got := s.normalizeDonationType(context.Background(), tc.in); got != tc.want {
			t.Errorf("normalizeDonationType(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// ─── The fallback ───────────────────────────────────────────────────────

// TestDonationTypeFallsBackWhenNoStoreWired is a pure test — no database — and
// it is the reason a donation cannot be lost to this change. If the types
// store is not wired (or, at runtime, if its query fails), the three shipped
// values must still resolve. A donation must never fail to save because a
// lookup table was unreachable.
func TestDonationTypeFallsBackWhenNoStoreWired(t *testing.T) {
	s := &Store{} // no Pool, no Types — the degraded case

	for _, tc := range []struct{ in, want string }{
		{"zakat", "zakat"},
		{"sadaqa", "sadaqah"}, // the legacy spelling the old switch accepted
		{"general", "general"},
		{"kaffara", "general"}, // unknown to the fallback list
	} {
		if got := s.normalizeDonationType(context.Background(), tc.in); got != tc.want {
			t.Errorf("fallback normalizeDonationType(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
