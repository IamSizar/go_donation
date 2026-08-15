// auth_verified_factor_test.go — no token without a verified factor (A16).
//
// # WHY THIS FILE EXISTS
//
// POST /api/auth/login used to mint a 30-day access token for ANY phone number
// whose `users` row had no `password_hash`, and to CREATE the row first when the
// number was unknown. Knowing a phone number was the whole of authentication.
// No OTP was enforced anywhere: /auth/otp/request and /auth/otp/verify are
// separate public endpoints that the app merely chose to call.
//
// Production holds 36 accounts (of 46) with a phone and no password — among them
// user 34, a `super_admin`, and user 1, an `admin`. Because the app and the
// dashboard SHARE ONE TOKEN STORE with nothing marking which minted a token
// (A15), the token handed out here is a dashboard token. A phone number was
// therefore enough to reach /api/admin/*.
//
// The second half of the hole is delivery mode. `OTP_DEMO_ENABLED` is ON in
// production while `OTPIQ_API_KEY` is unset, so demo is the only OTP mode that
// works there — and demo mode returns the code to the caller in the response
// body. These tests therefore run with demo mode ON, exactly as production has
// it, and pin that a demo code cannot sign a STAFF account in while ordinary
// users keep signing in with it (which is how the live app works today).
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_a16
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_a16?sslmode=disable' \
//	  go test ./internal/handlers/ -run VerifiedFactor -v
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newAuthTestPool connects to the throwaway database named by TEST_DATABASE_URL
// and brings its schema up to date with the real migrations. Skips when the
// variable is unset so a bare checkout still gets a green `go test ./...`.
func newAuthTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping verified-factor integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	// Start every run from an empty per-IP OTP budget (see callerIP), so a
	// previous run's counters can never decide this one's results.
	if _, err := pool.Exec(ctx,
		`DELETE FROM otp_ip_rate_limit WHERE ip_address LIKE '198.51.100.%'`); err != nil {
		pool.Close()
		t.Fatalf("reset otp ip rate limits: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// authTestAccount is one throwaway user row plus the phone it answers to.
type authTestAccount struct {
	id    int64
	phone string
}

// randomTestPhone returns a number already in auth.NormalizePhone's canonical
// form: the Iraq dial code followed by a 10-digit national number. Generating
// it pre-normalised keeps the tests exercising the handlers rather than the
// phone parser, which has its own tests in internal/auth/phone_test.go.
func randomTestPhone() string {
	return fmt.Sprintf("9647%09d", rand.Intn(1000000000))
}

// insertAccount creates a user in the shape under test. password == "" means no
// password_hash at all, which is the production shape that carried the hole.
func insertAccount(t *testing.T, pool *pgxpool.Pool, staffTier, password string) authTestAccount {
	t.Helper()
	ctx := context.Background()
	// Phone is UNIQUE; randomise so repeat runs don't collide. The value is
	// already in auth.NormalizePhone's canonical form (Iraq dial code + a
	// 10-digit national number), which is what the OTP endpoints require.
	phone := randomTestPhone()
	var hash *string
	if password != "" {
		b, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
		if err != nil {
			t.Fatalf("hash password: %v", err)
		}
		s := string(b)
		hash = &s
	}
	var id int64
	err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, is_admin, staff_tier,
		                    registration_status, account_status, password_hash)
		 VALUES ($1, 1, 1, 0, $2, 'approved', 'active', $3)
		 RETURNING id`, phone, staffTier, hash).Scan(&id)
	if err != nil {
		t.Fatalf("insert user (staff_tier=%s): %v", staffTier, err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM api_access_tokens WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM otp_codes WHERE phone = $1`, phone)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return authTestAccount{id: id, phone: phone}
}

// newAuthRouter wires the real auth routes onto the real handler. OTPIQ is nil
// and LoginLocks is live — exactly how main.go builds this in production, where
// OTPIQ_API_KEY is unset.
func newAuthRouter(t *testing.T, pool *pgxpool.Pool) *gin.Engine {
	t.Helper()
	return newAuthRouterWith(t, pool, nil) // OTPIQ unconfigured, as in production
}

