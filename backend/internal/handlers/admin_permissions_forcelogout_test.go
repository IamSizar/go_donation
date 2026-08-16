// admin_permissions_forcelogout_test.go — does taking a permission away end the
// sessions that still hold it (H11)?
//
// # WHY THIS FILE EXISTS
//
// The client asked for one rule: "force logout the instant permissions are
// reduced". Four of the five paths that reduce someone's authority already do
// it — a tier demotion, a suspend, a ban and an archive all call forceLogout,
// and auth/token.go refuses a revoked token on the very next request.
//
// The fifth did not. Unticking a checkbox in الصلاحيات wrote the override,
// logged it to the immutable audit trail, and left every affected session
// running. The staff member kept their loaded dashboard, kept the modules the
// SPA had already decided to render, and only discovered the change the next
// time a click hit a gated route and came back "لا تملك صلاحية".
//
// That is not merely cosmetic. The reason the other four force a logout is that
// a session carries decisions made when it was minted; the same is true here,
// and it is the path a Super Admin would actually use to react to a problem
// with a specific employee.
//
// WHAT THESE TESTS PIN, and equally what they pin OUT:
//
//   - Reducing a tier-wide permission ends the sessions of staff on that tier.
//   - Reducing ONE employee's own override ends only that employee's sessions.
//   - GRANTING a permission ends nothing. A logout is the cost of taking
//     authority away; charging it for handing authority out would train
//     operators to avoid the screen.
//   - A change to the `user` tier row ends nothing, because that tier cannot
//     reach the dashboard at all (permissions.CanAccessDashboard) and the
//     matrix governs nothing else. Without this the feature would log out every
//     app user on the platform for a change that does not affect them — a far
//     worse bug than the one being fixed.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_h11
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h11?sslmode=disable' \
//	  go test ./internal/handlers/ -run PermissionReduction -v
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

// liveSessionCount reports how many usable access tokens a user still holds.
// "Usable" is the same condition auth/token.go applies on every request, so
// this asks the question the way production answers it rather than counting
// rows the auth layer would have ignored anyway.
func liveSessionCount(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM api_access_tokens
		  WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW()`,
		userID).Scan(&n); err != nil {
		t.Fatalf("count live sessions for user %d: %v", userID, err)
	}
	return n
}

// openSession mints a real access token the same way the dashboard sign-in
// does, so what the test revokes is a genuine session and not a fixture row.
func openSession(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	if _, err := auth.NewTokenStore(pool).IssueToken(
		context.Background(), userID, "test-agent", "127.0.0.1"); err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
}

// newPermissionsRouter wires both permission-writing routes exactly as main.go
// does — RequireAdmin, then RequireSuperAdmin, then the handler — so the
// assertion is about the deployed request chain rather than one helper.
func newPermissionsRouter(pool *pgxpool.Pool) (*gin.Engine, *auth.OTPStore) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	tokenStore := auth.NewTokenStore(pool)
	otpStore := auth.NewOTPStore(pool)
	// nil OTPIQ and nil mailer — the production shape, so these tests exercise
	// the degraded-delivery path H1 deliberately keeps open.
	h := NewAdminPermissionsHandler(permissions.New(pool), otpStore, nil, nil)
	r.POST("/api/admin/permissions",
		auth.RequireAdmin(tokenStore), auth.RequireSuperAdmin(), h.SetPermission)
	r.POST("/api/admin/permissions/user/:id",
		auth.RequireAdmin(tokenStore), auth.RequireSuperAdmin(), h.SetUserPermission)
	return r, otpStore
}

// postPermissionAs drives a permission write as `actor`, minting the OTP second
// factor the handler consumes. The OTP is real (stored through the same store
// the endpoint verifies against) — nothing about the 2FA path is stubbed out.
func postPermissionAs(
	t *testing.T, pool *pgxpool.Pool, actorID int64, actorPhone, path string, body map[string]any,
) (int, map[string]any) {
	t.Helper()
	r, otps := newPermissionsRouter(pool)

	// Each permission change consumes a single-use code, so store a fresh one.
	// Stored with mode "real" rather than "demo": VerifyAndConsume rejects a
	// demo-mode record whenever OTP_DEMO_ENABLED is off, and this test must not
	// depend on that environment switch either way.
	const code = "424242"
	if err := otps.StoreCode(context.Background(), actorPhone, code, "real"); err != nil {
		t.Fatalf("store OTP for %s: %v", actorPhone, err)
	}
	body["otp"] = code

	session, err := auth.NewTokenStore(pool).IssueToken(
		context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for actor %d: %v", actorID, err)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

// grantTier writes a starting state directly, so a test can reduce FROM a known
// granted value without spending a request (and an OTP) setting it up.
func grantTier(t *testing.T, pool *pgxpool.Pool, tier, module, action string, allowed bool) {
	t.Helper()
	if err := permissions.New(pool).SetOverride(
		context.Background(), tier, module, action, allowed); err != nil {
		t.Fatalf("seed override %s/%s/%s: %v", tier, module, action, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM role_permissions
			  WHERE tier = $1 AND module = $2 AND action = $3 AND user_id IS NULL`,
			tier, module, action)
	})
}

// ─── The blocker found on the way in ────────────────────────────────────

