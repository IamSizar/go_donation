// duplicate_profiles_test.go — the admin contributions list must show a
// donation once even when the donor has two user_profiles rows (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches — here both the page and
// the total count.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package donations

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
// the real migrations, the same harness the other duplicate-profile tests use.
func newDupTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping donations integration test")
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

// TestAdminListShowsOneRowPerDonationWhenTheDonorHasTwoProfiles pins both the
// page and the total: a plain join doubled each.
func TestAdminListShowsOneRowPerDonationWhenTheDonorHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	donor := makeDupProfileUser(t, pool)
	ref := fmt.Sprintf("DUPREF-%09d", rand.Intn(1000000000))
	var donationID int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO donations (reference_number, user_id, message, amount, payment_method)
		 VALUES ($1, $2, '', '25000', 'cash') RETURNING id`, ref, donor,
	).Scan(&donationID); err != nil {
		t.Fatalf("insert donation: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM donations WHERE id = $1`, donationID)
	})

	page, err := NewStore(pool).AdminList(context.Background(), 1, 50, ref)
	if err != nil {
		t.Fatalf("AdminList: %v", err)
	}
	if len(page.Items) != 1 {
		t.Fatalf("got %d rows for reference %s, want 1", len(page.Items), ref)
	}
	if page.TotalItems != 1 {
		t.Errorf("TotalItems = %d, want 1 — the COUNT joins profiles too", page.TotalItems)
	}
	if page.Items[0].DonorFullName == nil || *page.Items[0].DonorFullName != "Oldest Profile Name" {
		t.Errorf("DonorFullName = %v, want the oldest profile row's name", page.Items[0].DonorFullName)
	}
}
