// admin_edit_user_profile_test.go — the Edit modal can now write the ninety
// plain-text `user_profiles` columns through an allow-list rather than through
// ninety struct fields (admin_edit_user_profile.go). These tests pin the two
// properties that makes safe: only listed columns are written, and a listed
// column really does reach the row — in both the UPDATE and the INSERT branch.
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_profile?sslmode=disable' \
//	  go test ./internal/handlers/ -run UserProfileEdit -v
package handlers

import (
	"context"
	"net/http"
	"testing"
)

// TestUserProfileEditRejectsUnlistedColumns is the injection/allow-list test.
//
// The parse step never sees a table or a column name from the request — a key
// that is not in userProfileWritableColumns is dropped before any SQL is built
// — so a body naming a column that is not writable must change nothing, and a
// body carrying SQL in a KEY must not reach the statement at all.
func TestUserProfileEditRejectsUnlistedColumns(t *testing.T) {
	for _, key := range []string{
		"field_privacy",          // a privacy control, never writable here
		"recipient_code",         // assign-once identity code
		"volunteer_code",         // assign-once identity code
		"display_name_mode",      // CHECK-constrained, owned by the user
		"gps_lat",                // a double, and device-captured
		`x" = '1', "national_id`, // a key shaped like SQL
		"password_hash",          // not even on this table
	} {
		if userProfileWritableColumns[key] {
			t.Errorf("%q is writable from the Edit modal; it must not be", key)
		}
		if got := parseUserProfileExtras([]byte(`{"` + key + `":"x"}`)); got != nil {
			t.Errorf("parse accepted %q: %v", key, got)
		}
	}
}

// TestUserProfileEditKeepsTheTypedColumnsOut — a column with its own typed
// field on userEditReq must NOT also be in the extras map, or one save would
// write it twice with two different rules.
func TestUserProfileEditKeepsTheTypedColumnsOut(t *testing.T) {
	for _, key := range []string{
		"full_name", "gender", "address", "profile_picture", "date_of_birth",
		"city", "occupation", "family_size", "housing_status",
		"monthly_income", "skills", "availability", "experience", "phone",
		"email", "password", "username",
	} {
		if userProfileWritableColumns[key] {
			t.Errorf("%q has a typed field AND an extras entry — two writers for one column", key)
		}
	}
}

// TestUserProfileEditWritesListedColumns drives the real PATCH route and reads
// the row back. Two branches, because they build their SQL separately: an
// account that already has a profile row (UPDATE) and one that does not
// (INSERT).
func TestUserProfileEditWritesListedColumns(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	actor := insertAccount(t, pool, "super_admin", "")

	body := map[string]any{
		"national_id":   "19900101234",
		"neighborhood":  "Ainkawa",
		"housing_type":  "rented",
		"men_count":     "3",
		"id_photo_path": "/uploads/id.jpg",
	}

	check := func(t *testing.T, targetID int64) {
		t.Helper()
		status, resp := patchUserAs(t, pool, actor.id, targetID, body)
		if status != http.StatusOK {
			t.Fatalf("PATCH status = %d, want 200 (body: %v)", status, resp)
		}
		var nationalID, neighborhood, housingType, menCount, idPhoto string
		if err := pool.QueryRow(ctx,
			`SELECT national_id, neighborhood, housing_type, men_count, id_photo_path
			   FROM user_profiles WHERE user_id = $1`, targetID).
			Scan(&nationalID, &neighborhood, &housingType, &menCount, &idPhoto); err != nil {
			t.Fatalf("read profile back: %v", err)
		}
		if nationalID != "19900101234" || neighborhood != "Ainkawa" ||
			housingType != "rented" || menCount != "3" || idPhoto != "/uploads/id.jpg" {
			t.Errorf("stored row = %q/%q/%q/%q/%q, want the five values that were sent",
				nationalID, neighborhood, housingType, menCount, idPhoto)
		}
	}

	t.Run("account that already has a profile row", func(t *testing.T) {
		target := insertAccount(t, pool, "user", "")
		if _, err := pool.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture)
			 VALUES ($1, 'Ali', 'male', 'Erbil', '')`, target.id); err != nil {
			t.Fatalf("seed profile: %v", err)
		}
		check(t, target.id)
	})

	t.Run("account with no profile row yet", func(t *testing.T) {
		target := insertAccount(t, pool, "user", "")
		check(t, target.id)
	})
}

// TestUserProfileEditClearsAColumn — an empty box means "clear this", the same
// meaning the typed fields already give it.
func TestUserProfileEditClearsAColumn(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture, tribe_clan)
		 VALUES ($1, 'Ali', 'male', 'Erbil', '', 'Barzani')`, target.id); err != nil {
		t.Fatalf("seed profile: %v", err)
	}

	if status, resp := patchUserAs(t, pool, actor.id, target.id,
		map[string]any{"tribe_clan": ""}); status != http.StatusOK {
		t.Fatalf("PATCH status = %d, want 200 (body: %v)", status, resp)
	}

	var tribe string
	if err := pool.QueryRow(ctx,
		`SELECT tribe_clan FROM user_profiles WHERE user_id = $1`, target.id).Scan(&tribe); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if tribe != "" {
		t.Errorf("tribe_clan = %q, want it cleared", tribe)
	}
}
