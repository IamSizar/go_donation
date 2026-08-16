// admin_user_edit_guard_test.go — who may rewrite another account's sign-in
// number (H13).
//
// # WHY THIS FILE EXISTS
//
// Every other write path on the users resource asks "is the target protected?"
// before touching the row: role, active, password, force-logout, account status
// and archive all call blockIfProtectedTarget (admin_status.go), and delete is
// pinned to RequireSuperAdmin. PATCH /api/admin/users/:id — the one route that
// can rewrite `users.phone` — asked nothing. Its only gate was the
// (users, edit) permission, which supervisor and employee hold by DEFAULT
// (permissions.defaultAllowed), so every staff tier could reach it.
//
// That was survivable while a phone was just a contact field. It is not one any
// more: the number is where a sign-in code is delivered, so holding it clears at
// least one factor of someone else's login. Exactly how much that buys an
// attacker depends on the auth design, which is being revised — these tests do
// not rest on it. They rest on what production says today: of the five staff
// accounts, ONE super_admin and ONE admin have no password at all, so for those
// two the phone number is currently sufficient on its own, and 34 of the 41
// ordinary users are in the same position. No role_permissions override narrows
// users.edit for anyone.
//
// These tests pin both halves of the fix:
//   - a tier floor: you cannot edit an account that outranks you, at all;
//   - a credential rule: rewriting the phone of ANY account that holds
//     dashboard access is Super-Admin-only, because that is handing out a new
//     identity rather than correcting a contact detail.
//
// and, just as important, that the everyday edits staff actually do — fixing a
// beneficiary's mistyped number, correcting a name — still go through.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_h13
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h13?sslmode=disable' \
//	  go test ./internal/handlers/ -run UserEditGuard -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newUserEditRouter wires the REAL route exactly as main.go does — the staff
// gate, then the (users, edit) permission, then the handler — so the assertion
// is "what does the deployed request chain do", not "what does one helper
// return". Nothing is stubbed; permissions come from the same store production
// reads, over the real migrated schema.
func newUserEditRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	tokenStore := auth.NewTokenStore(pool)
	permStore := permissions.New(pool)
	r.PATCH("/api/admin/users/:id",
		auth.RequireAdmin(tokenStore),
		auth.RequirePermission(permStore, "users", "edit"),
		NewAdminEditHandler(pool).User,
	)
	return r
}

