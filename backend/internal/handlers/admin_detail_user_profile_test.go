// admin_detail_user_profile_test.go — the tests that guard widening the detail
// allow-list to the whole registration profile.
//
// The owner's complaint was that the account-detail screen showed "—" for data
// the person had entered; the fix was to SELECT 104 more columns. Widening a
// security boundary is the moment to prove the boundary still holds, so the
// first test here is the credential test — and it now asks the question of
// EVERY resource in the allow-list, not just `users`.
//
// Integration tests need a throwaway Postgres and skip unless TEST_DATABASE_URL
// is set, matching every other test in this package:
//
//	createdb godonation_profile
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_profile?sslmode=disable' \
//	  go test ./internal/handlers/ -run UserProfileDetail -v
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"testing"
)

// credentialColumnRe matches a column name that must never reach a browser.
// Deliberately broader than the two columns that exist today: the point of the
// allow-list is that the NEXT secret is safe too, and this test should notice
// if one is ever added to a listed table.
var credentialColumnNames = []string{
	"password_hash", "password", "google_sub", "token", "access_token",
	"refresh_token", "secret", "api_key", "otp_code", "reset_token",
	"recovery_answer",
}

// TestNoDetailResourceEmitsACredentialColumn is the test that matters most.
//
// It walks every slug in detailColumns — not just `users` — and fails if any
// declared column name looks like a credential. This is a static check on the
// list itself, so it needs no database and no fixture row: a column that is not
// on the list cannot be emitted, so proving nothing credential-shaped is on any
// list proves nothing credential-shaped can be emitted.
func TestNoDetailResourceEmitsACredentialColumn(t *testing.T) {
	for slug, cols := range detailColumns {
		for _, col := range cols {
			lower := strings.ToLower(col)
			for _, bad := range credentialColumnNames {
				if lower == bad {
					t.Errorf("resource %q lists the credential column %q", slug, col)
				}
			}
		}
	}
	// The merged-in profile list is part of the same payload and gets the same
	// question asked of it.
	for _, col := range userProfileDetailColumns {
		lower := strings.ToLower(col)
		for _, bad := range credentialColumnNames {
			if lower == bad {
				t.Errorf("the user profile list includes the credential column %q", col)
			}
		}
	}
}

// TestUserProfileDetailNeverSerialisesACredential is the same question asked of
// the ACTUAL RESPONSE, for every resource, with a real row present. The static
// test above proves the list is clean; this proves the handler emits nothing
// beyond it — a merge helper that dumps an extra row would be caught here and
// nowhere else.
func TestUserProfileDetailNeverSerialisesACredential(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	givePassword(t, pool, target.id)
	insertFullProfile(t, pool, target.id)

	for slug := range detailColumns {
		// Every resource is asked for id 1 and for the seeded user; a 404 for a
		// table with no rows is a fine answer, the assertion is about the BODY.
		for _, id := range []int64{1, target.id} {
			_, body := fetchDetailAs(t, pool, actor.id, slug, id)
			raw, err := json.Marshal(body)
			if err != nil {
				t.Fatalf("marshal %s/%d response: %v", slug, id, err)
			}
			wire := strings.ToLower(string(raw))
			for _, bad := range credentialColumnNames {
				if strings.Contains(wire, `"`+bad+`"`) {
					t.Errorf("GET detail/%s/%d serialised a %q key", slug, id, bad)
				}
			}
		}
	}
}

// TestUserProfileDetailListMatchesTheSchema pins the allow-list against the
// live table, so a migration that adds a profile column is noticed instead of
// silently producing another "—" on the screen this whole change exists to fix.
//
// Failing here is not automatically a bug — the right answer may be to add the
// column to the list, or to add it to the documented omissions below. What is
// not allowed is for the two to drift unnoticed.
func TestUserProfileDetailListMatchesTheSchema(t *testing.T) {
	pool := newAuthTestPool(t)

	// The three columns deliberately left out. Kept here as well as in the
	// source comment so removing one from the source without a decision fails.
	omitted := map[string]bool{"id": true, "user_id": true, "field_privacy": true}

	rows, err := pool.Query(context.Background(),
		`SELECT column_name FROM information_schema.columns
		  WHERE table_name = 'user_profiles'`)
	if err != nil {
		t.Fatalf("read user_profiles schema: %v", err)
	}
	defer rows.Close()
	schema := map[string]bool{}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("scan column name: %v", err)
		}
		schema[name] = true
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate schema: %v", err)
	}

	listed := map[string]bool{}
	for _, c := range userProfileDetailColumns {
		if !schema[c] {
			t.Errorf("the allow-list names %q, which user_profiles does not have", c)
		}
		if listed[c] {
			t.Errorf("the allow-list names %q twice", c)
		}
		listed[c] = true
	}

	var missing []string
	for c := range schema {
		if !listed[c] && !omitted[c] {
			missing = append(missing, c)
		}
	}
	sort.Strings(missing)
	if len(missing) > 0 {
		t.Errorf("user_profiles columns neither shown nor documented as omitted: %v", missing)
	}
}

