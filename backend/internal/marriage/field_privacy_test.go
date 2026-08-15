// L19 — "خطوبتي" had one whole-profile audience dropdown and no way to say
// "show my age, hide my photo".
//
// THE SHAPE OF THE GAP
// The engagement form offered a single visibility_level with three values.
// Two things were wrong underneath it:
//
//  1. There was no per-field column at all, so a picker had nowhere to write.
//  2. Store.List SELECTed every field — gender, age, city, religion, weight,
//     height, photo — and masked none of them. It did not even use
//     visibility_level as a query condition, so a profile explicitly set to
//     'private' was browsable exactly like a public one.
//
// So the whole-profile selector that DID exist was itself only half enforced,
// and a per-field picker added on top would have been a second row of controls
// that changed nothing. On a matchmaking profile that is a privacy incident,
// not a cosmetic gap — which is why the app deliberately did not ship one.
//
// These tests exercise the real browse query with one user hiding fields and
// another reading. They need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_l19        # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_l19?sslmode=disable' \
//	  go test ./internal/marriage/ -v
package marriage

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping marriage field-privacy integration test")
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

// fixtureSeq keeps phone numbers unique within a run; runTag keeps two runs
// against the same database apart, so a run that dies before its cleanup
// cannot make the next one fail on users.phone's UNIQUE constraint.
var (
	fixtureSeq int64
	runTag     = time.Now().UnixNano() % 100000
)

func makeUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	fixtureSeq++
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (phone, role_id, active, registration_status)
		 VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("96478%05d%04d", runTag, fixtureSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// makeProfile writes an ACTIVE engagement profile with every browsable field
// filled in, so a masked field is unmistakably a mask rather than a blank.
func makeProfile(t *testing.T, pool *pgxpool.Pool, ownerID int64, visibility string, hidden []string) int64 {
	t.Helper()
	if hidden == nil {
		hidden = []string{} // the column is NOT NULL; nil would be a NULL
	}
	fixtureSeq++
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO marriage_profiles
		   (user_id, profile_code, gender, age, city, social_summary,
		    marital_status, religion, employment_status, weight_kg, height_cm,
		    photo_url, visibility_level, status, field_privacy)
		 VALUES ($1, $2, 'female', 27, 'Erbil', 'a short summary',
		         'single', 'Muslim', 'employed', 60, 165,
		         '/uploads/photo.jpg', $3, 'active', $4)
		 RETURNING id`,
		ownerID, fmt.Sprintf("L19-%05d-%04d", runTag, fixtureSeq), visibility, hidden,
	).Scan(&id); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marriage_profiles WHERE id = $1`, id)
	})
	return id
}

func find(t *testing.T, items []Profile, id int64) Profile {
	t.Helper()
	for _, p := range items {
		if p.ID == id {
			return p
		}
	}
	t.Fatalf("fixture problem: profile %d not among the %d returned", id, len(items))
	return Profile{}
}

func contains(t *testing.T, items []Profile, id int64) bool {
	t.Helper()
	for _, p := range items {
		if p.ID == id {
			return true
		}
	}
	return false
}

// ─── Tests ──────────────────────────────────────────────────────────────

// The row the client asked for: hide the photo, keep the age.
func TestMarriageBrowseHidesTheFieldsTheOwnerHid(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary",
		[]string{"photo_url", "religion", "weight_kg", "social_summary"})

	items, err := New(pool).List(context.Background(), SearchFilters{ViewerUserID: viewer, Limit: 100})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	p := find(t, items, id)
	if p.PhotoUrl != nil {
		t.Errorf("photo_url = %q — the owner hid it", *p.PhotoUrl)
	}
	if p.Religion != nil {
		t.Errorf("religion = %q — the owner hid it", *p.Religion)
	}
	if p.WeightKg != nil {
		t.Errorf("weight_kg = %d — the owner hid it", *p.WeightKg)
	}
	if p.SocialSummary != nil {
		t.Errorf("social_summary = %q — the owner hid it", *p.SocialSummary)
	}
	// Everything the owner left ON must survive, or this is a different bug.
	if p.Age == nil || *p.Age != 27 {
		t.Errorf("age was lost — only four fields were hidden")
	}
	if p.City == nil || *p.City != "Erbil" {
		t.Errorf("city was lost — only four fields were hidden")
	}
	if p.HeightCm == nil || *p.HeightCm != 165 {
		t.Errorf("height_cm was lost — only four fields were hidden")
	}
	// The profile must still be identifiable, or a hidden card is useless.
	if p.ProfileCode == "" {
		t.Errorf("profile_code was masked — it is the handle that replaces a name")
	}
}

// A user is never hidden from themselves.
func TestMarriageOwnerSeesTheirOwnProfileComplete(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", []string{"photo_url", "age"})

	items, err := New(pool).List(context.Background(), SearchFilters{
		Status: "all", OwnedByUser: owner, ViewerUserID: owner,
	})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	p := find(t, items, id)
	if p.PhotoUrl == nil || p.Age == nil {
		t.Fatalf("the owner cannot see their own hidden fields (photo=%v age=%v)", p.PhotoUrl, p.Age)
	}
	if len(p.FieldPrivacy) != 2 {
		t.Errorf("field_privacy = %v, want the owner's own two keys back so the picker can render", p.FieldPrivacy)
	}
}

