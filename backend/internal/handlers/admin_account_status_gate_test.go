// admin_account_status_gate_test.go — who may enable and disable an account
// (H8).
//
// # WHY THIS FILE EXISTS
//
// The client asked to "control activating/deactivating accounts, products and
// stores" from the permissions matrix. Products, stores, partners and media all
// obey it already — each status route sits on perm(module, "edit"). Accounts did
// not: POST /admin/users/:id/account_status was hard-pinned to
// RequireSuperAdmin(), so no checkbox anywhere could grant it and the answer to
// "let a supervisor suspend a spammer" was "only you can do that".
//
// The inconsistency was internal, not just against the client's note. The route
// immediately below it —
//
//	POST /admin/users/:id/archive   perm("users", "archive")
//
// takes an account out of circulation too, calls the SAME guard, and has been
// matrix-controlled all along. Suspending and archiving are the same kind of act
// on the same resource; only one of them was delegable.
//
// So account_status now sits on perm("users", "archive") — its own sibling's
// gate, deliberately, rather than a new module or a new action. Nothing new is
// granted by default: whoever could already archive an account can now suspend
// one, and a Super-Admin can untick that box for any rank.
//
// WHAT MUST NOT CHANGE, and is the reason this file exists at all: the
// permission says WHETHER you may disable accounts, never WHOSE. guardUserWrite's
// tier floor still refuses any write aimed at an account ranked at or above the
// actor, so a supervisor holding users/archive still cannot suspend an admin or
// a Super-Admin. Swapping a gate is exactly the change that could quietly drop
// that, so it is asserted here.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_h8
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h8?sslmode=disable' \
//	  go test ./internal/handlers/ -run AccountStatusGate -v
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
)

// ─── Harness ────────────────────────────────────────────────────────────

// postAccountStatusAs drives the REAL route as main.go wires it — the staff
// gate, then the permission, then the handler — so what is asserted is the
// deployed request chain rather than one helper's return value.
func postAccountStatusAs(
	t *testing.T, pool *pgxpool.Pool, actorID, targetID int64, status string,
) (int, map[string]any) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	tokenStore := auth.NewTokenStore(pool)
	r := gin.New()
	r.POST("/api/admin/users/:id/account_status",
		auth.RequireAdmin(tokenStore),
		auth.RequirePermission(permissions.New(pool), "users", "archive"),
		NewAdminStatusHandler(pool, nil, nil, nil).UserAccountStatus,
	)

	session, err := tokenStore.IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for actor %d: %v", actorID, err)
	}
	raw, _ := json.Marshal(map[string]any{"status": status})
	req := httptest.NewRequest(http.MethodPost,
		"/api/admin/users/"+strconv.FormatInt(targetID, 10)+"/account_status", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

// accountStatusOf reads the target's CURRENT lifecycle status from the database,
// because a 200 that wrote nothing would pass an assertion on the status code
// alone.
func accountStatusOf(t *testing.T, pool *pgxpool.Pool, id int64) string {
	t.Helper()
	var s string
	if err := pool.QueryRow(context.Background(),
		"SELECT account_status FROM users WHERE id = $1", id).Scan(&s); err != nil {
		t.Fatalf("read account_status for %d: %v", id, err)
	}
	return s
}

// setTierPermission writes one matrix cell directly, so a test can arrange the
// checkbox state without spending a request (and an OTP) on it.
func setTierPermission(t *testing.T, pool *pgxpool.Pool, tier, module, action string, allowed bool) {
	t.Helper()
	if err := permissions.New(pool).SetOverride(
		context.Background(), tier, module, action, allowed); err != nil {
		t.Fatalf("set %s/%s/%s = %v: %v", tier, module, action, allowed, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM role_permissions
			  WHERE tier = $1 AND module = $2 AND action = $3 AND user_id IS NULL`,
			tier, module, action)
	})
}

// ─── The boundary ───────────────────────────────────────────────────────

func TestAccountStatusGateIsDelegable(t *testing.T) {
	pool := newAuthTestPool(t)

	t.Run("a supervisor holding users/archive can suspend an ordinary account", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")
		setTierPermission(t, pool, "supervisor", "users", "archive", true)

		status, body := postAccountStatusAs(t, pool, actor.id, target.id, "suspended")
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 — the client asked for this to be delegable "+
				"(body: %v)", status, body)
		}
		if got := accountStatusOf(t, pool, target.id); got != "suspended" {
			t.Errorf("account_status = %q, want %q — the request was accepted but wrote nothing", got, "suspended")
		}
	})

	t.Run("unticking the box takes it away again", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "user", "")
		setTierPermission(t, pool, "supervisor", "users", "archive", false)

		status, _ := postAccountStatusAs(t, pool, actor.id, target.id, "banned")
		if status != http.StatusForbidden {
			t.Errorf("status = %d, want 403 — a permission that cannot be revoked is not a permission", status)
		}
		if got := accountStatusOf(t, pool, target.id); got != "active" {
			t.Errorf("account_status = %q, want %q — the write happened despite the refusal", got, "active")
		}
	})

	t.Run("the tier floor still holds: a supervisor cannot suspend an admin", func(t *testing.T) {
		actor := insertAccount(t, pool, "supervisor", "")
		target := insertAccount(t, pool, "admin", "")
		setTierPermission(t, pool, "supervisor", "users", "archive", true)

		status, body := postAccountStatusAs(t, pool, actor.id, target.id, "banned")
		if status != http.StatusForbidden {
			t.Fatalf("status = %d, want 403 — the permission says WHETHER you may disable "+
				"accounts, never WHOSE (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "protected_account" {
			t.Errorf("code = %q, want %q", got, "protected_account")
		}
		if got := accountStatusOf(t, pool, target.id); got != "active" {
			t.Errorf("an admin account was disabled by a supervisor: account_status = %q", got)
		}
	})

	t.Run("an employee still cannot, by default", func(t *testing.T) {
		actor := insertAccount(t, pool, "employee", "")
		target := insertAccount(t, pool, "user", "")
		// No override written on purpose: this asserts the DEFAULT, which is the
		// thing a gate swap is most likely to widen by accident.

		status, _ := postAccountStatusAs(t, pool, actor.id, target.id, "suspended")
		if status != http.StatusForbidden {
			t.Errorf("status = %d, want 403 — `employee` holds view+edit by default and "+
				"must not gain account suspension from this change", status)
		}
	})

	t.Run("a super-admin is unaffected", func(t *testing.T) {
		actor := insertAccount(t, pool, "super_admin", "")
		target := insertAccount(t, pool, "user", "")

		status, body := postAccountStatusAs(t, pool, actor.id, target.id, "suspended")
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := accountStatusOf(t, pool, target.id); got != "suspended" {
			t.Errorf("account_status = %q, want %q", got, "suspended")
		}
	})
}