// TestUserProfileDetailFlagsPrivateFields — a field the user switched off in
// the app's Privacy Settings must be IDENTIFIABLE in the payload. Staff still
// see the value (their access is governed by `sensitive_data`, not by this),
// but the response has to say which fields the person marked private so the
// screen can label them rather than presenting them as freely shared.
func TestUserProfileDetailFlagsPrivateFields(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")

	if _, err := pool.Exec(context.Background(),
		`INSERT INTO user_profiles (user_id, full_name, gender, address, field_privacy)
		 VALUES ($1, 'Sara Kareem', 'female', 'Ainkawa', $2)`,
		target.id, []string{"address", "date_of_birth"}); err != nil {
		t.Fatalf("insert profile with privacy choices: %v", err)
	}

	item := detailItemAs(t, pool, actor.id, "users", target.id)

	raw, ok := item["_privacy_hidden"].([]any)
	if !ok {
		t.Fatalf("_privacy_hidden missing or not a list: %#v", item["_privacy_hidden"])
	}
	got := map[string]bool{}
	for _, v := range raw {
		got[v.(string)] = true
	}
	for _, want := range []string{"address", "date_of_birth"} {
		if !got[want] {
			t.Errorf("%q was marked private by the user but is not flagged in the payload", want)
		}
	}
	if got["full_name"] {
		t.Error("full_name is flagged private, but the user never hid it")
	}
	// And the value is still there for staff to work with — flagged, not hidden.
	if item["address"] != "Ainkawa" {
		t.Errorf("address = %v, want the real value (staff access is a separate control)", item["address"])
	}
}

// TestUserProfileDetailSurvivesAnEmptyProfile — the two shapes an account with
// nothing entered can take. Both must render; neither may 500.
func TestUserProfileDetailSurvivesAnEmptyProfile(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")

	t.Run("no user_profiles row at all", func(t *testing.T) {
		target := insertAccount(t, pool, "user", "")
		item := detailItemAs(t, pool, actor.id, "users", target.id)
		if item["id"] == nil {
			t.Error("the account row itself did not render")
		}
		if _, ok := item["_privacy_hidden"].([]any); !ok {
			t.Errorf("_privacy_hidden must still be a list, got %#v", item["_privacy_hidden"])
		}
		if _, ok := item["_documents"].([]any); !ok {
			t.Errorf("_documents must still be a list, got %#v", item["_documents"])
		}
	})

	t.Run("a profile row with every column null", func(t *testing.T) {
		target := insertAccount(t, pool, "user", "")
		// The four NOT NULL columns take '' — everything else stays NULL.
		if _, err := pool.Exec(context.Background(),
			`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture)
			 VALUES ($1, '', '', '', '')`, target.id); err != nil {
			t.Fatalf("insert empty profile: %v", err)
		}
		item := detailItemAs(t, pool, actor.id, "users", target.id)
		if _, present := item["national_id"]; !present {
			t.Error("a null column must still be PRESENT as a key, so the screen can say 'blank' rather than omitting the field")
		}
		// Most of these columns were added NOT NULL DEFAULT '' (migration 072
		// onward), so "blank" arrives as "" rather than as null. Either is
		// empty; what matters is that the key is there and carries no value.
		if v := item["national_id"]; v != nil && v != "" {
			t.Errorf("national_id = %v, want empty", v)
		}
	})
}

// TestUserProfileDetailReturnsUploadedDocuments — the uploaded documents the
// owner asked for. They hang off the user's beneficiary case, so a user with no
// case gets an empty list rather than an error.
func TestUserProfileDetailReturnsUploadedDocuments(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")

	// case_code is UNIQUE, so derive it from the throwaway user id rather than
	// hardcoding one — repeat runs against the same database must not collide.
	caseCode := fmt.Sprintf("BC-TEST-%d", target.id)

	var caseID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases (user_id, case_code, public_title, actual_needs)
		 VALUES ($1, $2, 'Test case', 'help') RETURNING id`,
		target.id, caseCode).Scan(&caseID); err != nil {
		t.Fatalf("insert case: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO beneficiary_case_documents (case_id, document_type, file_path)
		 VALUES ($1, 'id_card', '/uploads/id-card.jpg')`, caseID); err != nil {
		t.Fatalf("insert document: %v", err)
	}

	item := detailItemAs(t, pool, actor.id, "users", target.id)
	docs, ok := item["_documents"].([]any)
	if !ok || len(docs) != 1 {
		t.Fatalf("_documents = %#v, want one document", item["_documents"])
	}
	doc := docs[0].(map[string]any)
	if doc["file_path"] != "/uploads/id-card.jpg" {
		t.Errorf("file_path = %v", doc["file_path"])
	}
	if doc["document_type"] != "id_card" {
		t.Errorf("document_type = %v", doc["document_type"])
	}
	if doc["case_code"] != caseCode {
		t.Errorf("case_code = %v — the join to beneficiary_cases did not run", doc["case_code"])
	}
}

// insertFullProfile seeds a profile row with a value in a spread of the newly
// exposed columns, so response-shape assertions run against a populated row
// rather than an empty one.
func insertFullProfile(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO user_profiles
		   (user_id, full_name, gender, address, profile_picture,
		    national_id, name_first, name_family, phone1, governorate,
		    neighborhood, housing_type, is_employed, education_level,
		    men_count, id_photo_path)
		 VALUES ($1, 'Ali Hassan', 'male', 'Ainkawa', 'p.jpg',
		         '19900101234', 'Ali', 'Hassan', '9647701234567', 'Erbil',
		         'Ainkawa', 'owned', 'yes', 'bachelor', '2', '/uploads/id.jpg')`,
		userID); err != nil {
		t.Fatalf("insert full profile: %v", err)
	}
}
