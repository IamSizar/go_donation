// Pins the Users list's staff filter (?staff=1 / ?staff=0).
//
// WHY THIS EXISTS
// The dashboard's Staff page (System Settings) fetched ONE page of every
// account and kept the staff rows in the browser. The list serves at most 100
// per page and an oversized per_page falls back to 20, so the page only ever
// looked at the newest 20 accounts — and on production, where app users keep
// registering after the staff accounts were made, it showed no staff at all.
// Filtering in SQL makes the staff list independent of how many other users
// exist, and keeps the Users page's pages full and its total honest.
package handlers

import (
	"context"
	"testing"

	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

func TestPaginatedListStaffFilter(t *testing.T) {
	pool := newAuthTestPool(t)
	store := users.NewStore(pool)
	ctx := context.Background()

	// A staff account created FIRST, then more than a page of ordinary users
	// after it — the production shape that hid every staff row.
	staff := insertAccount(t, pool, "supervisor", "")
	for i := 0; i < 25; i++ {
		insertAccount(t, pool, "user", "")
	}
	ordinary := insertAccount(t, pool, "user", "")

	has := func(res *users.PageUsers, id int64) bool {
		for _, u := range res.Items {
			if u.UserID == id {
				return true
			}
		}
		return false
	}

	onlyStaff, err := store.PaginatedListFiltered(ctx, 1, 100, "", "all", false, "1")
	if err != nil {
		t.Fatalf("staff=1: %v", err)
	}
	if !has(onlyStaff, staff.id) {
		t.Error("staff=1 must return the staff account even with 25 newer users on top")
	}
	for _, u := range onlyStaff.Items {
		if u.StaffTier == "" || u.StaffTier == "user" {
			t.Errorf("staff=1 returned non-staff account %d", u.UserID)
		}
	}
	if onlyStaff.Pagination.TotalItems != len(onlyStaff.Items) && onlyStaff.Pagination.TotalItems < 100 {
		t.Errorf("staff=1 total %d does not match its %d rows", onlyStaff.Pagination.TotalItems, len(onlyStaff.Items))
	}

	noStaff, err := store.PaginatedListFiltered(ctx, 1, 100, "", "all", false, "0")
	if err != nil {
		t.Fatalf("staff=0: %v", err)
	}
	if has(noStaff, staff.id) {
		t.Error("staff=0 must not return staff accounts")
	}
	if !has(noStaff, ordinary.id) {
		t.Error("staff=0 must still return ordinary users")
	}

	// Absent = both, exactly as before the filter existed.
	both, err := store.PaginatedList(ctx, 1, 100, "", "all", false)
	if err != nil {
		t.Fatalf("default: %v", err)
	}
	if both.Pagination.TotalItems != onlyStaff.Pagination.TotalItems+noStaff.Pagination.TotalItems {
		t.Errorf("default total %d != staff %d + non-staff %d",
			both.Pagination.TotalItems, onlyStaff.Pagination.TotalItems, noStaff.Pagination.TotalItems)
	}
}

// The Donors page asks for ?role_id=1: only donor accounts, with a total that
// counts donors only. A non-numeric value must be ignored, never reach the SQL.
func TestPaginatedListByRole(t *testing.T) {
	pool := newAuthTestPool(t)
	store := users.NewStore(pool)
	ctx := context.Background()

	donor := insertAccount(t, pool, "user", "")
	other := insertAccount(t, pool, "user", "")
	if _, err := pool.Exec(ctx, `UPDATE users SET role_id = 1 WHERE id = $1`, donor.id); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE users SET role_id = 2 WHERE id = $1`, other.id); err != nil {
		t.Fatal(err)
	}
	has := func(res *users.PageUsers, id int64) bool {
		for _, u := range res.Items {
			if u.UserID == id {
				return true
			}
		}
		return false
	}

	donors, err := store.PaginatedListByRole(ctx, 1, 100, "", "all", false, "0", "1")
	if err != nil {
		t.Fatal(err)
	}
	if !has(donors, donor.id) || has(donors, other.id) {
		t.Errorf("role 1 must return the donor and not the recipient")
	}
	for _, u := range donors.Items {
		if u.RoleID != 1 {
			t.Errorf("role=1 returned account %d with role %d", u.UserID, u.RoleID)
		}
	}
	if donors.Pagination.TotalItems < 1 || (len(donors.Items) < 100 && donors.Pagination.TotalItems != len(donors.Items)) {
		t.Errorf("total %d does not match the %d donor rows", donors.Pagination.TotalItems, len(donors.Items))
	}

	for _, junk := range []string{"", "abc", "1; DROP TABLE users", "-3"} {
		res, err := store.PaginatedListByRole(ctx, 1, 100, "", "all", false, "0", junk)
		if err != nil {
			t.Fatalf("role %q: %v", junk, err)
		}
		if !has(res, donor.id) || !has(res, other.id) {
			t.Errorf("role %q must apply no role filter", junk)
		}
	}
}
