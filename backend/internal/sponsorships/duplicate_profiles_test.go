// duplicate_profiles_test.go — the sponsorships list must show each
// sponsorship once even when the donor has two user_profiles rows
// (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package sponsorships

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// newDupTestPool connects to TEST_DATABASE_URL and brings it up to date with
// the real migrations.
func newDupTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping sponsorships integration test")
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

// makeDupProfileUser inserts a user with two profile rows (the older first).
func makeDupProfileUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, 1, 1) RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	for _, name := range []string{"Oldest Profile Name", "Newer Duplicate Profile Name"} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
			id, name); err != nil {
			t.Fatalf("insert profile: %v", err)
		}
	}
	return id
}

// TestListShowsASponsorshipOnceWhenTheDonorHasTwoProfiles filters to the
// donor's own id, and reads it as that donor, so the privacy masking in List
// leaves the name alone and the assertion is about the join only.
func TestListShowsASponsorshipOnceWhenTheDonorHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	donor := makeDupProfileUser(t, pool)
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO sponsorships (donor_user_id, sponsorship_type, amount, status)
		 VALUES ($1, 'monthly-support', 50000, 'active') RETURNING id`, donor,
	).Scan(&id); err != nil {
		t.Fatalf("insert sponsorship: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM sponsorships WHERE id = $1`, id)
	})

	items, err := New(pool).List(context.Background(), ListFilters{
		DonorUserID:  donor,
		ViewerUserID: donor,
		Limit:        200,
	})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(items) != 1 || items[0].ID != id {
		t.Fatalf("got %d rows for donor %d, want exactly sponsorship %d once", len(items), donor, id)
	}
	if items[0].DonorFullName == nil || *items[0].DonorFullName != "Oldest Profile Name" {
		t.Errorf("DonorFullName = %v, want the oldest profile row's name", items[0].DonorFullName)
	}
}