// patchUserAs issues a real access token for actorID — the same token the
// dashboard sign-in mints — and replays a PATCH against the target's row.
// Returns the status code and the decoded body so a test can assert on the
// translatable `code` as well as the outcome.
func patchUserAs(t *testing.T, pool *pgxpool.Pool, actorID, targetID int64, body map[string]any) (int, map[string]any) {
	t.Helper()
	store := auth.NewTokenStore(pool)
	session, err := store.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPatch,
		"/api/admin/users/"+strconv.FormatInt(targetID, 10), bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	newUserEditRouter(pool).ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

// postUserStatusAs drives one of the SIBLING write routes — the ones that
// always had a rank check — so the tests cover the guard everywhere it is now
// shared, not just on the route that was missing it.
func postUserStatusAs(t *testing.T, pool *pgxpool.Pool, actorID, targetID int64, action string, body map[string]any) (int, map[string]any) {
	t.Helper()
	tokenStore := auth.NewTokenStore(pool)
	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", actorID, err)
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/api/admin/users/:id/:action",
		auth.RequireAdmin(tokenStore),
		auth.RequirePermission(permissions.New(pool), "users", "edit"),
		NewAdminStatusHandler(pool, nil, nil, nil).UserPassword,
	)

	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost,
		"/api/admin/users/"+strconv.FormatInt(targetID, 10)+"/"+action, bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

// phoneOf reads the target's CURRENT phone straight from the database. The
// status code alone is not proof: a refusal that still wrote the row would be
// the same bug wearing a 403.
func phoneOf(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	var phone *string
	if err := pool.QueryRow(context.Background(),
		`SELECT phone FROM users WHERE id = $1`, userID).Scan(&phone); err != nil {
		t.Fatalf("read phone of user %d: %v", userID, err)
	}
	if phone == nil {
		return ""
	}
	return *phone
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestUserEditGuardRefusesTakeover is the H13 regression test. Each case holds
// (users, edit) — that is the whole point: the permission is not the control
// here, the target's rank is.
func TestUserEditGuardRefusesTakeover(t *testing.T) {
	pool := newAuthTestPool(t)

	// A phone the attacker controls. Canonical form, so a successful write
	// really would be a usable sign-in number rather than something the phone
	// parser would later reject.
	const attackerPhone = "9647700000001"

	cases := []struct {
		name       string
		actorTier  string
		targetTier string
		wantStatus int
		wantCode   string
	}{
		{
			// THE HOLE. An `admin` — the rank the client calls ادمن — rewriting
			// the Primary Administrator's sign-in number. Before the fix this
			// returned 200 and the row was updated.
			name:       "admin cannot change a super_admin's phone",
			actorTier:  "admin",
			targetTier: "super_admin",
			wantStatus: http.StatusForbidden,
			wantCode:   "protected_account",
		},
		{
			// The widest version of the same hole: `employee` holds users.edit
			// by default too, with no override anywhere in production.
			name:       "employee cannot change a super_admin's phone",
			actorTier:  "employee",
			targetTier: "super_admin",
			wantStatus: http.StatusForbidden,
			wantCode:   "protected_account",
		},
		{
			name:       "supervisor cannot change an admin's phone",
			actorTier:  "supervisor",
			targetTier: "admin",
			wantStatus: http.StatusForbidden,
			wantCode:   "protected_account",
		},
		{
			// The tier floor allows a peer edit, so the credential rule is what
			// has to stop this one: an admin re-pointing a FELLOW admin's
			// sign-in number is still an account takeover, just a sideways one.
			name:       "admin cannot change a fellow admin's phone",
			actorTier:  "admin",
			targetTier: "admin",
			wantStatus: http.StatusForbidden,
			wantCode:   "staff_phone_super_admin_only",
		},
		{
			name:       "employee cannot change a fellow employee's phone",
			actorTier:  "employee",
			targetTier: "employee",
			wantStatus: http.StatusForbidden,
			wantCode:   "staff_phone_super_admin_only",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			actor := insertAccount(t, pool, tc.actorTier, "")
			target := insertAccount(t, pool, tc.targetTier, "")
			before := phoneOf(t, pool, target.id)

			status, body := patchUserAs(t, pool, actor.id, target.id,
				map[string]any{"phone": attackerPhone})

			if status != tc.wantStatus {
				t.Errorf("status = %d, want %d (body: %v)", status, tc.wantStatus, body)
			}
			if got, _ := body["code"].(string); got != tc.wantCode {
				t.Errorf("code = %q, want %q", got, tc.wantCode)
			}
			// The row itself is the real assertion.
			if after := phoneOf(t, pool, target.id); after != before {
				t.Errorf("phone was rewritten: %q → %q — the account is takeable", before, after)
			}
		})
	}

	// The rank rule is shared, so it has to hold on the SIBLING routes too —
	// they carried the old super_admin-only version, which let a supervisor
	// reset an ADMIN's password and sign in as them by a different door.
	t.Run("supervisor cannot reset an admin's password", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "admin", "")

		status, body := postUserStatusAs(t, pool, actor.id, target.id, "password",
			map[string]any{"password": "hunter2"})

		if status != http.StatusForbidden {
			t.Errorf("status = %d, want 403 (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "protected_account" {
			t.Errorf("code = %q, want %q", got, "protected_account")
		}
		var hash *string
		if err := pool.QueryRow(context.Background(),
			`SELECT password_hash FROM users WHERE id = $1`, target.id).Scan(&hash); err != nil {
			t.Fatalf("read password_hash: %v", err)
		}
		if hash != nil {
			t.Error("a password was written onto an account that outranks the actor")
		}
	})
}

