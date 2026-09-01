// Pins the Users list's "hide guests" filter.
//
// WHY THIS EXISTS
// Guests are one-tap accounts that name themselves nothing, and they
// accumulate faster than real accounts — on production they were roughly half
// of page one, crowding out the donors, beneficiaries and volunteers staff
// were looking for. The owner asked for a way to hide them.
//
// The filter is applied in SQL rather than in the browser, and the reason IS
// the assertion this file cares most about: PaginatedList also produces the
// TOTAL the page header prints and the page count the pager walks. A filter
// applied after the query would leave an operator looking at eight rows on a
// "page" of twenty under a header still claiming sixty-three. So both the rows
// AND the total are checked here — a fix that only filtered the rows would
// pass a rows-only test and still ship the confusing screen.
package handlers

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// insertGuest adds a guest account and returns its id. Guests are created by
// the app with a username and no phone, which is why this cannot reuse
// insertAccount (that one always writes a phone).
func insertGuest(t *testing.T, pool *pgxpool.Pool, username string) int64 {
	t.Helper()
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO users (username, is_guest, role_id, active, is_admin,
		                    registration_status, account_status)
		 VALUES ($1, TRUE, 1, 1, 0, 'approved', 'active')
		 RETURNING id`, username).Scan(&id)
	if err != nil {
		t.Fatalf("insert guest %s: %v", username, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

func TestPaginatedListHideGuests(t *testing.T) {
	pool := newAuthTestPool(t)
	store := users.NewStore(pool)
	ctx := context.Background()

	// Arrange — a guest and a real account, both freshly inserted so the
	// assertions below can be about THESE rows rather than about whatever
	// else the database happens to hold.
	guestID := insertGuest(t, pool, "guest_hide_test_1")
	realAccount := insertAccount(t, pool, "user", "")

	// Act
	withGuests, err := store.PaginatedList(ctx, 1, 500, "", "all", false)
	if err != nil {
		t.Fatalf("list with guests: %v", err)
	}
	withoutGuests, err := store.PaginatedList(ctx, 1, 500, "", "all", true)
	if err != nil {
		t.Fatalf("list without guests: %v", err)
	}

	has := func(res *users.PageUsers, id int64) bool {
		for _, u := range res.Items {
			if u.UserID == id {
				return true
			}
		}
		return false
	}

	// Assert — the default is unchanged: nobody's existing view silently
	// starts hiding rows.
	if !has(withGuests, guestID) {
		t.Error("the default list must still contain guests")
	}
	if !has(withGuests, realAccount.id) {
		t.Error("the default list must contain the real account")
	}

	// Assert — the filter drops the guest and keeps everyone else.
	if has(withoutGuests, guestID) {
		t.Error("hide_guests did not drop the guest account")
	}
	if !has(withoutGuests, realAccount.id) {
		t.Error("hide_guests dropped a real account")
	}

	// Assert — and the TOTAL follows the rows. This is the half that a
	// browser-side filter cannot do, and the reason the predicate lives in
	// the same WHERE clause as the COUNT.
	if withoutGuests.Pagination.TotalItems >= withGuests.Pagination.TotalItems {
		t.Errorf(
			"total did not shrink with the filter: %d with guests, %d without — "+
				"the header would claim more rows than the list can show",
			withGuests.Pagination.TotalItems, withoutGuests.Pagination.TotalItems,
		)
	}
}

// The predicate COALESCEs is_guest before comparing it. Today that is belt and
// braces — the column is NOT NULL — but "today" is the operative word, and the
// failure mode if that ever changes is the bad one: a NULL means "not a guest",
// so a bare `is_guest = FALSE` would quietly hide established accounts rather
// than guests. This pins the constraint the simpler form would depend on, so
// dropping it fails here instead of in the users list.
func TestIsGuestIsNotNullable(t *testing.T) {
	pool := newAuthTestPool(t)

	var nullable string
	err := pool.QueryRow(context.Background(),
		`SELECT is_nullable FROM information_schema.columns
		  WHERE table_name = 'users' AND column_name = 'is_guest'`,
	).Scan(&nullable)
	if err != nil {
		t.Fatalf("read is_guest nullability: %v", err)
	}
	if nullable != "NO" {
		t.Errorf(
			"users.is_guest is now nullable (is_nullable=%s). The COALESCE in "+
				"PaginatedList's hide-guests predicate is load-bearing from here on: "+
				"a NULL means NOT a guest, and must never be filtered out.",
			nullable,
		)
	}
}