// newAuthRouterWith is newAuthRouter with an explicit OTPIQ client, so a test
// can exercise the configured-gateway half of the switch.
func newAuthRouterWith(t *testing.T, pool *pgxpool.Pool, otpiq *auth.OTPIQClient) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	h := NewAuthHandler(
		auth.NewTokenStore(pool),
		auth.NewOTPStore(pool),
		users.NewStore(pool),
		otpiq,
		auth.NewLoginLockStore(pool),
		nil, // notifier — not exercised here
	)
	r := gin.New()
	r.POST("/api/auth/login", h.Login)
	r.POST("/api/auth/otp/request", h.OTPRequest)
	r.POST("/api/auth/otp/verify", h.OTPVerify)
	return r
}

// callerIP hands every request its own client address. /auth/otp/request rate
// limits per IP (10/hour, persisted in otp_ip_rate_limit), and httptest gives
// every request the same RemoteAddr — so without this the tests would throttle
// each other, and the leftover row would throttle the NEXT run too. Sharing a
// bucket is exactly the kind of order-dependence that makes a suite lie.
// 198.51.100.0/24 is TEST-NET-2, reserved for documentation and tests.
var callerIP atomic.Int64

// postJSON posts body to path and returns the status and decoded response.
func postJSON(t *testing.T, r *gin.Engine, path string, body map[string]any) (int, map[string]any) {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(string(raw)))
	req.Header.Set("Content-Type", "application/json")
	req.RemoteAddr = fmt.Sprintf("198.51.100.%d:54321", callerIP.Add(1)%250+1)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

// tokenCount reports how many access tokens exist for a user. The assertion
// that matters is not just "the response had no token" but "no token was
// minted", so a future refactor cannot leak one out of band.
func tokenCount(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM api_access_tokens WHERE user_id = $1`, userID).Scan(&n); err != nil {
		t.Fatalf("count tokens: %v", err)
	}
	return n
}

// hasToken reports whether a login response actually handed back a usable token.
func hasToken(body map[string]any) bool {
	tok, _ := body["access_token"].(string)
	return strings.TrimSpace(tok) != ""
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestVerifiedFactorRequiredForPhoneLogin is the A16 regression test: phone
// alone must not buy a token.
//
// The "passwordless account" case reproduces the hole — it is the exact shape of
// production users 34 (super_admin) and 1 (admin) — and it FAILED before the fix
// (200 OK with an access_token, want 401).
func TestVerifiedFactorRequiredForPhoneLogin(t *testing.T) {
	pool := newAuthTestPool(t)
	r := newAuthRouter(t, pool)

	t.Run("passwordless account gets no token from phone alone", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		status, body := postJSON(t, r, "/api/auth/login", map[string]any{"phone": acc.phone})
		if status != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", status)
		}
		if got, _ := body["code"].(string); got != "otp_required" {
			t.Errorf("code = %q, want %q", got, "otp_required")
		}
		if hasToken(body) {
			t.Error("a token was returned for a phone number with no verified factor")
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0", n)
		}
	})

	t.Run("passwordless super_admin gets no token from phone alone", func(t *testing.T) {
		// The reported finding, stated exactly: production user 34.
		acc := insertAccount(t, pool, "super_admin", "")
		status, body := postJSON(t, r, "/api/auth/login", map[string]any{"phone": acc.phone})
		if status != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", status)
		}
		if hasToken(body) {
			t.Error("a phone number alone bought a super_admin session")
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0", n)
		}
	})

	t.Run("unknown phone is refused and creates no account", func(t *testing.T) {
		phone := randomTestPhone()
		t.Cleanup(func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE phone = $1`, phone)
		})
		status, body := postJSON(t, r, "/api/auth/login", map[string]any{"phone": phone})
		if status != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", status)
		}
		if hasToken(body) {
			t.Error("an unknown phone number was handed a token")
		}
		var n int
		if err := pool.QueryRow(context.Background(),
			`SELECT COUNT(*) FROM users WHERE phone = $1`, phone).Scan(&n); err != nil {
			t.Fatalf("count users: %v", err)
		}
		if n != 0 {
			t.Errorf("accounts created = %d, want 0 — this endpoint must not register anybody", n)
		}
	})

	// The other direction: the fix must not lock out the people who CAN prove
	// who they are. A password is a verified factor and still works.
	t.Run("correct password still signs in", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "correct-horse")
		status, body := postJSON(t, r, "/api/auth/login",
			map[string]any{"phone": acc.phone, "password": "correct-horse"})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("a correct password did not produce a session")
		}
		if n := tokenCount(t, pool, acc.id); n != 1 {
			t.Errorf("tokens minted = %d, want 1", n)
		}
	})

	t.Run("wrong password is refused", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "correct-horse")
		status, body := postJSON(t, r, "/api/auth/login",
			map[string]any{"phone": acc.phone, "password": "battery-staple"})
		if status != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", status)
		}
		if hasToken(body) {
			t.Error("a wrong password produced a session")
		}
	})
}

