// profile_canonical_row_test.go — two rules every user_profiles READER must
// follow, pinned on the two readers that live in this package.
//
// Rule 1 — oldest row wins. user_profiles.user_id has no UNIQUE constraint
// (see migrations/124_user_profiles_user_id_index.sql for why it was not
// added), so an account can own more than one row. The paginated admin list
// already settled on "the oldest row is the canonical one" (ORDER BY p.id
// LIMIT 1, OPOS #26603). GetProfileRow and GetAccountForClient used a bare
// LIMIT 1 with no ORDER BY, so Postgres returned whichever row it felt like —
// two screens could disagree about the same person.
//
// Rule 2 — the '0' profile-picture sentinel never escapes the query.
// user_profiles.profile_picture is NOT NULL and is seeded with the literal
// string '0' (registration.go), which is not a path. Readers must translate it
// to "no picture" at the boundary, or the dashboard renders it as a URL and
// shows a broken image.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package users

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// makeUserWithProfiles inserts one user plus one profile row per entry in
// pictures, in order, so the FIRST entry is always the oldest row (lowest id).
// Each profile's full_name records its index so a reader's choice is visible.
func makeUserWithProfiles(t *testing.T, pool *pgxpool.Pool, pictures ...string) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, registration_status)
		 VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	for i, pic := range pictures {
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture)
			 VALUES ($1, $2, '', '', $3)`,
			id, fmt.Sprintf("Profile %d", i), pic,
		); err != nil {
			t.Fatalf("insert profile %d: %v", i, err)
		}
	}
	// Push the OLDEST row to the back of the heap. Without this, a sequential
	// scan hands back insertion order and an unordered query looks correct by
	// luck — which is exactly how the bug survived. An UPDATE writes a new
	// tuple at the end of the table, so the newest row is now the first one a
	// reader without an ORDER BY sees.
	if len(pictures) > 1 {
		if _, err := pool.Exec(ctx,
			`UPDATE user_profiles SET address = ''
			  WHERE id = (SELECT MIN(id) FROM user_profiles WHERE user_id = $1)`, id,
		); err != nil {
			t.Fatalf("reorder heap: %v", err)
		}
	}
	return id
}

// ─── Rule 1: oldest row wins ────────────────────────────────────────────────

func TestGetProfileRowReturnsTheOldestRowWhenAnAccountHasTwo(t *testing.T) {
	pool := newDupTestPool(t)
	userID := makeUserWithProfiles(t, pool, "uploads/a.jpg", "uploads/b.jpg")

	row, err := NewStore(pool).GetProfileRow(context.Background(), userID)
	if err != nil {
		t.Fatalf("GetProfileRow: %v", err)
	}
	if row == nil {
		t.Fatal("GetProfileRow returned no row")
	}
	if row.FullName != "Profile 0" {
		t.Errorf("GetProfileRow chose %q, want the oldest row %q", row.FullName, "Profile 0")
	}
}

func TestGetAccountForClientReturnsTheOldestProfileWhenAnAccountHasTwo(t *testing.T) {
	pool := newDupTestPool(t)
	userID := makeUserWithProfiles(t, pool, "uploads/a.jpg", "uploads/b.jpg")

	acc, err := NewStore(pool).GetAccountForClient(context.Background(), userID)
	if err != nil {
		t.Fatalf("GetAccountForClient: %v", err)
	}
	if acc == nil || acc.Profile == nil {
		t.Fatal("GetAccountForClient returned no profile")
	}
	got := ""
	if acc.Profile.FullName != nil {
		got = *acc.Profile.FullName
	}
	if got != "Profile 0" {
		t.Errorf("GetAccountForClient chose %q, want the oldest row %q", got, "Profile 0")
	}
}

// TestGetProfileRowAndGetAccountForClientAgree is the symptom the rule exists
// to prevent: two readers naming two different rows for the same person.
func TestGetProfileRowAndGetAccountForClientAgree(t *testing.T) {
	pool := newDupTestPool(t)
	userID := makeUserWithProfiles(t, pool, "uploads/a.jpg", "uploads/b.jpg")
	ctx := context.Background()
	store := NewStore(pool)

	row, err := store.GetProfileRow(ctx, userID)
	if err != nil || row == nil {
		t.Fatalf("GetProfileRow: %v (row=%v)", err, row)
	}
	acc, err := store.GetAccountForClient(ctx, userID)
	if err != nil || acc == nil || acc.Profile == nil {
		t.Fatalf("GetAccountForClient: %v", err)
	}
	if row.ProfileID != acc.Profile.ProfileID {
		t.Errorf("readers disagree on the canonical row: GetProfileRow=%d, GetAccountForClient=%d",
			row.ProfileID, acc.Profile.ProfileID)
	}
}

// ─── Rule 2: the '0' sentinel is not a picture ──────────────────────────────

func TestGetAccountForClientTreatsTheZeroSentinelAsNoPicture(t *testing.T) {
	pool := newDupTestPool(t)
	userID := makeUserWithProfiles(t, pool, "0")

	acc, err := NewStore(pool).GetAccountForClient(context.Background(), userID)
	if err != nil {
		t.Fatalf("GetAccountForClient: %v", err)
	}
	if acc == nil || acc.Profile == nil {
		t.Fatal("GetAccountForClient returned no profile")
	}
	if acc.Profile.ProfilePicture != nil {
		t.Errorf("profile_picture = %q, want nil — '0' is the NOT NULL seed, not a path",
			*acc.Profile.ProfilePicture)
	}
}

func TestGetAccountForClientKeepsARealPicturePath(t *testing.T) {
	pool := newDupTestPool(t)
	userID := makeUserWithProfiles(t, pool, "uploads/avatars/real.jpg")

	acc, err := NewStore(pool).GetAccountForClient(context.Background(), userID)
	if err != nil {
		t.Fatalf("GetAccountForClient: %v", err)
	}
	if acc == nil || acc.Profile == nil || acc.Profile.ProfilePicture == nil {
		t.Fatal("a real picture path was dropped")
	}
	if *acc.Profile.ProfilePicture != "uploads/avatars/real.jpg" {
		t.Errorf("profile_picture = %q, want the stored path", *acc.Profile.ProfilePicture)
	}
}

// TestPaginatedListTreatsTheZeroSentinelAsNoPicture covers the admin Users
// list, the other dashboard read of this column.
func TestPaginatedListTreatsTheZeroSentinelAsNoPicture(t *testing.T) {
	pool := newDupTestPool(t)
	ctx := context.Background()
	var phone string
	if err := pool.QueryRow(ctx,
		`SELECT phone FROM users WHERE id = $1`,
		makeUserWithProfiles(t, pool, "0"),
	).Scan(&phone); err != nil {
		t.Fatalf("read back phone: %v", err)
	}

	page, err := NewStore(pool).PaginatedList(ctx, 1, 50, phone, "all", false)
	if err != nil {
		t.Fatalf("PaginatedList: %v", err)
	}
	if len(page.Items) != 1 {
		t.Fatalf("got %d rows for phone %s, want 1", len(page.Items), phone)
	}
	prof := page.Items[0].Profile
	if prof == nil {
		t.Fatal("list row carries no profile")
	}
	if prof.ProfilePicture != nil {
		t.Errorf("profile_picture = %q, want nil — the dashboard renders this as a URL",
			*prof.ProfilePicture)
	}
}
