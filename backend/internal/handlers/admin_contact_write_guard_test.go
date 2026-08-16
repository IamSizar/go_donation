// admin_contact_write_guard_test.go — the safety net H10's redaction stands on.
//
// # WHY THIS FILE EXISTS, AND WHY IT COMES FIRST
//
// H10 asks that staff without the `sensitive_data` permission stop receiving
// raw phone numbers and email addresses. The obvious way to deliver that —
// replace the value with "••••61" in the list response — is a data-destroying
// change on this codebase, because the dashboard's edit modal is prefilled FROM
// THE LIST ROW it just rendered:
//
//	admin-web/src/pages/UsersPage.tsx  flattenForEdit()  → phone: u.phone
//	backend/.../admin_edit.go          User()            → UPDATE users SET phone = $1
//
// So a supervisor who opens تعديل on a masked row, changes the city, and presses
// حفظ would store "••••61" as that account's phone. `users.phone` is the sign-in
// identity (auth looks the row up by the normalised value), so that account can
// never sign in again — and nothing on the screen would say so.
//
// The rule these tests pin is therefore NOT "who may write a phone" (that is
// H13's tier floor + credential rule, admin_user_guard.go, still in force). It
// is narrower and absolute:
//
//	A VALUE THAT CARRIES THE REDACTION MARK IS NEVER PERSISTED, BY ANYONE.
//
// The mark is U+2022 BULLET, which no real phone number, email address or
// WhatsApp number contains, so the rule has no false positives on contact
// fields. It is scoped to contact fields precisely BECAUSE prose fields
// (a partner's description, a case's notes) legitimately contain bullets.
//
// These tests are written against the four PATCH endpoints whose edit form is
// prefilled from a list the redaction will mask. They failed before
// admin_contact_write_guard.go existed — every one of them wrote the mask into
// the database and answered 200.
//
// Integration tests need a throwaway Postgres and skip unless TEST_DATABASE_URL
// is set, matching every other integration test in this package:
//
//	createdb godonation_h10
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test ./internal/handlers/ -run ContactWriteGuard -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// ─── Harness ────────────────────────────────────────────────────────────

// patchAsStaff replays a PATCH against `path` as `actorID`, through the REAL
// request chain main.go builds for that route: the staff gate, the (module,
// edit) permission, then the handler. Nothing is stubbed — the point is what
// the deployed endpoint does, not what one helper returns.
func patchAsStaff(t *testing.T, pool *pgxpool.Pool, actorID int64,
	module, path string, handler gin.HandlerFunc, body map[string]any) (int, map[string]any) {
	t.Helper()

	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.PATCH("/api/admin/:resource/:id",
		auth.RequireAdmin(tokenStore),
		auth.RequirePermission(permissions.New(pool), module, "edit"),
		handler,
	)

	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPatch, path, bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

// scalar reads one column off one row, so a test can assert on the DATABASE
// rather than on the status code. A refusal that still wrote the row is the
// same bug wearing a 400.
func scalar(t *testing.T, pool *pgxpool.Pool, query string, args ...any) string {
	t.Helper()
	var v *string
	if err := pool.QueryRow(context.Background(), query, args...).Scan(&v); err != nil {
		t.Fatalf("read %q: %v", query, err)
	}
	if v == nil {
		return ""
	}
	return *v
}

// insertCase creates one beneficiary case carrying a real phone number.
func insertCase(t *testing.T, pool *pgxpool.Pool, phone string) int64 {
	t.Helper()
	var id int64
	code := "H10-" + strconv.FormatInt(int64(len(phone))*1000+int64(len(t.Name())), 10) + "-" + randomTestPhone()
	err := pool.QueryRow(context.Background(),
		`INSERT INTO beneficiary_cases (case_code, public_title, full_name, phone)
		 VALUES ($1, 'H10 fixture', 'Fixture Person', $2) RETURNING id`, code, phone).Scan(&id)
	if err != nil {
		t.Fatalf("insert beneficiary case: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, id)
	})
	return id
}

// insertVolunteerApplication creates one volunteer application carrying a phone.
func insertVolunteerApplication(t *testing.T, pool *pgxpool.Pool, phone string) int64 {
	t.Helper()
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO volunteer_applications (full_name, phone, status)
		 VALUES ('H10 fixture', $1, 'submitted') RETURNING id`, phone).Scan(&id)
	if err != nil {
		t.Fatalf("insert volunteer application: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM volunteer_applications WHERE id = $1`, id)
	})
	return id
}