// TestVerifiedFactorOTPSignIn covers the path the app actually uses. Demo mode
// is ON here because that is how production is configured.
func TestVerifiedFactorOTPSignIn(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	r := newAuthRouter(t, pool)

	// An ordinary user completing request → verify must still sign in. This is
	// the app's real sign-up/sign-in flow and the constraint the fix must not
	// break: enforce OTP, don't remove it.
	t.Run("ordinary user completes a verified OTP sign-in", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusOK {
			t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
		}
		code, _ := body["demo_code"].(string)
		if code == "" {
			t.Fatal("demo request returned no code to verify with")
		}
		status, body = postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": code})
		if status != http.StatusOK {
			t.Fatalf("otp verify status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("a verified OTP did not produce a session")
		}
		if n := tokenCount(t, pool, acc.id); n != 1 {
			t.Errorf("tokens minted = %d, want 1", n)
		}
	})

	// An unverified caller — no code ever requested — must get nothing.
	t.Run("verify without a requested code is refused", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		status, body := postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "424242"})
		if status == http.StatusOK || hasToken(body) {
			t.Errorf("status = %d with token=%v, want a refusal", status, hasToken(body))
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0", n)
		}
	})

	// The PUBLIC demo code is handed to the caller in the response body, so it
	// proves nothing. It must not open a staff account — at either end of the
	// flow — and with no staff code configured (the state production is in) a
	// staff account has no demo door at all.
	for _, tier := range []string{"super_admin", "admin", "supervisor", "employee"} {
		t.Run("public demo OTP cannot sign in staff tier "+tier, func(t *testing.T) {
			acc := insertAccount(t, pool, tier, "")

			status, body := postJSON(t, r, "/api/auth/otp/request",
				map[string]any{"phone": acc.phone, "mode": "demo"})
			if status != http.StatusForbidden {
				t.Errorf("otp request status = %d, want 403 (body: %v)", status, body)
			}
			if got, _ := body["code"].(string); got != "staff_otp_unavailable" {
				t.Errorf("code = %q, want %q", got, "staff_otp_unavailable")
			}
			if _, leaked := body["demo_code"]; leaked {
				t.Error("a demo code was issued for a staff phone")
			}

			// Belt and braces: a demo code already sitting in otp_codes from
			// before this gate shipped must not be spendable either.
			otps := auth.NewOTPStore(pool)
			if err := otps.StoreCode(context.Background(), acc.phone, "424242", "demo"); err != nil {
				t.Fatalf("seed pre-existing demo code: %v", err)
			}
			status, body = postJSON(t, r, "/api/auth/otp/verify",
				map[string]any{"phone": acc.phone, "code": "424242"})
			if status != http.StatusForbidden {
				t.Errorf("otp verify status = %d, want 403 (body: %v)", status, body)
			}
			if hasToken(body) {
				t.Error("a demo code minted a staff session")
			}
			if n := tokenCount(t, pool, acc.id); n != 0 {
				t.Errorf("tokens minted = %d, want 0", n)
			}
		})
	}

	// The fix must not lock staff out of the factor that IS real. A code
	// delivered out-of-band (mode "real") still signs a staff account in, so
	// configuring OTPIQ restores their access without another code change.
	t.Run("real OTP still signs a staff account in", func(t *testing.T) {
		acc := insertAccount(t, pool, "super_admin", "")
		otps := auth.NewOTPStore(pool)
		if err := otps.StoreCode(context.Background(), acc.phone, "424242", "real"); err != nil {
			t.Fatalf("seed real code: %v", err)
		}
		status, body := postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "424242"})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("a real out-of-band code did not sign staff in")
		}
	})
}

