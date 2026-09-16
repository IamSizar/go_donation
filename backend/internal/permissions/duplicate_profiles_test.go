// duplicate_profiles_test.go — the permission audit log must show each entry
// once even when the actor has two user_profiles rows (OPOS #26603).
//
// user_profiles.user_id has no UNIQUE constraint, so a user can own two rows,
// and a plain join on it repeats every row it touches. An audit log that
// repeats entries is worse than a cosmetic bug: it misreports what happened.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package permissions

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
		t.Skip("TEST_DATABASE_URL not set — skipping permissions integration test")
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

func TestListAuditShowsAnEntryOnceWhenTheActorHasTwoProfiles(t *testing.T) {
	pool := newDupTestPool(t)
	actor := makeDupProfileUser(t, pool)
	var entryID int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO permission_audit_log (actor_id, action, target) VALUES ($1, 'permission_set', 'dup-profile-probe') RETURNING id`,
		actor,
	).Scan(&entryID); err != nil {
		t.Fatalf("insert audit row: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM permission_audit_log WHERE id = $1`, entryID)
	})

	entries, err := New(pool).ListAudit(context.Background(), 500)
	if err != nil {
		t.Fatalf("ListAudit: %v", err)
	}
	got := 0
	var name *string
	for _, e := range entries {
		if e.ID == entryID {
			got++
			name = e.ActorName
		}
	}
	if got != 1 {
		t.Fatalf("audit entry %d listed %d times, want 1", entryID, got)
	}
	if name == nil || *name != "Oldest Profile Name" {
		t.Errorf("ActorName = %v, want the oldest profile row's name", name)
	}
}