// insertProjectRequest creates one beneficiary project request carrying both a
// contact phone and a contact email.
func insertProjectRequest(t *testing.T, pool *pgxpool.Pool, owner int64, phone, email string) int64 {
	t.Helper()
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO beneficiary_project_requests
		   (user_id, project_title, category, summary, description_long, amount_needed,
		    location, beneficiary_community_name, contact_phone, contact_email)
		 VALUES ($1, 'H10 fixture', 'general', 'summary', 'description', 1000,
		         'Erbil', 'Fixture community', $2, $3)
		 RETURNING id`, owner, phone, email).Scan(&id)
	if err != nil {
		t.Fatalf("insert project request: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_project_requests WHERE id = $1`, id)
	})
	return id
}

// ─── The rule ───────────────────────────────────────────────────────────

// TestContactWriteGuardRejectsMaskedValues is THE test the whole H10 change
// rests on. Each case sends back exactly what a masked list row would have
// prefilled into the edit form, and asserts twice: the request is refused with
// a translatable code, AND the stored value is untouched.
func TestContactWriteGuardRejectsMaskedValues(t *testing.T) {
	pool := newAuthTestPool(t)

	// What the redaction actually emits, so the test cannot drift from it.
	maskedPhone := sensitive.Mask("9647500000903") // "••••03"
	maskedEmail := sensitive.Mask("donor@example.com")
	shortMask := sensitive.Mask("7") // "••" — the <=2 char branch

	t.Run("users PATCH refuses a masked phone", func(t *testing.T) {
		// A supervisor holds (users, edit) by default and does NOT hold
		// sensitive_data — the exact person the redaction is for, and the exact
		// person who would have destroyed a sign-in number.
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")
		before := phoneOf(t, pool, target.id)

		status, body := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"phone": maskedPhone, "city": "Erbil"})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400 (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "redacted_contact_write" {
			t.Errorf("code = %q, want %q", got, "redacted_contact_write")
		}
		if after := phoneOf(t, pool, target.id); after != before {
			t.Fatalf("SIGN-IN NUMBER DESTROYED: %q → %q", before, after)
		}
	})

	t.Run("users PATCH refuses the short mask too", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")
		before := phoneOf(t, pool, target.id)

		status, _ := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"phone": shortMask})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400", status)
		}
		if after := phoneOf(t, pool, target.id); after != before {
			t.Fatalf("SIGN-IN NUMBER DESTROYED: %q → %q", before, after)
		}
	})

	t.Run("a super_admin is refused as well", func(t *testing.T) {
		// The rule is about the VALUE, not the rank. A Super-Admin sees the real
		// number, so a bullet string from them is a bug in the client, never an
		// intention — storing it would break the account just as thoroughly.
		actor := insertAccount(t, pool, "super_admin", "")
		target := insertAccount(t, pool, "user", "")
		before := phoneOf(t, pool, target.id)

		status, _ := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"phone": maskedPhone})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400", status)
		}
		if after := phoneOf(t, pool, target.id); after != before {
			t.Fatalf("SIGN-IN NUMBER DESTROYED: %q → %q", before, after)
		}
	})

	t.Run("beneficiary_cases PATCH refuses a masked phone", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		const real = "9647700000010"
		id := insertCase(t, pool, real)

		status, body := patchAsStaff(t, pool, actor.id, "beneficiary",
			"/api/admin/beneficiary_cases/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).BeneficiaryCase,
			map[string]any{"phone": maskedPhone, "city": "Erbil"})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400 (body: %v)", status, body)
		}
		if got := scalar(t, pool, `SELECT phone FROM beneficiary_cases WHERE id = $1`, id); got != real {
			t.Fatalf("case phone overwritten: %q → %q", real, got)
		}
	})

	t.Run("volunteer_applications PATCH refuses a masked phone", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		const real = "9647700000011"
		id := insertVolunteerApplication(t, pool, real)

		status, body := patchAsStaff(t, pool, actor.id, "volunteers",
			"/api/admin/volunteer_applications/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).VolunteerApplication,
			map[string]any{"phone": maskedPhone})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400 (body: %v)", status, body)
		}
		if got := scalar(t, pool, `SELECT phone FROM volunteer_applications WHERE id = $1`, id); got != real {
			t.Fatalf("application phone overwritten: %q → %q", real, got)
		}
	})

	t.Run("project_requests PATCH refuses a masked contact phone", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		owner := insertAccount(t, pool, "user", "")
		const realPhone, realEmail = "9647700000012", "owner@example.com"
		id := insertProjectRequest(t, pool, owner.id, realPhone, realEmail)

		status, body := patchAsStaff(t, pool, actor.id, "beneficiary",
			"/api/admin/beneficiary_project_requests/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).ProjectRequest,
			map[string]any{"contact_phone": maskedPhone})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400 (body: %v)", status, body)
		}
		if got := scalar(t, pool, `SELECT contact_phone FROM beneficiary_project_requests WHERE id = $1`, id); got != realPhone {
			t.Fatalf("contact_phone overwritten: %q → %q", realPhone, got)
		}
	})

	t.Run("project_requests PATCH refuses a masked contact email", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		owner := insertAccount(t, pool, "user", "")
		const realPhone, realEmail = "9647700000013", "owner2@example.com"
		id := insertProjectRequest(t, pool, owner.id, realPhone, realEmail)

		status, body := patchAsStaff(t, pool, actor.id, "beneficiary",
			"/api/admin/beneficiary_project_requests/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).ProjectRequest,
			map[string]any{"contact_email": maskedEmail})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400 (body: %v)", status, body)
		}
		if got := scalar(t, pool, `SELECT contact_email FROM beneficiary_project_requests WHERE id = $1`, id); got != realEmail {
			t.Fatalf("contact_email overwritten: %q → %q", realEmail, got)
		}
	})

	t.Run("the refusal is atomic — no other field lands either", func(t *testing.T) {
		// The guard runs BEFORE any write, so a rejected request must not leave
		// the row half-edited. Checked on the case row because its PATCH builds
		// one UPDATE over many columns.
		actor := insertAccount(t, pool, "supervisor", "")
		const real = "9647700000014"
		id := insertCase(t, pool, real)

		status, _ := patchAsStaff(t, pool, actor.id, "beneficiary",
			"/api/admin/beneficiary_cases/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).BeneficiaryCase,
			map[string]any{"phone": maskedPhone, "full_name": "Changed Name"})

		if status != http.StatusBadRequest {
			t.Errorf("status = %d, want 400", status)
		}
		if got := scalar(t, pool, `SELECT full_name FROM beneficiary_cases WHERE id = $1`, id); got != "Fixture Person" {
			t.Errorf("full_name was written despite the refusal: %q", got)
		}
	})
}

