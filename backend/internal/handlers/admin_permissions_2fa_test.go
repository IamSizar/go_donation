// admin_permissions_2fa_test.go — are BOTH factors on إدارة الصلاحيات real
// (H1)?
//
// # THE HOLE THESE WERE WRITTEN AGAINST
//
// The client asked for "كلمة السر ثم رمز تأكيد مؤقت" — password, then a
// temporary code — on every permission change. The code was enforced. The
// password was not: the dashboard called POST /api/admin/verify-password, got
// {ok:true}, and then sent the write, and the write endpoint never mentioned a
// password. A caller that simply did not make the first call met no password at
// all. That is not a two-factor confirmation, it is a one-factor confirmation
// with a habit.
//
// TestPermissionChangeRequiresPassword is that hole, driven through the real
// request chain with a real single-use OTP: RequireAdmin → RequireSuperAdmin →
// handler. It fails on the parent commit because the write succeeds.
//
// # WHAT ELSE IS PINNED, AND WHY EACH ONE MATTERS
//
//   - A WRONG password is refused, and the change does not happen. Otherwise
//     "requires a password" would mean "requires the field to be present".
//   - An actor with NO password_hash is still allowed through, and is TOLD so
//     in the response. Production holds a super_admin with no password and no
//     username; enforcing the factor on that account would lock the owner out
//     of the one screen that fixes everything else. The allowance is the
//     deliberate choice, and it is only defensible because it is reported.
//   - Every successful change reports whether the SECOND factor was degraded.
//     With no gateway configured the code comes back in the response, which
//     makes it not a second factor; the screen has to be able to say so instead
//     of drawing a padlock.
//   - Email delivery works when SMTP is configured and the actor has an
//     address, and the code that arrives is the one the endpoint accepts —
//     the "phone OR email" half of the client's sentence.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_h1
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h1?sslmode=disable' \
//	  go test ./internal/handlers/ -run PermissionFactor -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newFactorRouter wires POST /api/admin/permissions exactly as main.go does,
// with whichever gateways the test supplies. Returns the OTP store so a test
// can mint the second factor the endpoint will consume.
func newFactorRouter(
	pool *pgxpool.Pool, otpiq *auth.OTPIQClient, mailer *auth.Mailer,
) (*gin.Engine, *AdminPermissionsHandler) {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	h := NewAdminPermissionsHandler(permissions.New(pool), auth.NewOTPStore(pool), otpiq, mailer)
	r := gin.New()
	r.POST("/api/admin/permissions",
		auth.RequireAdmin(tokens), auth.RequireSuperAdmin(), h.SetPermission)
	r.POST("/api/admin/permissions/otp",
		auth.RequireAdmin(tokens), auth.RequireSuperAdmin(), h.RequestOTP)
	return r, h
}

// postFactorAs drives one request as `actorID` and returns status + body.
func postFactorAs(
	t *testing.T, pool *pgxpool.Pool, r *gin.Engine, path string, actorID int64, body map[string]any,
) (int, map[string]any) {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(
		context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal: %v", err)
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

// mintFactor stores a real single-use code for the actor's phone, the same way
// the endpoint's own /otp route does, so the second factor in these tests is
// genuine rather than bypassed.
func mintFactor(t *testing.T, pool *pgxpool.Pool, phone string) string {
	t.Helper()
	const code = "515151"
	if err := auth.NewOTPStore(pool).StoreCode(context.Background(), phone, code, "real"); err != nil {
		t.Fatalf("store OTP: %v", err)
	}
	return code
}

// effective reads the stored answer for a (tier, module, action) straight from
// the store — the status code alone would not prove the write happened.
func effective(t *testing.T, pool *pgxpool.Pool, tier, module, action string) bool {
	t.Helper()
	allowed, err := permissions.New(pool).Allowed(
		context.Background(), permissions.TierFrom(tier), module, action)
	if err != nil {
		t.Fatalf("read effective permission: %v", err)
	}
	return allowed
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestPermissionFactorRequiresPassword is the hole itself: a permission change
// carrying a valid OTP and NO password must not be applied.
func TestPermissionFactorRequiresPassword(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	grantTier(t, pool, "supervisor", "reports", "view", true)

	r, _ := newFactorRouter(pool, nil, nil)
	code := mintFactor(t, pool, actor.phone)

	status, body := postFactorAs(t, pool, r, "/api/admin/permissions", actor.id, map[string]any{
		"tier": "supervisor", "module": "reports", "action": "view",
		"allowed": false, "otp": code, // no password at all
	})

	if status != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401 — a permission change went through with no password (body: %v)",
			status, body)
	}
	if got, _ := body["code"].(string); got != "password_factor_required" {
		t.Errorf("code = %q, want password_factor_required (body: %v)", got, body)
	}
	if !effective(t, pool, "supervisor", "reports", "view") {
		t.Error("the permission was REVOKED by a request that proved only one factor")
	}
}

// TestPermissionFactorRejectsWrongPassword — presence is not proof.
func TestPermissionFactorRejectsWrongPassword(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	grantTier(t, pool, "supervisor", "reports", "export", true)

	r, _ := newFactorRouter(pool, nil, nil)
	code := mintFactor(t, pool, actor.phone)

	status, body := postFactorAs(t, pool, r, "/api/admin/permissions", actor.id, map[string]any{
		"tier": "supervisor", "module": "reports", "action": "export",
		"allowed": false, "otp": code, "password": "not-the-password",
	})

	if status != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401 (body: %v)", status, body)
	}
	if got, _ := body["code"].(string); got != "password_factor_incorrect" {
		t.Errorf("code = %q, want password_factor_incorrect (body: %v)", got, body)
	}
	if !effective(t, pool, "supervisor", "reports", "export") {
		t.Error("a wrong password still revoked the permission")
	}
}

