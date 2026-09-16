// duplicate_profiles_test.go — the admin user list and the registration queue
// must show an account once even when it has two user_profiles rows
// (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches — both the page and the
// total count in each of these two paginated reads.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package users

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
		t.Skip("TEST_DATABASE_URL not set — skipping users integration test")
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

// makeDupProfileUser inserts a user with two profile rows (the older first)
// and returns its id and its unique phone, which the searches below use to
// isolate this test's row from everything else in the database.
func makeDupProfileUser(t *testing.T, pool *pgxpool.Pool, regStatus string) (int64, string) {
	t.Helper()
	ctx := context.Background()
	phone := fmt.Sprintf("9647%08d", rand.Intn(100000000))
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, registration_status, registration_submitted_at)
		 VALUES ($1, 1, 1, $2, CURRENT_TIMESTAMP) RETURNING id`, phone, regStatus,
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
	return id, phone
}

// TestPaginatedListShowsAnAccountOnceWhenItHasTwoProfiles covers the admin
// user list, searched by the account's own phone so only this row can match.
func TestPaginatedListShowsAnAccountOnceWhenItHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	id, phone := makeDupProfileUser(t, pool, "approved")

	page, err := NewStore(pool).PaginatedList(context.Background(), 1, 50, phone, "all", false)
	if err != nil {
		t.Fatalf("PaginatedList: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].UserID != id {
		t.Fatalf("got %d rows for phone %s, want exactly user %d once", len(page.Items), phone, id)
	}
	prof := page.Items[0].Profile
	if prof == nil || prof.FullName == nil || *prof.FullName != "Oldest Profile Name" {
		t.Errorf("profile full_name = %v, want the oldest profile row's name", prof)
	}
	if page.Pagination.TotalItems != 1 {
		t.Errorf("TotalItems = %d, want 1 — the COUNT joins profiles too", page.Pagination.TotalItems)
	}
}

// TestListRegistrationsShowsARegistrationOnceWhenTheUserHasTwoProfiles covers
// the registration review queue.
func TestListRegistrationsShowsARegistrationOnceWhenTheUserHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	id, phone := makeDupProfileUser(t, pool, "pending")

	page, err := NewStore(pool).ListRegistrations(context.Background(), "pending", 1, 50, phone)
	if err != nil {
		t.Fatalf("ListRegistrations: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].UserID != id {
		t.Fatalf("got %d rows for phone %s, want exactly user %d once", len(page.Items), phone, id)
	}
	if page.Items[0].FullName != "Oldest Profile Name" {
		t.Errorf("FullName = %q, want the oldest profile row's name", page.Items[0].FullName)
	}
	if page.Pagination.TotalItems != 1 {
		t.Errorf("TotalItems = %d, want 1 — the COUNT joins profiles too", page.Pagination.TotalItems)
	}
}