// TestContactWriteGuardAllowsRealValues is the other half. A guard that also
// refuses genuine numbers would quietly remove "fix a beneficiary's mistyped
// phone" — the everyday task H13 deliberately kept available to every rank
// holding تعديل — and nobody would notice until an operator complained.
func TestContactWriteGuardAllowsRealValues(t *testing.T) {
	pool := newAuthTestPool(t)

	t.Run("a real phone still writes on users", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")
		const corrected = "9647700000020"

		status, body := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"phone": corrected})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := phoneOf(t, pool, target.id); got != corrected {
			t.Errorf("phone = %q, want %q — the guard blocked a legitimate edit", got, corrected)
		}
	})

	t.Run("a real phone still writes on a beneficiary case", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		id := insertCase(t, pool, "9647700000021")
		const corrected = "9647700000022"

		status, body := patchAsStaff(t, pool, actor.id, "beneficiary",
			"/api/admin/beneficiary_cases/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).BeneficiaryCase,
			map[string]any{"phone": corrected})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := scalar(t, pool, `SELECT phone FROM beneficiary_cases WHERE id = $1`, id); got != corrected {
			t.Errorf("phone = %q, want %q", got, corrected)
		}
	})

	t.Run("prose keeps its bullets", func(t *testing.T) {
		// The reason the guard is scoped to CONTACT fields rather than applied
		// to the whole body: staff write bulleted lists into free text, and an
		// Arabic case note beginning "• " is ordinary content, not a redaction.
		actor := insertAccount(t, pool, "supervisor", "")
		id := insertCase(t, pool, "9647700000023")
		const notes = "• سكن غير ملائم\n• دخل شهري منخفض"

		status, body := patchAsStaff(t, pool, actor.id, "beneficiary",
			"/api/admin/beneficiary_cases/"+strconv.FormatInt(id, 10),
			NewAdminEditHandler(pool).BeneficiaryCase,
			map[string]any{"actual_needs": notes})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := scalar(t, pool, `SELECT actual_needs FROM beneficiary_cases WHERE id = $1`, id); got != notes {
			t.Errorf("actual_needs = %q, want the bulleted list back unchanged", got)
		}
	})
}
