// K12 — "من نحن" was one free-text blob with no way to give it named parts.
//
// THE SHAPE OF THE GAP
// The client asked for About Us to carry THREE NAMED sub-sections and to stay
// EXTENDABLE. `app_content` (migration 025) holds exactly one title and one
// body per locale per page, and the app renders precisely those two fields
// (content_page_screen.dart:90-118) — so there was no field to put a second
// sub-section in, and no column to order them by.
//
// What these tests pin down is the CONTRACT migration 111 establishes, because
// getting it wrong silently blanks a live page:
//
//	zero sections  -> body_* IS the page, untouched by the section endpoint
//	one or more    -> body_* is COMPOSED from the sections, in order
//
// The composition rule is what makes the feature visible in the app that is
// already installed: the Flutter screen reads body_*, so a page split into
// three named sub-sections still renders, as one document, without an app
// release.
//
// The DB-backed tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_k12          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k12?sslmode=disable' \
//	  go test ./internal/content/ -v
//
// TestComposeBody needs no database and always runs.
package content

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newSectionsTestPool brings a throwaway database up to date with the real
// migrations — the backfill in migration 111 is part of what is under test, so
// a fixture schema would not exercise it.
func newSectionsTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping content-sections integration test")
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

// seedPage installs a throwaway page to work on, so a test never edits one of
// the eight real pages and leaves the database in a state the next test reads.
func seedPage(t *testing.T, pool *pgxpool.Pool, slug, bodyEn, bodyAr string) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx,
		`INSERT INTO app_content (slug, title_en, body_en, body_ar)
		 VALUES ($1, 'Test page', $2, $3)
		 ON CONFLICT (slug) DO UPDATE SET body_en = EXCLUDED.body_en,
		                                  body_ar = EXCLUDED.body_ar`,
		slug, bodyEn, bodyAr); err != nil {
		t.Fatalf("seed page %s: %v", slug, err)
	}
	t.Cleanup(func() {
		// CASCADE on the FK takes the sections with it.
		if _, err := pool.Exec(context.Background(),
			`DELETE FROM app_content WHERE slug = $1`, slug); err != nil {
			t.Logf("cleanup page %s: %v", slug, err)
		}
	})
}

// ─── The migration's backfill ───────────────────────────────────────────

// TestBackfillMovesBlobIntoFirstSection is the regression guard for the
// dangerous half of migration 111. Had the backfill been skipped, the first
// save from the new editor would compose a page out of an empty list and blank
// live content — so a page that existed before 111 must come out of it already
// carrying its own text as sub-section #1, with an EMPTY title (the page
// heading is app_content.title_*; repeating it would double it).
//
// It builds its own pre-111 page and REPLAYS the real migration over it rather
// than inspecting whatever the eight shipped pages happen to hold: those are
// editable, so asserting on them would turn any later edit — including one made
// while verifying this feature by hand — into a failing test. Replaying is safe
// and is itself worth pinning: the file is written to be re-runnable
// (CREATE TABLE IF NOT EXISTS, and a backfill guarded by NOT EXISTS), so the
// pages that already have sub-sections are skipped and only the new one is
// filled.
func TestBackfillMovesBlobIntoFirstSection(t *testing.T) {
	pool := newSectionsTestPool(t)
	ctx := context.Background()
	const slug = "k12-backfill"
	seedPage(t, pool, slug, "The blob this page had before K12.", "النص قبل K12.")

	// Pre-111 state for this page: a blob and no sub-sections.
	if _, err := pool.Exec(ctx,
		`DELETE FROM app_content_sections WHERE slug = $1`, slug); err != nil {
		t.Fatalf("clear sections of %s: %v", slug, err)
	}
	// Un-record the migration so the runner replays it.
	if _, err := pool.Exec(ctx,
		`DELETE FROM schema_migrations WHERE version = '111_app_content_sections.sql'`); err != nil {
		t.Fatalf("un-record migration 111: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		t.Fatalf("replay migrations: %v", err)
	}

	rows, err := pool.Query(ctx, `
		SELECT display_order, title_en, body_en, body_ar
		  FROM app_content_sections
		 WHERE slug = $1
		 ORDER BY display_order, id`, slug)
	if err != nil {
		t.Fatalf("read backfilled sections: %v", err)
	}
	defer rows.Close()

	type row struct {
		order          int
		titleEn        string
		bodyEn, bodyAr string
	}
	var got []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.order, &r.titleEn, &r.bodyEn, &r.bodyAr); err != nil {
			t.Fatalf("scan: %v", err)
		}
		got = append(got, r)
	}
	if len(got) != 1 {
		t.Fatalf("backfill produced %d sub-sections, want exactly 1", len(got))
	}
	if got[0].order != 0 {
		t.Errorf("backfilled sub-section has display_order %d, want 0", got[0].order)
	}
	if got[0].bodyEn != "The blob this page had before K12." {
		t.Errorf("backfilled body_en = %q, want the page's own blob", got[0].bodyEn)
	}
	if got[0].bodyAr != "النص قبل K12." {
		t.Errorf("backfilled body_ar = %q, want the page's own blob", got[0].bodyAr)
	}
	if got[0].titleEn != "" {
		t.Errorf("backfilled title_en = %q, want empty — the page heading is already app_content.title_en", got[0].titleEn)
	}

	// The composed blob must equal what the page already served, or the very
	// first save from the editor would change live text.
	if composed := composeBody([]Section{{BodyEn: got[0].bodyEn}}, "en"); composed != "The blob this page had before K12." {
		t.Errorf("composing the backfilled sub-section gives %q, want the original blob", composed)
	}
}

