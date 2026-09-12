// OPOS #25287 — "profile edits sometimes don't sync to dashboard". Root
// cause: profile_change_requests (internal/profilechanges) is a deliberate
// staff-review queue for name/photo edits, but the Users list had no way to
// show a pending row, so staff saw one field update instantly (name/address,
// written live by the registration-edit flow) and another (a queued photo
// change) silently not appear, and reasonably called it "not syncing".
//
// This locks in the fix: PaginatedList marks HasPendingProfileChange = true
// for any user with an unreviewed row.
//
// Needs a throwaway Postgres, skipped unless TEST_DATABASE_URL is set — see
// grantor_code_test.go's newGrantorTestPool for the exact setup.
package users

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// makeSecondUser is makeUser's fixture logic with a distinguishable phone,
// for tests that need two fixture users in one run (t.Name() alone is not
// enough to keep two makeUser calls from colliding on the unique phone).
func makeSecondUser(t *testing.T, pool *pgxpool.Pool, roleID int) int64 {
	t.Helper()
	ctx := context.Background()
	phone := "96471111" + pad6(int64(len(t.Name())))[1:] + itoaLast(t.Name())
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ($1, $2, 1) RETURNING id`,
		phone, roleID,
	).Scan(&id); err != nil {
		t.Fatalf("insert second user: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, address, gender)
		 VALUES ($1, 'Test Person Two', 'Erbil', 'Male')`,
		id); err != nil {
		t.Fatalf("insert second profile: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func TestPaginatedListMarksPendingProfileChange(t *testing.T) {
	pool := newGrantorTestPool(t)
	ctx := context.Background()
	store := NewStore(pool)

	// makeUser derives its fixture phone number from t.Name() alone, so two
	// calls in the SAME test collide on the unique phone constraint — hence
	// the second user is its own small fixture rather than a second makeUser
	// call.
	withPending := makeUser(t, pool, 2)
	withoutPending := makeSecondUser(t, pool, 2)

	if _, err := pool.Exec(ctx,
		`INSERT INTO profile_change_requests (user_id, field, old_value, new_value)
		 VALUES ($1, 'profile_picture', 'old.jpg', 'new.jpg')`,
		withPending,
	); err != nil {
		t.Fatalf("insert pending change: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM profile_change_requests WHERE user_id = $1`, withPending)
	})

	page, err := store.PaginatedList(ctx, 1, 100, "", "all", false)
	if err != nil {
		t.Fatalf("PaginatedList: %v", err)
	}

	var sawPending, sawClean bool
	for _, acc := range page.Items {
		switch acc.UserID {
		case withPending:
			sawPending = true
			if !acc.HasPendingProfileChange {
				t.Errorf("user %d has a pending profile_change_requests row but HasPendingProfileChange is false", withPending)
			}
		case withoutPending:
			sawClean = true
			if acc.HasPendingProfileChange {
				t.Errorf("user %d has no pending row but HasPendingProfileChange is true", withoutPending)
			}
		}
	}
	if !sawPending {
		t.Fatalf("fixture user %d not found in PaginatedList results", withPending)
	}
	if !sawClean {
		t.Fatalf("fixture user %d not found in PaginatedList results", withoutPending)
	}
}