// TestTierOverrideActuallyPersists pins a defect found while building the tests
// above, and it is worse than the row that led to it: the tier matrix could not
// be saved AT ALL.
//
// permissions.SetOverride was written against migration 015's plain
// UNIQUE (tier, module, action). Migration 055 dropped that constraint and
// replaced it with two PARTIAL unique indexes, and Postgres will only use a
// partial index as an ON CONFLICT arbiter if the conflict target repeats the
// index predicate. The statement did not, so every tier-wide write answered
//
//	ERROR: there is no unique or exclusion constraint matching the
//	ON CONFLICT specification (SQLSTATE 42P10)
//
// and the handler turned that into a 500 "Database error". SetUserOverride was
// written alongside 055 and already carried `WHERE user_id IS NOT NULL`, which
// is why the per-employee half kept working and the failure went unnoticed.
//
// The assertion is deliberately end-to-end through the store rather than a
// string check on the SQL: what matters is that the value is readable
// afterwards, and that writing it twice updates rather than duplicating.
func TestTierOverrideActuallyPersists(t *testing.T) {
	pool := newAuthTestPool(t)
	store := permissions.New(pool)
	ctx := context.Background()
	const tier, module, action = "supervisor", "reports", "export"

	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM role_permissions
			  WHERE tier = $1 AND module = $2 AND action = $3 AND user_id IS NULL`,
			tier, module, action)
	})

	if err := store.SetOverride(ctx, tier, module, action, false); err != nil {
		t.Fatalf("first write: %v", err)
	}
	if allowed, err := store.Allowed(ctx, permissions.TierFrom(tier), module, action); err != nil || allowed {
		t.Fatalf("after writing false: allowed = %v, err = %v — the override did not stick", allowed, err)
	}

	// The upsert half: writing again must UPDATE the existing row, not insert a
	// second one that the partial unique index would then have to reject.
	if err := store.SetOverride(ctx, tier, module, action, true); err != nil {
		t.Fatalf("second write (the upsert path): %v", err)
	}
	if allowed, err := store.Allowed(ctx, permissions.TierFrom(tier), module, action); err != nil || !allowed {
		t.Fatalf("after writing true: allowed = %v, err = %v", allowed, err)
	}

	var rows int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM role_permissions
		  WHERE tier = $1 AND module = $2 AND action = $3 AND user_id IS NULL`,
		tier, module, action).Scan(&rows); err != nil {
		t.Fatalf("count override rows: %v", err)
	}
	if rows != 1 {
		t.Errorf("override rows = %d, want 1 — the upsert inserted instead of updating", rows)
	}
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestPermissionReductionForcesLogout is the client's rule, one case per path.
func TestPermissionReductionForcesLogout(t *testing.T) {
	pool := newAuthTestPool(t)

	// The acting Super Admin needs a phone: the OTP second factor is delivered
	// to it, and the handler refuses an actor without one.
	actor := insertAccount(t, pool, "super_admin", "")

	t.Run("tier-wide reduction ends that tier's sessions", func(t *testing.T) {
		staff := insertAccount(t, pool, "supervisor", "")
		grantTier(t, pool, "supervisor", "donations", "export", true)
		openSession(t, pool, staff.id)
		if got := liveSessionCount(t, pool, staff.id); got != 1 {
			t.Fatalf("precondition: live sessions = %d, want 1", got)
		}

		status, body := postPermissionAs(t, pool, actor.id, actor.phone,
			"/api/admin/permissions", map[string]any{
				"tier": "supervisor", "module": "donations", "action": "export", "allowed": false,
			})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := liveSessionCount(t, pool, staff.id); got != 0 {
			t.Errorf("supervisor still holds %d live session(s) after losing donations/export — "+
				"the permission was reduced and the session survived it", got)
		}
	})

	t.Run("granting a permission ends nothing", func(t *testing.T) {
		staff := insertAccount(t, pool, "employee", "")
		grantTier(t, pool, "employee", "reports", "view", false)
		openSession(t, pool, staff.id)

		status, body := postPermissionAs(t, pool, actor.id, actor.phone,
			"/api/admin/permissions", map[string]any{
				"tier": "employee", "module": "reports", "action": "view", "allowed": true,
			})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := liveSessionCount(t, pool, staff.id); got != 1 {
			t.Errorf("live sessions = %d, want 1 — being GRANTED a permission "+
				"must not sign anyone out", got)
		}
	})

	t.Run("a user-tier change never touches app users", func(t *testing.T) {
		appUser := insertAccount(t, pool, "user", "")
		grantTier(t, pool, "user", "campaigns", "view", true)
		openSession(t, pool, appUser.id)

		status, body := postPermissionAs(t, pool, actor.id, actor.phone,
			"/api/admin/permissions", map[string]any{
				"tier": "user", "module": "campaigns", "action": "view", "allowed": false,
			})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := liveSessionCount(t, pool, appUser.id); got != 1 {
			t.Errorf("live sessions = %d, want 1 — the `user` tier cannot reach the "+
				"dashboard, so its matrix row governs nothing and a change to it must "+
				"not mass-log-out the app", got)
		}
	})

	t.Run("a per-employee reduction ends only that employee", func(t *testing.T) {
		target := insertAccount(t, pool, "employee", "")
		bystander := insertAccount(t, pool, "employee", "")
		openSession(t, pool, target.id)
		openSession(t, pool, bystander.id)

		// `employee` holds view by default, so setting the per-user override to
		// false is a genuine reduction for this one account.
		allowed := false
		status, body := postPermissionAs(t, pool, actor.id, actor.phone,
			"/api/admin/permissions/user/"+strconv.FormatInt(target.id, 10),
			map[string]any{"module": "donations", "action": "view", "allowed": &allowed})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got := liveSessionCount(t, pool, target.id); got != 0 {
			t.Errorf("target still holds %d live session(s) after its own override "+
				"was reduced", got)
		}
		if got := liveSessionCount(t, pool, bystander.id); got != 1 {
			t.Errorf("bystander live sessions = %d, want 1 — a per-employee change "+
				"must not sign out the rest of the tier", got)
		}
	})
}