// visibility_level was stored and never used as a query condition.
func TestMarriagePrivateProfileIsNotBrowsable(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "private", nil)

	items, err := New(pool).List(context.Background(), SearchFilters{ViewerUserID: viewer, Limit: 100})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if contains(t, items, id) {
		t.Errorf("a profile set to visibility_level='private' is still in the browse feed")
	}

	// The owner must still find their own private profile.
	mine, err := New(pool).List(context.Background(), SearchFilters{
		Status: "all", OwnedByUser: owner, ViewerUserID: owner,
	})
	if err != nil {
		t.Fatalf("List(mine): %v", err)
	}
	if !contains(t, mine, id) {
		t.Errorf("the owner cannot see their own private profile")
	}
}

// employee_only is the column DEFAULT, so filtering it out would empty the
// feed. This pins the deliberate decision NOT to, so a later change is a
// conscious one rather than an accident.
func TestMarriageEmployeeOnlyProfilesStayBrowsable(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "employee_only", nil)

	items, err := New(pool).List(context.Background(), SearchFilters{ViewerUserID: viewer, Limit: 100})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if !contains(t, items, id) {
		t.Errorf("an 'employee_only' profile vanished from the feed — that is the DEFAULT for every profile in the system")
	}
}

// ─── The setter ─────────────────────────────────────────────────────────

func TestMarriageSetFieldPrivacyStoresOnlyCatalogueKeys(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	saved, err := New(pool).SetFieldPrivacy(context.Background(), id, owner,
		[]string{"photo_url", "  age  ", "photo_url", "profile_code", "not_a_field", ""})
	if err != nil {
		t.Fatalf("SetFieldPrivacy: %v", err)
	}
	want := map[string]bool{"photo_url": true, "age": true}
	if len(saved) != len(want) {
		t.Fatalf("saved = %v, want exactly photo_url and age (duplicates, blanks, unknown "+
			"keys and profile_code all dropped)", saved)
	}
	for _, k := range saved {
		if !want[k] {
			t.Errorf("saved unexpected key %q", k)
		}
	}
}

func TestMarriageSetFieldPrivacyRefusesANonOwner(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	stranger := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if _, err := New(pool).SetFieldPrivacy(context.Background(), id, stranger, []string{"photo_url"}); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("SetFieldPrivacy by a stranger returned %v, want ErrNotOwner", err)
	}
	// And nothing was written.
	var stored []string
	if err := pool.QueryRow(context.Background(),
		`SELECT field_privacy FROM marriage_profiles WHERE id = $1`, id).Scan(&stored); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if len(stored) != 0 {
		t.Errorf("field_privacy = %v after a rejected write, want empty", stored)
	}
}

// A missing profile answers exactly like somebody else's, so the endpoint
// cannot be used to probe which ids exist.
func TestMarriageSetFieldPrivacyOnAMissingProfileLooksTheSame(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	if _, err := New(pool).SetFieldPrivacy(context.Background(), 999999999, owner, []string{"age"}); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("SetFieldPrivacy on a missing profile returned %v, want ErrNotOwner", err)
	}
}

// ─── The catalogue ──────────────────────────────────────────────────────

// The picker is data-driven, so the migration's seed is part of the contract.
func TestMarriagePrivacyCatalogueIsSeeded(t *testing.T) {
	pool := newTestPool(t)
	opts, err := New(pool).PrivacyFieldOptions(context.Background())
	if err != nil {
		t.Fatalf("PrivacyFieldOptions: %v", err)
	}
	// The label keys must be ones the app ALREADY has in all four locales
	// (en/ar/ckb/kmr) — the engagement form prints these same labels above
	// these same fields. Inventing new keys here would mean shipping English
	// (or worse, invented Kurdish) into the picker.
	wantLabel := map[string]string{
		"photo_url": "marriage_photo", "age": "marriage_age", "gender": "marriage_gender",
		"city": "marriage_city", "marital_status": "marriage_marital_status",
		"religion": "marriage_religion", "employment_status": "marriage_employment_status",
		"weight_kg": "marriage_weight", "height_cm": "marriage_height",
		"social_summary": "marriage_summary",
	}
	got := map[string]bool{}
	for _, o := range opts {
		got[o.FieldKey] = true
		if o.LabelKey == "" {
			t.Errorf("option %q has no label_key and no fallback", o.FieldKey)
		}
		if want, ok := wantLabel[o.FieldKey]; ok && o.LabelKey != want {
			t.Errorf("option %q has label_key %q, want the existing app key %q", o.FieldKey, o.LabelKey, want)
		}
	}
	for _, want := range []string{
		"photo_url", "age", "gender", "city", "marital_status",
		"religion", "employment_status", "weight_kg", "height_cm", "social_summary",
	} {
		if !got[want] {
			t.Errorf("catalogue is missing %q — the picker cannot offer a switch it does not know about", want)
		}
	}
	// profile_code must NOT be offered: it is the handle that stands in for a
	// name, so hiding it would leave nothing to refer to the profile by.
	if got["profile_code"] {
		t.Errorf("catalogue offers profile_code — hiding the identity handle leaves an unreferenceable card")
	}
}