// ─── Composition ────────────────────────────────────────────────────────

// TestComposeBody pins the exact text the already-installed app will render
// for a page that has been split up. It needs no database.
func TestComposeBody(t *testing.T) {
	tests := []struct {
		name     string
		sections []Section
		lang     string
		want     string
	}{
		{
			name:     "no sections composes to nothing",
			sections: nil,
			lang:     "en",
			want:     "",
		},
		{
			// The backfilled shape. Composition MUST be the identity here, or
			// migration 111 changes live pages the moment staff press Save.
			name:     "single untitled section is reproduced verbatim",
			sections: []Section{{BodyEn: "One paragraph."}},
			lang:     "en",
			want:     "One paragraph.",
		},
		{
			name: "named sections are headed by their own name",
			sections: []Section{
				{TitleEn: "The app", BodyEn: "First."},
				{TitleEn: "The organization", BodyEn: "Second."},
				{TitleEn: "Our goals", BodyEn: "Third."},
			},
			lang: "en",
			want: "The app\n\nFirst.\n\nThe organization\n\nSecond.\n\nOur goals\n\nThird.",
		},
		{
			// A locale the owner has not written yet must not contribute an
			// empty gap — otherwise a half-translated page renders as a run of
			// blank lines.
			name: "sections empty in this locale are skipped",
			sections: []Section{
				{TitleEn: "The app", BodyEn: "First.", TitleAr: "", BodyAr: ""},
				{TitleAr: "المنظمة", BodyAr: "ثانياً."},
			},
			lang: "ar",
			want: "المنظمة\n\nثانياً.",
		},
		{
			name:     "a title with no body still names the block",
			sections: []Section{{TitleEn: "Coming soon"}},
			lang:     "en",
			want:     "Coming soon",
		},
		{
			// Staff paste prose with trailing blank lines; the join must not
			// multiply them into a growing gap on every save.
			name:     "surrounding whitespace is trimmed",
			sections: []Section{{BodyEn: "  Padded.\n\n"}, {BodyEn: "\nNext.  "}},
			lang:     "en",
			want:     "Padded.\n\nNext.",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := composeBody(tc.sections, tc.lang); got != tc.want {
				t.Errorf("composeBody(%s) = %q, want %q", tc.lang, got, tc.want)
			}
		})
	}
}

// ─── The store ──────────────────────────────────────────────────────────