// TestUserEditGuardAllowsLegitimateEdits is the other half of the fix: the
// guard must not turn "correct a beneficiary's mistyped number" into a
// Super-Admin errand. Every case here is an edit staff perform routinely.
func TestUserEditGuardAllowsLegitimateEdits(t *testing.T) {
	pool := newAuthTestPool(t)

	t.Run("employee can fix an ordinary user's phone", func(t *testing.T) {
		actor := insertAccount(t, pool, "employee", "")
		target := insertAccount(t, pool, "user", "")
		const corrected = "9647700000002"

		status, body := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"phone": corrected})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := phoneOf(t, pool, target.id); got != corrected {
			t.Errorf("phone = %q, want %q — the legitimate edit did not land", got, corrected)
		}
	})

	t.Run("employee can edit an ordinary user's profile fields", func(t *testing.T) {
		actor := insertAccount(t, pool, "employee", "")
		target := insertAccount(t, pool, "user", "")

		status, body := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"full_name": "Ali Hassan", "city": "Erbil"})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		var name string
		if err := pool.QueryRow(context.Background(),
			`SELECT full_name FROM user_profiles WHERE user_id = $1`, target.id).Scan(&name); err != nil {
			t.Fatalf("read profile: %v", err)
		}
		if name != "Ali Hassan" {
			t.Errorf("full_name = %q, want %q", name, "Ali Hassan")
		}
	})

	// H20 SUPERSEDED THE OLD ASSERTION HERE, deliberately.
	//
	// This case used to read "a super_admin can still change a super_admin's
	// phone" and expect a 200: under H13 alone, rank was the whole question and
	// a peer edit was legitimate. H20 answers a second question the client
	// asked — does the OWNER of that account know it is happening? — so the
	// same request now needs a code delivered to the target's own phone AND
	// email before anything is written.
	//
	// What the original case was protecting is preserved and asserted below:
	// the Super-Admin is not locked out of their own tool. They are told what
	// is missing, in a message that names it, and the row is left alone rather
	// than half-changed. The two-request happy path is covered end to end in
	// admin_main_admin_guard_test.go with both channels live.
	t.Run("a super_admin's phone now needs the two-channel confirmation", func(t *testing.T) {
		actor := insertAccount(t, pool, "super_admin", "")
		target := insertAccount(t, pool, "super_admin", "")
		before := phoneOf(t, pool, target.id)
		const corrected = "9647700000003"

		status, body := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"phone": corrected})

		if status == http.StatusOK {
			t.Fatalf("status = 200 — a main-admin sign-in number was rewritten with no confirmation (body: %v)", body)
		}
		code, _ := body["code"].(string)
		if !strings.HasPrefix(code, "main_admin_") {
			t.Errorf("code = %q, want a main_admin_* refusal naming what is missing (body: %v)", code, body)
		}
		if got := phoneOf(t, pool, target.id); got != before {
			t.Errorf("phone = %q, want it unchanged at %q — the refusal left a half-applied edit", got, before)
		}
	})

	t.Run("employee can still set an ordinary user's password", func(t *testing.T) {
		// The sibling status route, proving the shared guard did not turn the
		// everyday case into a refusal when it started refusing the rank case.
		actor := insertAccount(t, pool, "employee", "")
		target := insertAccount(t, pool, "user", "")

		status, body := postUserStatusAs(t, pool, actor.id, target.id, "password",
			map[string]any{"password": "hunter2"})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
	})

	t.Run("an admin can still edit a fellow admin's non-credential fields", func(t *testing.T) {
		// The credential rule is scoped to the phone. Blocking a peer's NAME
		// would be a new bug, not a fix.
		actor := insertAccount(t, pool, "admin", "")
		target := insertAccount(t, pool, "admin", "")

		status, body := patchUserAs(t, pool, actor.id, target.id,
			map[string]any{"full_name": "Sara Ahmed"})

		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
	})
}