// TestPermissionFactorAcceptsCorrectPassword — the happy path, and the proof
// that the new factor did not simply close the screen.
func TestPermissionFactorAcceptsCorrectPassword(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	grantTier(t, pool, "employee", "tasks", "view", true)

	r, _ := newFactorRouter(pool, nil, nil)
	code := mintFactor(t, pool, actor.phone)

	status, body := postFactorAs(t, pool, r, "/api/admin/permissions", actor.id, map[string]any{
		"tier": "employee", "module": "tasks", "action": "view",
		"allowed": false, "otp": code, "password": "TheOwnersPassword1",
	})

	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %v)", status, body)
	}
	if effective(t, pool, "employee", "tasks", "view") {
		t.Error("the change was accepted but not applied")
	}
	factors, _ := body["factors"].(map[string]any)
	if factors == nil {
		t.Fatalf("no factors block in the response (body: %v)", body)
	}
	if got, _ := factors["password"].(string); got != passwordFactorVerified {
		t.Errorf("factors.password = %q, want %q", got, passwordFactorVerified)
	}
	// No gateway is configured in this router, so the code came back in the
	// response and the screen must be told the second factor was not one.
	if degraded, _ := factors["second_factor_degraded"].(bool); !degraded {
		t.Error("factors.second_factor_degraded = false with no gateway configured — " +
			"the dashboard would show a clean padlock for a code it was handed itself")
	}
}

// TestPermissionFactorPasswordlessAdminIsNotLockedOut is the deliberate
// allowance, and the constraint the whole row was built under: the owner must
// still be able to administer permissions. It is only defensible because the
// response says the factor did not apply — so that is asserted too.
func TestPermissionFactorPasswordlessAdminIsNotLockedOut(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "") // no password_hash — production has one
	grantTier(t, pool, "employee", "tasks", "edit", true)

	r, _ := newFactorRouter(pool, nil, nil)
	code := mintFactor(t, pool, actor.phone)

	status, body := postFactorAs(t, pool, r, "/api/admin/permissions", actor.id, map[string]any{
		"tier": "employee", "module": "tasks", "action": "edit",
		"allowed": false, "otp": code,
	})

	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — a Super-Admin with no password was locked out of "+
			"their own permissions screen (body: %v)", status, body)
	}
	factors, _ := body["factors"].(map[string]any)
	if got, _ := factors["password"].(string); got != passwordFactorUnset {
		t.Errorf("factors.password = %q, want %q — the allowance has to be visible", got, passwordFactorUnset)
	}
}

// TestPermissionFactorDeliversByEmail is the "phone OR email" half. It runs a
// real SMTP conversation against a listener on 127.0.0.1 and then spends the
// code that arrived, so the assertion is that the delivered code is the one the
// endpoint accepts — not merely that a send was attempted.
func TestPermissionFactorDeliversByEmail(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	setEmail(t, pool, actor.id, "owner@example.org")
	grantTier(t, pool, "supervisor", "donations", "view", true)

	stub := newFakeSMTP(t)
	mailer := auth.NewMailer(auth.MailerConfig{
		Host: "127.0.0.1", Port: stub.port(), From: "no-reply@test.local",
	})
	r, _ := newFactorRouter(pool, nil, mailer) // email real, SMS not

	status, body := postFactorAs(t, pool, r, "/api/admin/permissions/otp", actor.id,
		map[string]any{"channel": "email"})
	if status != http.StatusOK {
		t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
	}
	if got, _ := body["channel"].(string); got != "email" {
		t.Errorf("channel = %q, want email (body: %v)", got, body)
	}
	if degraded, _ := body["degraded"].(bool); degraded {
		t.Error("degraded = true with SMTP configured — a real channel was reported as a fallback")
	}
	if _, leaked := body["demo_code"]; leaked {
		t.Error("the response carried the code even though it was emailed out of band")
	}

	delivered := stub.decodedBodies()
	if len(delivered) != 1 {
		t.Fatalf("emails delivered = %d, want 1", len(delivered))
	}
	emailed := codeFrom(t, delivered[0])

	status, body = postFactorAs(t, pool, r, "/api/admin/permissions", actor.id, map[string]any{
		"tier": "supervisor", "module": "donations", "action": "view",
		"allowed": false, "otp": emailed, "password": "TheOwnersPassword1",
	})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — the emailed code was not accepted (body: %v)", status, body)
	}
	if effective(t, pool, "supervisor", "donations", "view") {
		t.Error("the change was accepted but not applied")
	}
	factors, _ := body["factors"].(map[string]any)
	if degraded, _ := factors["second_factor_degraded"].(bool); degraded {
		t.Error("second_factor_degraded = true while a real email channel is configured")
	}
}