// TestReplaceSectionsRoundTrips is the "extendable, ordered" half of K12: the
// list saves, reads back in the order it was given, and survives being
// extended.
func TestReplaceSectionsRoundTrips(t *testing.T) {
	pool := newSectionsTestPool(t)
	store := New(pool)
	ctx := context.Background()
	seedPage(t, pool, "k12-roundtrip", "Original blob.", "النص الأصلي.")

	want := []Section{
		{Order: 0, TitleEn: "One", BodyEn: "First body.", TitleAr: "واحد", BodyAr: "الفقرة الأولى."},
		{Order: 1, TitleEn: "Two", BodyEn: "Second body."},
		{Order: 2, TitleEn: "Three", BodyEn: "Third body."},
	}
	if err := store.ReplaceSections(ctx, "k12-roundtrip", want, 42); err != nil {
		t.Fatalf("ReplaceSections: %v", err)
	}

	got, err := store.ListSections(ctx, "k12-roundtrip")
	if err != nil {
		t.Fatalf("ListSections: %v", err)
	}
	if len(got) != len(want) {
		t.Fatalf("got %d sections, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i].TitleEn != want[i].TitleEn || got[i].BodyEn != want[i].BodyEn {
			t.Errorf("section %d = (%q, %q), want (%q, %q)",
				i, got[i].TitleEn, got[i].BodyEn, want[i].TitleEn, want[i].BodyEn)
		}
		if got[i].Order != i {
			t.Errorf("section %d has display_order %d, want %d", i, got[i].Order, i)
		}
	}
	if got[0].TitleAr != "واحد" {
		t.Errorf("Arabic title did not round-trip: %q", got[0].TitleAr)
	}

	// Extendable: a fourth sub-section needs no schema or code change.
	if err := store.ReplaceSections(ctx, "k12-roundtrip",
		append(want, Section{Order: 3, TitleEn: "Four", BodyEn: "Fourth body."}), 42); err != nil {
		t.Fatalf("ReplaceSections (extend): %v", err)
	}
	got, err = store.ListSections(ctx, "k12-roundtrip")
	if err != nil {
		t.Fatalf("ListSections after extend: %v", err)
	}
	if len(got) != 4 {
		t.Fatalf("after extending, got %d sections, want 4", len(got))
	}
}

// TestReplaceSectionsComposesLegacyBody is the contract that keeps K12 from
// shipping dark: the already-installed app reads app_content.body_*, so saving
// sub-sections has to leave a composed blob behind in that same column.
func TestReplaceSectionsComposesLegacyBody(t *testing.T) {
	pool := newSectionsTestPool(t)
	store := New(pool)
	ctx := context.Background()
	seedPage(t, pool, "k12-compose", "Original blob.", "النص الأصلي.")

	if err := store.ReplaceSections(ctx, "k12-compose", []Section{
		{Order: 0, TitleEn: "The app", BodyEn: "About the app."},
		{Order: 1, TitleEn: "The organization", BodyEn: "About us."},
	}, 7); err != nil {
		t.Fatalf("ReplaceSections: %v", err)
	}

	page, err := store.Get(ctx, "k12-compose")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	const wantEn = "The app\n\nAbout the app.\n\nThe organization\n\nAbout us."
	if page.BodyEn != wantEn {
		t.Errorf("composed body_en = %q, want %q", page.BodyEn, wantEn)
	}
	// Arabic was never given a section, so this locale composes to nothing and
	// the app's own English fallback takes over — the alternative, leaving the
	// old Arabic blob in place, would keep serving text the page no longer says.
	if page.BodyAr != "" {
		t.Errorf("composed body_ar = %q, want empty (no Arabic section was saved)", page.BodyAr)
	}
}

// TestReplaceSectionsEmptyListLeavesBodyAlone protects the escape hatch. A page
// with no sub-sections is a plain blob page — exactly what every page was
// before K12 — so clearing the list must NOT wipe the text the plain body
// editor is still responsible for.
func TestReplaceSectionsEmptyListLeavesBodyAlone(t *testing.T) {
	pool := newSectionsTestPool(t)
	store := New(pool)
	ctx := context.Background()
	seedPage(t, pool, "k12-empty", "Keep me.", "احتفظ بي.")

	if err := store.ReplaceSections(ctx, "k12-empty", nil, 7); err != nil {
		t.Fatalf("ReplaceSections(nil): %v", err)
	}

	page, err := store.Get(ctx, "k12-empty")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if page.BodyEn != "Keep me." {
		t.Errorf("body_en = %q after clearing the section list, want it untouched", page.BodyEn)
	}
	if page.BodyAr != "احتفظ بي." {
		t.Errorf("body_ar = %q after clearing the section list, want it untouched", page.BodyAr)
	}
	secs, err := store.ListSections(ctx, "k12-empty")
	if err != nil {
		t.Fatalf("ListSections: %v", err)
	}
	if len(secs) != 0 {
		t.Errorf("got %d sections after clearing, want 0", len(secs))
	}
}