// ─── The staff door under an OTP-only design ────────────────────────────
//
// Sign-in is phone + OTP only, so "staff must use their password instead" is no
// longer an answer: production ids 1 (admin) and 34 (super_admin) hold no
// password and no username. They get an OTP-shaped door whose code the server
// never prints — OTP_STAFF_DEMO_CODE, set by the owner and shared out of band.
//
// The exposure that buys, stated plainly and pinned below: while that variable
// is set, anyone holding BOTH a staff phone number AND that one code can sign in
// as that staff member, dashboard included. It is a shared password, and these
// tests exist to keep it from being anything weaker than one.
func TestStaffDemoOTPSignIn(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	t.Setenv("OTP_STAFF_DEMO_CODE", "907183")
	r := newAuthRouter(t, pool)

	// The owner's requirement: a staff account signs in with a phone and a code,
	// like everyone else. Without this, ids 1 and 34 stay locked out.
	t.Run("staff completes request to verify with the staff code", func(t *testing.T) {
		acc := insertAccount(t, pool, "super_admin", "")

		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusOK {
			t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
		}
		// The whole point of a separate code: it is never handed back.
		if leaked, ok := body["demo_code"]; ok {
			t.Errorf("the staff code was echoed to the caller: %v", leaked)
		}

		status, body = postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "907183"})
		if status != http.StatusOK {
			t.Fatalf("otp verify status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("the staff code did not produce a session")
		}
		if n := tokenCount(t, pool, acc.id); n != 1 {
			t.Errorf("tokens minted = %d, want 1", n)
		}
	})

	// The public code is printed in every ordinary user's response, so it must
	// stay useless against staff even now that staff have a demo door.
	t.Run("the public demo code still cannot sign staff in", func(t *testing.T) {
		acc := insertAccount(t, pool, "admin", "")
		if _, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"}); body["demo_code"] != nil {
			t.Fatal("staff request echoed a code")
		}
		status, body := postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "424242"})
		if status != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401 (body: %v)", status, body)
		}
		if hasToken(body) {
			t.Error("the public demo code minted a staff session")
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0", n)
		}
	})

	// A wrong staff code must answer exactly as a wrong ordinary code does, or
	// the endpoint becomes an oracle for "is this number staff?".
	t.Run("a wrong code reveals nothing about the account", func(t *testing.T) {
		staff := insertAccount(t, pool, "supervisor", "")
		ordinary := insertAccount(t, pool, "user", "")
		for _, acc := range []authTestAccount{staff, ordinary} {
			postJSON(t, r, "/api/auth/otp/request", map[string]any{"phone": acc.phone, "mode": "demo"})
		}
		_, staffBody := postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": staff.phone, "code": "111111"})
		_, ordinaryBody := postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": ordinary.phone, "code": "111111"})

		staffJSON, _ := json.Marshal(staffBody)
		ordinaryJSON, _ := json.Marshal(ordinaryBody)
		if string(staffJSON) != string(ordinaryJSON) {
			t.Errorf("wrong-code answers differ:\n  staff    = %s\n  ordinary = %s", staffJSON, ordinaryJSON)
		}
		if got, _ := staffBody["code"].(string); got != "invalid_otp" {
			t.Errorf("code = %q, want %q", got, "invalid_otp")
		}
	})

	// Ordinary users must be untouched by any of this — they still receive the
	// public code in the body, which is the app's only source for it.
	t.Run("an ordinary user still gets the echoed public code", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if got, _ := body["demo_code"].(string); got != "424242" {
			t.Errorf("demo_code = %q, want %q — the app has no other source for it", got, "424242")
		}
	})
}

