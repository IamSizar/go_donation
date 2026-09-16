// admin_user_phone_unique_test.go — OPOS #26636.
//
// The owner's rule, verbatim: "no phone number can be on 2 accounts".
//
// `users.phone` has carried a UNIQUE constraint since migration 001, and every
// app-side path (sign-in, OTP, the guest upgrade) reduces the typed number to
// ONE canonical form with auth.NormalizePhone before it touches the column. The
// two DASHBOARD write paths did not: POST /api/admin/users (admin_status.go
// CreateUser) and PATCH /api/admin/users/:id (admin_edit.go User) both stored
// the string after a bare strings.TrimSpace. A UNIQUE index compares strings,
// so "07508582031" and "9647508582031" are two different keys for ONE human
// number — the constraint let the second row in, and the owner's rule was
// broken by exactly the screen staff use most.
//
// These tests drive the REAL routes through the REAL middleware chain against
// the REAL migrated schema. They are the regression proof for the fix in
// phone_identity.go.
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_phoneuniq?sslmode=disable' \
//	  go test ./internal/handlers/ -run PhoneIdentity -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newUserCreateRouter wires POST /api/admin/users exactly as main.go does
// (main.go:1166): the staff gate, then the (users, add) permission, then the
// handler. Nothing is stubbed — same reasoning as newUserEditRouter beside it.
func newUserCreateRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/api/admin/users",
		auth.RequireAdmin(auth.NewTokenStore(pool)),
		auth.RequirePermission(permissions.New(pool), "users", "add"),
		NewAdminStatusHandler(pool, nil, nil).CreateUser,
	)
	return r
}

// createUserAs mints a real access token for actorID and posts the New User
// window's body. Returns the status and decoded body so a test can assert on
// the translatable `code`, not on English prose.
func createUserAs(t *testing.T, pool *pgxpool.Pool, actorID int64, body map[string]any) (int, map[string]any) {
	t.Helper()
	status, decoded, _ := createUserOn(t, newUserCreateRouter(pool), pool, actorID, body)
	return status, decoded
}

// createUserOn is createUserAs against a router the caller already built, so
// the concurrency test can share one engine across goroutines.
func createUserOn(t *testing.T, router *gin.Engine, pool *pgxpool.Pool, actorID int64, body map[string]any) (int, map[string]any, string) {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/admin/users", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded, rec.Body.String()
}

// dropCreatedUser removes a row this test made, plus the profile row that came
// with it. insertAccount registers its own cleanup; a row born inside the
// handler has nobody to do it.
func dropCreatedUser(t *testing.T, pool *pgxpool.Pool, phone string) {
	t.Helper()
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg,
			`DELETE FROM user_profiles WHERE user_id IN (SELECT id FROM users WHERE phone = $1)`, phone)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE phone = $1`, phone)
	})
}

// storedPhone (admin_main_admin_guard_test.go) reads back the column the
// UNIQUE constraint indexes; it is shared rather than re-declared here.

// localForm renders a canonical "964…" number the way a human types it into
// the dashboard: trunk "0", spaces between the groups. This is the SAME number,
// and the whole point of the fix is that the database must agree.
func localForm(canonical string) string {
	national := canonical[len("964"):]
	return "0" + national[:3] + " " + national[3:6] + " " + national[6:]
}

// ─── POST /api/admin/users ──────────────────────────────────────────────

// TestPhoneIdentityCreateUserStoresCanonicalPhone — the number an operator
// types with spaces and a trunk zero must land in the column in the one form
// sign-in looks numbers up by. Stored any other way the account exists, shows
// up in the list, and can never sign in.
func TestPhoneIdentityCreateUserStoresCanonicalPhone(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	canonical := randomTestPhone()
	dropCreatedUser(t, pool, canonical)

	status, body := createUserAs(t, pool, actor.id, map[string]any{
		"phone":     localForm(canonical),
		"full_name": "Canonical Phone",
	})
	if status != http.StatusOK {
		t.Fatalf("POST status = %d, want 200 (body: %v)", status, body)
	}
	idFloat, ok := body["id"].(float64)
	if !ok {
		t.Fatalf("response carries no numeric id: %v", body)
	}
	if got := storedPhone(t, pool, int64(idFloat)); got != canonical {
		t.Fatalf("stored phone = %q, want the canonical %q", got, canonical)
	}
}

// TestPhoneIdentityCreateUserRefusesNumberHeldInAnotherForm — the owner's rule
// itself. The number already belongs to an account, written canonically; the
// operator types the same number the local way. Before the fix this INSERTed a
// second row, because the two strings differ.
func TestPhoneIdentityCreateUserRefusesNumberHeldInAnotherForm(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	existing := insertAccount(t, pool, "user", "")
	dropCreatedUser(t, pool, existing.phone)

	status, body := createUserAs(t, pool, actor.id, map[string]any{
		"phone":     localForm(existing.phone),
		"full_name": "Duplicate Number",
	})
	if status != http.StatusConflict {
		t.Fatalf("POST status = %d, want 409 (body: %v)", status, body)
	}
	if body["code"] != "phone_taken" {
		t.Fatalf("refusal code = %v, want phone_taken (body: %v)", body["code"], body)
	}

	var rows int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM users WHERE phone = $1`, existing.phone).Scan(&rows); err != nil {
		t.Fatalf("count accounts on the number: %v", err)
	}
	if rows != 1 {
		t.Fatalf("%d accounts hold %s, want exactly 1", rows, existing.phone)
	}
}

