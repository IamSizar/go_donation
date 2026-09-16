// duplicate_profiles_test.go — the profile-change review queue must show each
// request once even when the requester or the decider has two user_profiles
// rows (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows.
// This query joins the table TWICE — once for the requester, once for the
// decider — so two duplicated people multiply: 2 × 2 = four copies of one
// request. The irony is that this is the very screen for fixing a profile.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set. This package had no test file before.
package profilechanges

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
		t.Skip("TEST_DATABASE_URL not set — skipping profilechanges integration test")
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

// TestListShowsARequestOnceWhenBothPartiesHaveTwoProfiles uses a decided
// request so BOTH joins are exercised at once — the failure this pins is ×4,
// not ×2.
func TestListShowsARequestOnceWhenBothPartiesHaveTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	requester := makeDupProfileUser(t, pool)
	decider := makeDupProfileUser(t, pool)
	var reqID int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO profile_change_requests (user_id, field, old_value, new_value, status, decided_at, decided_by)
		 VALUES ($1, 'full_name', 'Old', 'New', 'approved', CURRENT_TIMESTAMP, $2) RETURNING id`,
		requester, decider,
	).Scan(&reqID); err != nil {
		t.Fatalf("insert request: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM profile_change_requests WHERE id = $1`, reqID)
	})

	items, err := New(pool).List(context.Background(), "approved", 500)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	got := 0
	var found Request
	for _, r := range items {
		if r.ID == reqID {
			got++
			found = r
		}
	}
	if got != 1 {
		t.Fatalf("request %d listed %d times, want 1", reqID, got)
	}
	if found.UserName != "Oldest Profile Name" {
		t.Errorf("UserName = %q, want the oldest profile row's name", found.UserName)
	}
	if found.DecidedByName != "Oldest Profile Name" {
		t.Errorf("DecidedByName = %q, want the oldest profile row's name", found.DecidedByName)
	}
}
