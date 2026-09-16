// GetOrCreateThread must refuse a pair where either side is an ordinary
// (staff_tier = 'user') account.
//
// WHY THIS MATTERS
// This package's whole premise (see the file doc on staffchat.go) is that a
// thread here skips the accept/decline step donor<->beneficiary chat has,
// because both parties are already trusted staff. Before this fix,
// GetOrCreateThread trusted its caller entirely — nothing stopped a thread
// (and therefore internal/notify's unfiltered push, titled "Message from
// <staff name>") from reaching a donor, beneficiary, volunteer, or guest
// account. See OPOS #25267.
//
// Needs a throwaway Postgres and is skipped unless TEST_DATABASE_URL is set,
// same convention as internal/users/grantor_code_test.go:
//
//	createdb godonation_staffchat
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_staffchat?sslmode=disable' \
//	  go test ./internal/staffchat/ -v
package staffchat

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

func newStaffChatTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping staffchat integration test")
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

// insertTestUser creates a throwaway user with the given staff_tier
// ('user' for an ordinary account) and removes it when the test ends.
func insertTestUser(t *testing.T, pool *pgxpool.Pool, staffTier string) int64 {
	t.Helper()
	ctx := context.Background()
	phone := fmt.Sprintf("9647%09d", rand.Intn(1000000000))
	var id int64
	err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, is_admin, staff_tier, registration_status, account_status)
		 VALUES ($1, 1, 1, 0, $2, 'approved', 'active') RETURNING id`,
		phone, staffTier,
	).Scan(&id)
	if err != nil {
		t.Fatalf("insert user (staff_tier=%s): %v", staffTier, err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM staff_chat_messages WHERE thread_id IN (SELECT id FROM staff_chat_threads WHERE user_a_id = $1 OR user_b_id = $1)`, id)
		_, _ = pool.Exec(bg, `DELETE FROM staff_chat_threads WHERE user_a_id = $1 OR user_b_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func TestGetOrCreateThreadRefusesANonStaffParticipant(t *testing.T) {
	pool := newStaffChatTestPool(t)
	store := New(pool)

	t.Run("both staff succeeds", func(t *testing.T) {
		a := insertTestUser(t, pool, "employee")
		b := insertTestUser(t, pool, "supervisor")

		thread, err := store.GetOrCreateThread(context.Background(), a, b)
		if err != nil {
			t.Fatalf("GetOrCreateThread(staff, staff) = %v, want success", err)
		}
		if thread.ID == 0 {
			t.Errorf("thread.ID = 0, want a real id")
		}
	})

	t.Run("staff with an ordinary user is refused, no thread created", func(t *testing.T) {
		staff := insertTestUser(t, pool, "employee")
		ordinary := insertTestUser(t, pool, "user")

		_, err := store.GetOrCreateThread(context.Background(), staff, ordinary)
		if !errors.Is(err, ErrNotStaff) {
			t.Fatalf("GetOrCreateThread(staff, ordinary) err = %v, want ErrNotStaff", err)
		}

		var count int
		if err := pool.QueryRow(context.Background(),
			`SELECT COUNT(*) FROM staff_chat_threads WHERE user_a_id IN ($1,$2) OR user_b_id IN ($1,$2)`,
			staff, ordinary,
		).Scan(&count); err != nil {
			t.Fatalf("count threads: %v", err)
		}
		if count != 0 {
			t.Errorf("thread count = %d, want 0 — a refused pair must not create a row", count)
		}
	})

	t.Run("two ordinary users is refused", func(t *testing.T) {
		u1 := insertTestUser(t, pool, "user")
		u2 := insertTestUser(t, pool, "user")

		_, err := store.GetOrCreateThread(context.Background(), u1, u2)
		if !errors.Is(err, ErrNotStaff) {
			t.Fatalf("GetOrCreateThread(ordinary, ordinary) err = %v, want ErrNotStaff", err)
		}
	})
}
