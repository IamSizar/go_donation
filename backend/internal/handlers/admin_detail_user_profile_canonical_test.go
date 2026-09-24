// admin_detail_user_profile_canonical_test.go — the account-detail profile
// reader must pick the same row as every other reader, and must not leak the
// '0' profile-picture sentinel to the dashboard.
//
// Client feedback round 1:
//
//   - loadUserProfile had no ORDER BY and no LIMIT, so pgx.CollectOneRow took
//     whichever of an account's user_profiles rows arrived first. The paginated
//     Users list had already settled on "oldest row wins" (OPOS #26603), so the
//     list and the detail page could describe the same person differently.
//   - profile_picture is NOT NULL and seeded with the literal '0'. Only the APP
//     endpoint translated it (handlers/profile.go); the dashboard path passed it
//     through, and admin-web turned it into "<API base>/0" — a broken image.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package handlers

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// makeUserWithDetailProfiles inserts a user plus one profile row per picture,
// oldest first; full_name records the index so a reader's choice is visible.
func makeUserWithDetailProfiles(t *testing.T, pool *pgxpool.Pool, pictures ...string) int64 {
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

func TestLoadUserProfileReturnsTheOldestRowWhenAnAccountHasTwo(t *testing.T) {
	pool := newDupProfilesPool(t)
	userID := makeUserWithDetailProfiles(t, pool, "uploads/a.jpg", "uploads/b.jpg")

	prof, err := loadUserProfile(context.Background(), pool, userID)
	if err != nil {
		t.Fatalf("loadUserProfile: %v", err)
	}
	if prof == nil {
		t.Fatal("loadUserProfile returned no profile")
	}
	if got, _ := prof["full_name"].(string); got != "Profile 0" {
		t.Errorf("loadUserProfile chose %q, want the oldest row %q", got, "Profile 0")
	}
}

func TestLoadUserProfileTreatsTheZeroSentinelAsNoPicture(t *testing.T) {
	pool := newDupProfilesPool(t)
	userID := makeUserWithDetailProfiles(t, pool, "0")

	prof, err := loadUserProfile(context.Background(), pool, userID)
	if err != nil {
		t.Fatalf("loadUserProfile: %v", err)
	}
	if prof == nil {
		t.Fatal("loadUserProfile returned no profile")
	}
	if got := prof["profile_picture"]; got != nil {
		t.Errorf("profile_picture = %#v, want nil — '0' is the NOT NULL seed, not a path", got)
	}
}

func TestLoadUserProfileKeepsARealPicturePath(t *testing.T) {
	pool := newDupProfilesPool(t)
	userID := makeUserWithDetailProfiles(t, pool, "uploads/avatars/real.jpg")

	prof, err := loadUserProfile(context.Background(), pool, userID)
	if err != nil {
		t.Fatalf("loadUserProfile: %v", err)
	}
	if got, _ := prof["profile_picture"].(string); got != "uploads/avatars/real.jpg" {
		t.Errorf("profile_picture = %#v, want the stored path", prof["profile_picture"])
	}
}
