// admin_detail_columns_test.go — what a detail page is allowed to send back.
//
// # WHY THIS FILE EXISTS
//
// GET /api/admin/detail/:resource/:id ran `SELECT *` and then redacted the
// columns whose NAME looked like contact information (phone/email/whatsapp/…).
// Everything else went to the browser verbatim — including `users.password_hash`,
// the bcrypt hash the account signs in with. Production holds ten of them.
//
// The mechanism was the wrong way round. A redaction list has to be updated for
// every new secret or it leaks by default, and this one only ever knew about
// contact fields, so `password_hash` was never in scope for it. Worse, the route
// carries no per-module permission at all — it is one of the handful main.go
// leaves "ungated beyond RequireAdmin" — so the hash reached ANY staff account,
// including an `employee` who is not even granted `sensitive_data`.
//
// The fix inverts it: each resource declares the columns it may emit, and the
// query asks for exactly those. A column nobody has listed is invisible, so the
// next migration that adds a secret is safe by default rather than by memory.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_b7
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_b7?sslmode=disable' \
//	  go test ./internal/handlers/ -run DetailColumns -v
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ─── Harness ────────────────────────────────────────────────────────────

// fetchDetailAs drives the REAL route as main.go wires it: RequireAdmin and
// nothing else. That absence is deliberate in the test as well as in
// production — it is why an employee could read the hash.
func fetchDetailAs(t *testing.T, pool *pgxpool.Pool, actorID int64, resource string, targetID int64) (int, map[string]any) {
	t.Helper()
	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/admin/detail/:resource/:id",
		auth.RequireAdmin(tokenStore),
		NewAdminDetailHandler(pool, permissions.New(pool)).Detail,
	)

	req := httptest.NewRequest(http.MethodGet,
		"/api/admin/detail/"+resource+"/"+strconv.FormatInt(targetID, 10), nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

// detailItemAs fetches a detail row and hands back its `item` object, failing
// the test if the request did not succeed — an assertion about "the hash is
// absent" is worthless if the body was a 404.
func detailItemAs(t *testing.T, pool *pgxpool.Pool, actorID int64, resource string, targetID int64) map[string]any {
	t.Helper()
	status, body := fetchDetailAs(t, pool, actorID, resource, targetID)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %v)", status, body)
	}
	item, ok := body["item"].(map[string]any)
	if !ok {
		t.Fatalf("response has no item object: %v", body)
	}
	return item
}

