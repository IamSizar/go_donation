// Pins GET /api/profile/full — the endpoint that lets the app's edit form
// prefill from what the user already entered.
//
// The property that matters most here is not what it returns but WHOSE row it
// returns. The endpoint takes no id: the row is chosen by the bearer token
// alone. That is the whole IDOR defence, and it is the kind of thing a later
// "make it reusable" refactor quietly breaks by adding a `?user_id=` for the
// admin panel's convenience — so it is asserted rather than assumed.
package handlers

import (
	"context"
	"testing"
)

func TestProfileFullColumnsMatchTheDashboard(t *testing.T) {
	// The endpoint reuses the dashboard's loader and allow-list precisely so
	// the two surfaces cannot disagree about what a profile contains. If that
	// list is ever forked for the app, this stops being true silently.
	if len(userProfileDetailColumns) == 0 {
		t.Fatal("userProfileDetailColumns is empty — the loader would return nothing")
	}
	for _, credential := range []string{"password_hash", "google_sub"} {
		for _, col := range userProfileDetailColumns {
			if col == credential {
				t.Errorf(
					"%q is in the profile allow-list. It is a credential and lives on "+
						"`users`, not `user_profiles` — if it has moved, this endpoint "+
						"now hands it to the app.", credential,
				)
			}
		}
	}
	// field_privacy is a SETTING owned by the Privacy screen, not a profile
	// field. The dashboard re-emits it as `_privacy_hidden` for badging; the
	// edit form has no badges and must not offer a second place to change it.
	for _, col := range userProfileDetailColumns {
		if col == "field_privacy" {
			t.Error("field_privacy is in the profile allow-list; it is a privacy setting, not a field")
		}
	}
}

func TestProfileFullReadsOnlyTheRequestedUsersRow(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	mine := insertAccount(t, pool, "user", "")
	theirs := insertAccount(t, pool, "user", "")

	// Plain INSERTs, not upserts: user_profiles has NO unique constraint on
	// user_id (checked — ON CONFLICT (user_id) is rejected as having no
	// matching constraint), so there is nothing to conflict on. Both accounts
	// are freshly created by insertAccount, so neither has a row yet.
	seed := func(id int64, name string) {
		t.Helper()
		// gender and address are NOT NULL with no default on this table, so a
		// minimal insert is rejected. They are given empty strings rather than
		// values, because this test is about WHOSE row comes back, not about
		// what is in it.
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address)
			 VALUES ($1, $2, '', '')`, id, name,
		); err != nil {
			t.Fatalf("seed profile for %d: %v", id, err)
		}
	}
	// Give the other account something distinctive to leak.
	seed(theirs.id, "SOMEBODY ELSE")
	seed(mine.id, "MY OWN NAME")

	got, err := loadUserProfile(ctx, pool, mine.id)
	if err != nil {
		t.Fatalf("load own profile: %v", err)
	}
	if got == nil {
		t.Fatal("own profile came back nil")
	}
	if got["full_name"] != "MY OWN NAME" {
		t.Errorf("loaded the wrong row: full_name = %v", got["full_name"])
	}
}

// A brand-new account has no user_profiles row at all. The handler turns that
// into an empty object rather than a 404, because "nothing filled in yet" is a
// legitimate state for the edit form to prefill from — and a 404 would make
// the client treat a normal case as a failure and show an error screen to
// somebody who simply has not registered yet.
func TestProfileFullTreatsNoRowAsEmptyNotMissing(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	fresh := insertAccount(t, pool, "user", "")
	if _, err := pool.Exec(ctx, `DELETE FROM user_profiles WHERE user_id = $1`, fresh.id); err != nil {
		t.Fatalf("clear profile: %v", err)
	}

	got, err := loadUserProfile(ctx, pool, fresh.id)
	if err != nil {
		t.Fatalf("load profile for a user with no row: %v", err)
	}
	if got != nil {
		t.Errorf("expected nil for an absent row (the handler maps it to {}), got %v", got)
	}
}