// TestStaffDemoCodeMisconfiguration pins the two ways the staff door must refuse
// to open, both of which would otherwise restore the original hole silently.
func TestStaffDemoCodeMisconfiguration(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")

	t.Run("a staff code equal to the public code is ignored", func(t *testing.T) {
		t.Setenv("OTP_STAFF_DEMO_CODE", "424242")
		r := newAuthRouter(t, pool)
		acc := insertAccount(t, pool, "super_admin", "")
		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusForbidden {
			t.Errorf("status = %d, want 403 (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "staff_otp_unavailable" {
			t.Errorf("code = %q, want %q", got, "staff_otp_unavailable")
		}
	})

	t.Run("a malformed staff code is ignored", func(t *testing.T) {
		t.Setenv("OTP_STAFF_DEMO_CODE", "letmein")
		r := newAuthRouter(t, pool)
		acc := insertAccount(t, pool, "admin", "")
		status, _ := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusForbidden {
			t.Errorf("status = %d, want 403", status)
		}
	})
}

// TestRealDeliveryTakesOverFromDemo is the switchover proof: setting
// OTPIQ_API_KEY — and nothing else, no code change, no app release — must move
// every sign-in onto real out-of-band codes.
//
// It matters that the request below asks for mode "demo". That is what the
// SHIPPED app sends, hard-coded, and a build already on people's phones cannot
// be told otherwise. If the server honoured the caller's choice, configuring
// OTPIQ would change nothing for the users who are actually out there.
func TestRealDeliveryTakesOverFromDemo(t *testing.T) {
	pool := newAuthTestPool(t)

	// A stand-in for OTPIQ. Deterministic and offline — it records the code the
	// server tried to deliver, which is exactly what must NOT be in the response.
	var delivered struct {
		phone string
		code  string
	}
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		var sent struct {
			PhoneNumber      string `json:"phoneNumber"`
			VerificationCode string `json:"verificationCode"`
		}
		_ = json.NewDecoder(req.Body).Decode(&sent)
		delivered.phone, delivered.code = sent.PhoneNumber, sent.VerificationCode
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"smsId":"sms-test-1","cost":1,"remainingCredit":99,"canCover":true}`))
	}))
	t.Cleanup(gateway.Close)

	// Demo is left switched ON, to show the key alone is what settles it.
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	t.Setenv("OTPIQ_API_KEY", "sk_test_switchover")
	t.Setenv("OTPIQ_BASE_URL", gateway.URL)
	otpiq := auth.NewOTPIQClient()
	if otpiq == nil {
		t.Fatal("OTPIQ client was nil with OTPIQ_API_KEY set")
	}
	r := newAuthRouterWith(t, pool, otpiq)

	// Staff, because they are the accounts the interim locks out. Once delivery
	// is real, the staff code is irrelevant and they sign in like anyone else.
	acc := insertAccount(t, pool, "super_admin", "")

	status, body := postJSON(t, r, "/api/auth/otp/request",
		map[string]any{"phone": acc.phone, "mode": "demo"})
	if status != http.StatusOK {
		t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
	}
	if got, _ := body["mode"].(string); got != "real" {
		t.Errorf("mode = %q, want %q — a demo request was not upgraded", got, "real")
	}
	if leaked, ok := body["demo_code"]; ok {
		t.Errorf("the response printed a code after switchover: %v", leaked)
	}
	if delivered.code == "" {
		t.Fatal("nothing was handed to the gateway — no real code was sent")
	}
	if delivered.code == "424242" {
		t.Error("the gateway was sent the fixed demo code, not a generated one")
	}

	// And the delivered code is the one that works.
	status, body = postJSON(t, r, "/api/auth/otp/verify",
		map[string]any{"phone": acc.phone, "code": delivered.code})
	if status != http.StatusOK {
		t.Fatalf("otp verify status = %d, want 200 (body: %v)", status, body)
	}
	if !hasToken(body) {
		t.Error("the out-of-band code did not produce a session")
	}
	if got, _ := body["mode"].(string); got != "real" {
		t.Errorf("verified mode = %q, want %q", got, "real")
	}
}