// TestPhoneIdentityCreateUserRefusesUnreadableNumber — a string that is not a
// number at all used to be stored verbatim, creating an account nobody could
// ever sign into or call.
func TestPhoneIdentityCreateUserRefusesUnreadableNumber(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")

	status, body := createUserAs(t, pool, actor.id, map[string]any{
		"phone":     "12",
		"full_name": "Not A Number",
	})
	if status != http.StatusBadRequest {
		t.Fatalf("POST status = %d, want 400 (body: %v)", status, body)
	}
	if body["code"] != "phone_invalid" {
		t.Fatalf("refusal code = %v, want phone_invalid (body: %v)", body["code"], body)
	}
}

// ─── PATCH /api/admin/users/:id ─────────────────────────────────────────

// TestPhoneIdentityEditUserStoresCanonicalPhone — the edit form's half of the
// same rule.
func TestPhoneIdentityEditUserStoresCanonicalPhone(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	fresh := randomTestPhone()
	dropCreatedUser(t, pool, fresh)

	status, body := patchUserAs(t, pool, actor.id, target.id, map[string]any{
		"phone": localForm(fresh),
	})
	if status != http.StatusOK {
		t.Fatalf("PATCH status = %d, want 200 (body: %v)", status, body)
	}
	if got := storedPhone(t, pool, target.id); got != fresh {
		t.Fatalf("stored phone = %q, want the canonical %q", got, fresh)
	}
}

// TestPhoneIdentityEditUserRefusesNumberHeldInAnotherForm — moving an account
// onto a number another account already holds must be refused, in the
// operator's language. Before the fix the local form slipped past the UNIQUE
// index entirely (two accounts, one number); the canonical form hit it and
// answered HTTP 500 with the raw Postgres text painted on the screen.
func TestPhoneIdentityEditUserRefusesNumberHeldInAnotherForm(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	holder := insertAccount(t, pool, "user", "")

	status, body := patchUserAs(t, pool, actor.id, target.id, map[string]any{
		"phone": localForm(holder.phone),
	})
	if status != http.StatusConflict {
		t.Fatalf("PATCH status = %d, want 409 (body: %v)", status, body)
	}
	if body["code"] != "phone_taken" {
		t.Fatalf("refusal code = %v, want phone_taken (body: %v)", body["code"], body)
	}
	if got := storedPhone(t, pool, target.id); got != target.phone {
		t.Fatalf("target phone = %q after a refused edit, want it untouched (%q)", got, target.phone)
	}
}

// TestPhoneIdentityEditUserRefusesUnreadableNumber — same refusal on the edit
// path, and it must be a coded 400 rather than the old uncoded English line.
func TestPhoneIdentityEditUserRefusesUnreadableNumber(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")

	status, body := patchUserAs(t, pool, actor.id, target.id, map[string]any{
		"phone": "not-a-phone",
	})
	if status != http.StatusBadRequest {
		t.Fatalf("PATCH status = %d, want 400 (body: %v)", status, body)
	}
	if body["code"] != "phone_invalid" {
		t.Fatalf("refusal code = %v, want phone_invalid (body: %v)", body["code"], body)
	}
	if got := storedPhone(t, pool, target.id); got != target.phone {
		t.Fatalf("target phone = %q after a refused edit, want it untouched (%q)", got, target.phone)
	}
}

// ─── The race ───────────────────────────────────────────────────────────

// TestPhoneIdentityConcurrentCreateLeavesOneAccount — two operators (or one
// double-click) creating the same number at the same instant, each typing it a
// different way. The check the handler does before inserting is a read, so two
// requests can both pass it; what makes this safe is that normalisation puts
// both on the SAME key and the UNIQUE index from migration 001 then refuses one
// of them inside the database. No advisory lock is needed, and none is taken —
// the constraint is the serialisation point.
func TestPhoneIdentityConcurrentCreateLeavesOneAccount(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	canonical := randomTestPhone()
	dropCreatedUser(t, pool, canonical)
	router := newUserCreateRouter(pool)

	// Two spellings of ONE number: the canonical form the app writes, and the
	// local form a human types. Identical after normalisation, different before
	// — which is exactly the pair the unfixed code let both through.
	spellings := []string{canonical, localForm(canonical)}
	type result struct {
		status int
		body   string
	}
	done := make(chan result, len(spellings))
	for _, spelling := range spellings {
		go func() {
			status, _, raw := createUserOn(t, router, pool, actor.id, map[string]any{
				"phone":     spelling,
				"full_name": "Race Number",
			})
			done <- result{status, raw}
		}()
	}

	created, refused := 0, 0
	for range spellings {
		select {
		case got := <-done:
			switch got.status {
			case http.StatusOK:
				created++
			case http.StatusConflict:
				refused++
			default:
				t.Fatalf("concurrent create answered %d, want 200 or 409 (body: %s)", got.status, got.body)
			}
		case <-time.After(60 * time.Second):
			t.Fatalf("a concurrent create never returned")
		}
	}
	if created != 1 || refused != 1 {
		t.Fatalf("concurrent creates: %d succeeded and %d were refused, want exactly 1 and 1", created, refused)
	}

	var rows int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM users WHERE phone = $1`, canonical).Scan(&rows); err != nil {
		t.Fatalf("count accounts on the number: %v", err)
	}
	if rows != 1 {
		t.Fatalf("%d accounts hold %s after two simultaneous sign-ups, want exactly 1", rows, canonical)
	}
}