// givePassword sets a real bcrypt hash on an account, reproducing the
// production shape: ten rows carry one, including two super_admins.
func givePassword(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	hash, err := bcrypt.GenerateFromPassword([]byte("hunter2"), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	if _, err := pool.Exec(context.Background(),
		`UPDATE users SET password_hash = $1, google_sub = $2 WHERE id = $3`,
		string(hash), "google-oauth-subject-1234", userID); err != nil {
		t.Fatalf("set password_hash: %v", err)
	}
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestDetailColumnsWithholdsCredentials is the B7 regression test: no caller,
// at any tier, receives a credential column from the detail endpoint.
func TestDetailColumnsWithholdsCredentials(t *testing.T) {
	pool := newAuthTestPool(t)

	// Every tier that can reach the route, most privileged first. The super_admin
	// case matters as much as the employee one: a hash is not a thing to hand to
	// a browser, however trusted the person in front of it.
	for _, tier := range []string{"super_admin", "admin", "supervisor", "employee"} {
		t.Run(tier+" does not receive password_hash", func(t *testing.T) {
			actor := insertAccount(t, pool, tier, "")
			target := insertAccount(t, pool, "user", "")
			givePassword(t, pool, target.id)

			item := detailItemAs(t, pool, actor.id, "users", target.id)

			if v, present := item["password_hash"]; present {
				t.Errorf("password_hash reached the browser: %v", v)
			}
			if v, present := item["google_sub"]; present {
				t.Errorf("google_sub (an auth identifier) reached the browser: %v", v)
			}
		})
	}

	// A staff target is the case that turns a leak into an escalation: the hash
	// of an account that can open the dashboard.
	t.Run("a super_admin's own hash is not readable by an employee", func(t *testing.T) {
		actor := insertAccount(t, pool, "employee", "")
		target := insertAccount(t, pool, "super_admin", "")
		givePassword(t, pool, target.id)

		item := detailItemAs(t, pool, actor.id, "users", target.id)

		if v, present := item["password_hash"]; present {
			t.Errorf("a Super-Admin's bcrypt hash reached an employee's browser: %v", v)
		}
	})
}

// wantUserDetailKeys is every key the users detail view is allowed to return:
// the account row minus its two credential columns, plus the registration
// profile fields the handler merges in.
//
// It is written out here rather than read from detailColumns on purpose. A test
// that derives its expectation from the code it is testing proves only that the
// code agrees with itself — deleting a column from the map would keep such a
// test green. This list is the independent statement of what may cross the wire.
var wantUserDetailKeys = map[string]bool{
	// users
	"id": true, "phone": true, "role_id": true, "active": true, "is_admin": true,
	"created_at": true, "registration_status": true, "registration_submitted_at": true,
	"registration_reviewed_at": true, "registration_reviewed_by": true,
	"registration_reject_reason": true, "username": true, "staff_tier": true,
	"email": true, "account_status": true, "notifications_enabled": true,
	"is_guest": true, "wallet_balance_iqd": true,
	// merged from user_profiles — every column of that table except its own
	// primary key, its user_id (duplicated by the account's id) and
	// field_privacy (a settings blob, re-emitted as the _privacy_hidden meta
	// key below). Written out from `information_schema` rather than derived
	// from userProfileDetailColumns, for the reason in the comment above.
	"address": true, "age_0_5_count": true, "age_10_15_count": true, "age_15_25_count": true,
	"age_25_40_count": true, "age_40_plus_count": true, "age_5_10_count": true, "alias_name": true,
	"availability": true, "available_furniture": true, "certificates_count": true, "chronic_illnesses": true,
	"city": true, "consent_share_info": true, "consent_show_real_name": true, "cv_photo_path": true,
	"date_of_birth": true, "disability_type": true, "display_name_mode": true, "district": true,
	"divorced_count": true, "education_level": true, "emergency_phone": true,
	"experience": true, "eyesight_condition": true, "families_count": true, "family_size": true,
	"female_children_count": true, "floors_count": true, "full_name": true, "gender": true,
	"golden_square_photo_path": true, "governorate": true, "gps_lat": true, "gps_lng": true,
	"graduation_cert_photo_path": true, "grantor_code": true, "has_disability": true, "height": true,
	"house_facade_photo_path": true, "house_inside_photo_path": true, "house_outside_photo_path": true, "household_disabled_count": true,
	"household_employees_count": true, "housing_area": true, "housing_side": true, "housing_status": true,
	"housing_type": true, "id_photo_path": true, "is_employed": true, "job_description": true,
	"languages": true, "male_children_count": true, "marital_status": true, "medical_conditions_count": true,
	"medical_conditions_desc": true, "medical_report_photo_path": true, "men_count": true, "monthly_income": true,
	"name_family": true, "name_father": true, "name_first": true, "name_grandfather": true,
	"national_id": true, "nationality": true, "nearest_landmark": true, "needs_description": true,
	"neighborhood": true, "occupation": true, "orphans_count": true, "other_certificate": true,
	"owns_car": true, "passport_photo_path": true, "phone1": true, "phone2": true,
	"previous_occupation": true, "profile_picture": true, "property_proof_photo_path": true, "ration_card_photo_path": true,
	"recipient_code": true, "registered_social_welfare": true, "registered_unemployed": true, "rental_amount": true,
	"residence_card_photo_path": true, "residency_status": true, "rooms_count": true, "skills": true,
	"smoking_status": true, "social_facebook": true, "social_instagram": true, "social_other": true,
	"social_telegram": true, "students_count": true, "title_surname": true, "tribe_clan": true,
	"volunteer_code": true, "wage_amount": true, "weight": true, "widows_count": true,
	"women_count": true, "working_hours": true, "working_members_count": true, "workplace": true,
	// Meta keys — not columns. Underscore-prefixed so the SPA can tell them
	// apart from fields it must render as rows.
	"_privacy_hidden": true, "_documents": true,
}

// TestDetailColumnsIsDenyByDefault pins the MECHANISM, not just today's one
// leak: the response may only contain columns someone deliberately listed. This
// is what makes the next migration safe without anyone remembering this file.
func TestDetailColumnsIsDenyByDefault(t *testing.T) {
	pool := newAuthTestPool(t)

	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	givePassword(t, pool, target.id)

	item := detailItemAs(t, pool, actor.id, "users", target.id)

	for key := range item {
		if !wantUserDetailKeys[key] {
			t.Errorf("column %q was emitted without being on any allow-list", key)
		}
	}
}

// TestDetailColumnsStillShowsTheRecord is the other half: withholding the hash
// must not blank the page. These are the fields the عرض view is FOR.
func TestDetailColumnsStillShowsTheRecord(t *testing.T) {
	pool := newAuthTestPool(t)

	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO user_profiles (user_id, full_name, gender, address, profile_picture, city)
		 VALUES ($1, 'Ali Hassan', 'male', 'Ainkawa', '', 'Erbil')`, target.id); err != nil {
		t.Fatalf("insert profile: %v", err)
	}

	item := detailItemAs(t, pool, actor.id, "users", target.id)

	for _, key := range []string{
		"id", "phone", "role_id", "created_at", "staff_tier",
		"account_status", "registration_status", "wallet_balance_iqd",
		"full_name", "city", // merged in from user_profiles
	} {
		if _, present := item[key]; !present {
			t.Errorf("detail view lost the %q field", key)
		}
	}
	if got := item["full_name"]; got != "Ali Hassan" {
		t.Errorf("full_name = %v, want %q", got, "Ali Hassan")
	}
}

// TestEveryDetailResourceDeclaresItsColumns keeps the fail-closed path from
// ever firing in front of a user. Adding a resource to resourceTables without
// listing its columns is now a compile-and-test-time mistake rather than a
// 500 someone discovers by clicking عرض in production.
//
// No database needed, so this one runs on a bare checkout.
func TestEveryDetailResourceDeclaresItsColumns(t *testing.T) {
	for slug, table := range resourceTables {
		cols, ok := detailColumns[slug]
		if !ok || len(cols) == 0 {
			t.Errorf("resource %q (table %s) has no column allow-list — its detail page would fail closed", slug, table)
			continue
		}
		// A detail page keyed by :id that cannot return the id is a bug in the
		// list, not in the caller.
		found := false
		for _, c := range cols {
			if c == "id" {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("resource %q does not list its own id column", slug)
		}
	}
}

// TestUsersListWithholdsCredentials pins the LIST endpoint too. It was already
// clean — it selects explicit columns and exposes only a `has_password` boolean
// — so unlike the tests above this one passes before the fix as well. It is here
// so that stays true.
func TestUsersListWithholdsCredentials(t *testing.T) {
	pool := newAuthTestPool(t)

	target := insertAccount(t, pool, "user", "")
	givePassword(t, pool, target.id)

	res, err := users.NewStore(pool).PaginatedList(context.Background(), 1, 200, "", "")
	if err != nil {
		t.Fatalf("paginated list: %v", err)
	}
	raw, err := json.Marshal(res.Items)
	if err != nil {
		t.Fatalf("marshal list: %v", err)
	}
	// Search the SERIALISED response, not the struct: what matters is what
	// crosses the wire.
	wire := string(raw)
	for _, secret := range []string{"password_hash", "google_sub"} {
		if strings.Contains(wire, secret) {
			t.Errorf("the users list serialises %s", secret)
		}
	}
	// The boolean the dashboard actually needs must survive.
	if !strings.Contains(wire, "has_password") {
		t.Error("the users list no longer reports has_password")
	}
}
