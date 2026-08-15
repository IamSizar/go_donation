// auth_verified_factor_test.go — what each factor is allowed to buy (A16).
//
// # THE DESIGN THIS PINS
//
// The owner's decision: "OTP for account creation only, password will be used
// for sign in to the app later." Three rules follow, and every test below is
// one of them:
//
//	SIGN-IN   is POST /auth/login with a phone and a PASSWORD.
//	SIGN-UP   is a code, then a password — and the code alone signs nobody in.
//	AN OTP    can do exactly one thing: give a password to an account that has
//	          NONE. It can never open an account that already has one.
//
// That last rule is the entire bound on the bridge built for the 36 production
// accounts (of 46) that hold no password — including ids 1 (`admin`) and 34
// (`super_admin`), which have no username either and so cannot use the
// dashboard's username+password door. Each of those accounts can be claimed
// ONCE, after which the OTP path is powerless against it forever.
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
// body. A factor that hands you the factor is not one. These tests therefore
// run with demo mode ON, exactly as production has it, which is what makes the
// "an OTP can only ever set a FIRST password" bound load-bearing rather than
// theoretical: under demo delivery a code is public, so the bound is the only
// thing standing between a phone number and an account.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout
// (same convention as internal/auth/dashboard_access_test.go):
//
//	createdb godonation_a16
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_a16?sslmode=disable' \
//	  go test ./internal/handlers/ -run 'VerifiedFactor|Password|Staff|RealDelivery|OTP' -v
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
		_, _ = pool.Exec(bg, `DELETE FROM password_setup_tickets WHERE phone = $1`, phone)
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
	// The password-setup route is wired through an interface assertion rather
	// than as h.SetPassword, for one reason worth the oddity: it keeps this file
	// COMPILING against the commit it is meant to fail on. Anyone can check out
	// the parent of this change, drop this file in, and watch the new cases fail
	// — which is the only thing that shows they test something. Where the method
	// does not exist the route simply is not registered, and the tests get the
	// 404 they deserve.
	if ps, ok := any(h).(passwordSetupHandler); ok {
		r.POST("/api/auth/password/set", ps.SetPassword)
	}
	return r
}

// passwordSetupHandler is the half of *AuthHandler this file needs and that did
// not exist before A16's second pass. See newAuthRouterWith.
type passwordSetupHandler interface {
	SetPassword(*gin.Context)
}

// setupTicketGuessBudget mirrors auth.SetupTicketMaxAttempts. It is restated
// here rather than imported for the same reason as passwordSetupHandler above:
// so this file compiles against the commit it is meant to fail on. If the two
// ever diverge, "wrong tickets are counted and then exhausted" fails loudly.
const setupTicketGuessBudget = 5

// ─── Reading the flow ───────────────────────────────────────────────────

// setupTicketFrom pulls the single-use ticket out of an /auth/otp/verify
// response, failing the test when there is none — a verify that hands back no
// ticket has not authorised a password, whatever else it said.
func setupTicketFrom(t *testing.T, body map[string]any) string {
	t.Helper()
	ticket, _ := body["setup_ticket"].(string)
	if strings.TrimSpace(ticket) == "" {
		t.Fatalf("no setup_ticket in verify response: %v", body)
	}
	return ticket
}

// verifyForSetup runs request → verify for a phone in demo mode and returns the
// setup ticket. code is the code that phone is expected to answer to (the
// public demo code for an ordinary account, OTP_STAFF_DEMO_CODE for staff).
func verifyForSetup(t *testing.T, r *gin.Engine, phone, code string) string {
	t.Helper()
	status, body := postJSON(t, r, "/api/auth/otp/request", map[string]any{"phone": phone, "mode": "demo"})
	if status != http.StatusOK {
		t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
	}
	status, body = postJSON(t, r, "/api/auth/otp/verify", map[string]any{"phone": phone, "code": code})
	if status != http.StatusOK {
		t.Fatalf("otp verify status = %d, want 200 (body: %v)", status, body)
	}
	return setupTicketFrom(t, body)
}

// storedPasswordHash reads a user's password_hash straight from the database.
// The assertions that matter are about what is STORED, not about what a
// response said — a handler that answered 200 and wrote nothing would pass a
// response-only test and lock the user out for real.
func storedPasswordHash(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	var hash *string
	if err := pool.QueryRow(context.Background(),
		`SELECT password_hash FROM users WHERE id = $1`, userID).Scan(&hash); err != nil {
		t.Fatalf("read password hash: %v", err)
	}
	if hash == nil {
		return ""
	}
	return *hash
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

// postJSONFrom is postJSON with a FIXED client address, for the one test that
// is about the per-IP budget rather than about a handler's logic.
func postJSONFrom(t *testing.T, r *gin.Engine, remoteAddr, path string, body map[string]any) (int, map[string]any) {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(string(raw)))
	req.Header.Set("Content-Type", "application/json")
	req.RemoteAddr = remoteAddr
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

// countUsersWithPhone reports how many rows hold this number. Used wherever the
// assertion is "no account was created" — a response body cannot prove that.
func countUsersWithPhone(t *testing.T, pool *pgxpool.Pool, phone string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM users WHERE phone = $1`, phone).Scan(&n); err != nil {
		t.Fatalf("count users: %v", err)
	}
	return n
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

	// A correct code buys the right to choose a password — and NOT a session.
	// This is the rule the whole design rests on: under demo delivery the code
	// is printed to whoever asks for it, so if a code minted sessions, a phone
	// number would still be a credential.
	t.Run("a verified OTP buys a password setup, not a session", func(t *testing.T) {
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
		if got, _ := body["status"].(string); got != "password_setup_required" {
			t.Errorf("status = %q, want %q", got, "password_setup_required")
		}
		if hasToken(body) {
			t.Error("a code alone produced a session")
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0 — a code is not a sign-in", n)
		}
		setupTicketFrom(t, body) // and it did authorise a password
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
	// delivered out-of-band (mode "real") still reaches a staff account, so
	// configuring OTPIQ restores their route in without another code change.
	t.Run("real OTP still reaches a passwordless staff account", func(t *testing.T) {
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
		setupTicketFrom(t, body)
		if hasToken(body) {
			t.Error("a real code minted a session instead of a password setup")
		}
	})
}

// TestOTPCannotOpenAnAccountThatHasAPassword is the pin the owner's design
// turns on: once an account has a password, that password is the ONLY way in.
//
// It is not a hypothetical. Ten production accounts have a password today,
// among them ids 15, 18 and 19 — an admin and two super_admins. Before this
// change /auth/otp/verify never looked at `password_hash` at all: it consumed
// the code, found-or-created the row, and minted a 30-day token. So the public
// demo code — which /auth/otp/request prints in its own response body — walked
// straight past every one of those passwords.
func TestOTPCannotOpenAnAccountThatHasAPassword(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	t.Setenv("OTP_STAFF_DEMO_CODE", "907183")
	r := newAuthRouter(t, pool)

	// Ordinary account first: nothing about this rule is staff-specific.
	t.Run("an ordinary account with a password is not opened by a code", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "correct-horse")
		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusOK {
			t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
		}
		code, _ := body["demo_code"].(string)
		status, body = postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": code})
		if status != http.StatusConflict {
			t.Errorf("otp verify status = %d, want 409 (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "password_required" {
			t.Errorf("code = %q, want %q", got, "password_required")
		}
		if hasToken(body) {
			t.Error("a code signed in an account that has a password")
		}
		if _, leaked := body["setup_ticket"]; leaked {
			t.Error("a setup ticket was issued against an account that already has a password")
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0", n)
		}
	})

	// And the staff code — the one the owner shares out of band — is no more
	// powerful. It rescues an account with NO password; it does not reset one.
	t.Run("the staff code cannot open a staff account that has a password", func(t *testing.T) {
		acc := insertAccount(t, pool, "super_admin", "correct-horse")
		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusOK {
			t.Fatalf("otp request status = %d, want 200 (body: %v)", status, body)
		}
		status, body = postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "907183"})
		if status != http.StatusConflict {
			t.Errorf("otp verify status = %d, want 409 (body: %v)", status, body)
		}
		if hasToken(body) {
			t.Error("the staff code signed in a super_admin that has a password")
		}
		if n := tokenCount(t, pool, acc.id); n != 0 {
			t.Errorf("tokens minted = %d, want 0", n)
		}
	})

	// The password itself keeps working — the rule is "use your password", not
	// "you are locked out".
	t.Run("the password still signs that account in", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "correct-horse")
		status, body := postJSON(t, r, "/api/auth/login",
			map[string]any{"phone": acc.phone, "password": "correct-horse"})
		if status != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("the password did not produce a session")
		}
	})
}

// ─── The staff door, and how it closes behind them ──────────────────────
//
// Production ids 1 (admin) and 34 (super_admin) hold no password and no
// username, so neither the app's password door nor the dashboard's
// username+password door is an answer for them. Their route in is the same
// bridge every passwordless account gets — verify the number, choose a password
// — with one extra lock: while demo delivery is all there is, the code that
// reaches a staff phone is OTP_STAFF_DEMO_CODE, which the server never prints.
//
// The exposure that buys, stated plainly and pinned below: while that variable
// is set, anyone holding BOTH a staff phone number AND that one code can claim
// that staff account by setting its first password. It is a shared password —
// and unlike the version it replaces, it is spent on first use: once the account
// HAS a password, this code can never touch it again.
func TestStaffDemoOTPSignIn(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	t.Setenv("OTP_STAFF_DEMO_CODE", "907183")
	r := newAuthRouter(t, pool)

	// The owner's requirement: ids 1 and 34 must be able to get back in. They
	// verify the number with the staff code, choose a password, and from then on
	// sign in with it like every other account.
	t.Run("staff claims a passwordless account once, then owns a password", func(t *testing.T) {
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
		if hasToken(body) {
			t.Error("the staff code produced a session on its own")
		}
		ticket := setupTicketFrom(t, body)

		status, body = postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "staff-chosen-pw",
		})
		if status != http.StatusOK {
			t.Fatalf("password set status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("setting the first password did not sign the staff account in")
		}
		if storedPasswordHash(t, pool, acc.id) == "" {
			t.Fatal("no password_hash was written")
		}

		// The password is now the door.
		status, body = postJSON(t, r, "/api/auth/login",
			map[string]any{"phone": acc.phone, "password": "staff-chosen-pw"})
		if status != http.StatusOK || !hasToken(body) {
			t.Fatalf("password sign-in status = %d token=%v, want 200 with a token", status, hasToken(body))
		}

		// And the shared staff code is spent: it cannot claim this account a
		// second time, so it can no longer be used to take it over.
		postJSON(t, r, "/api/auth/otp/request", map[string]any{"phone": acc.phone, "mode": "demo"})
		status, body = postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "907183"})
		if status != http.StatusConflict {
			t.Errorf("second claim status = %d, want 409 (body: %v)", status, body)
		}
		if _, leaked := body["setup_ticket"]; leaked {
			t.Error("the staff code was handed a second claim on an account it already claimed")
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

	// And the delivered code is the one that works: it authorises the password
	// this account has never had, which is how a staff member locked out today
	// gets back in the day OTPIQ is configured — with no staff code involved.
	status, body = postJSON(t, r, "/api/auth/otp/verify",
		map[string]any{"phone": acc.phone, "code": delivered.code})
	if status != http.StatusOK {
		t.Fatalf("otp verify status = %d, want 200 (body: %v)", status, body)
	}
	if got, _ := body["mode"].(string); got != "real" {
		t.Errorf("verified mode = %q, want %q", got, "real")
	}
	ticket := setupTicketFrom(t, body)

	status, body = postJSON(t, r, "/api/auth/password/set", map[string]any{
		"phone": acc.phone, "setup_ticket": ticket, "password": "after-switchover",
	})
	if status != http.StatusOK {
		t.Fatalf("password set status = %d, want 200 (body: %v)", status, body)
	}
	if !hasToken(body) {
		t.Error("the out-of-band code did not lead to a session")
	}
}

// ─── The bridge for the 36 accounts that hold no password ───────────────
//
// TestPasswordSetupBridge is the whole of the rescue path, and the whole of its
// bound. Read the subtest names as a sentence: a passwordless account can be
// claimed ONCE, by whoever answers a code on its number, and never again.
//
// That bound is doing real work, not decoration. While demo delivery is the
// only delivery configured, the code is public — so without "once, and only
// while the account has no password", this endpoint would be a permanent
// takeover of all 36 accounts by phone number alone.
func TestPasswordSetupBridge(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	r := newAuthRouter(t, pool)

	// The production shape: an existing row, no password, no username, no way in
	// under "sign in with your password" until this exists.
	t.Run("a passwordless account is rescued by choosing a password", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, acc.phone, "424242")

		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "chosen-by-owner",
		})
		if status != http.StatusOK {
			t.Fatalf("password set status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("setting a password did not sign the user in")
		}
		if got, _ := body["returning_user"].(bool); !got {
			t.Error("returning_user = false for an account that already existed")
		}
		if storedPasswordHash(t, pool, acc.id) == "" {
			t.Fatal("no password_hash was written")
		}
		// And it is the password they typed, not something else.
		status, body = postJSON(t, r, "/api/auth/login",
			map[string]any{"phone": acc.phone, "password": "chosen-by-owner"})
		if status != http.StatusOK || !hasToken(body) {
			t.Fatalf("sign-in with the new password: status = %d token = %v", status, hasToken(body))
		}
	})

	// The bound. A second claim on the same account must fail even with a fresh,
	// perfectly valid code — because by then the account HAS a credential.
	t.Run("a claimed account can never be claimed again", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, acc.phone, "424242")
		if status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "the-real-owner",
		}); status != http.StatusOK {
			t.Fatalf("first claim status = %d (body: %v)", status, body)
		}
		firstHash := storedPasswordHash(t, pool, acc.id)

		// An attacker with the public code tries the same route.
		status, body := postJSON(t, r, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status != http.StatusOK {
			t.Fatalf("second otp request status = %d (body: %v)", status, body)
		}
		status, body = postJSON(t, r, "/api/auth/otp/verify",
			map[string]any{"phone": acc.phone, "code": "424242"})
		if status != http.StatusConflict {
			t.Errorf("second verify status = %d, want 409 (body: %v)", status, body)
		}
		if _, leaked := body["setup_ticket"]; leaked {
			t.Fatal("a second setup ticket was issued for an account that has a password")
		}
		if got := storedPasswordHash(t, pool, acc.id); got != firstHash {
			t.Error("the stored password changed — the claim was not one-time")
		}
	})

	// Belt and braces on the same bound, at the level below: even if a ticket
	// were somehow held over a password being set (a race, or a bug upstream),
	// the WRITE itself refuses. This is the check that does not depend on
	// /auth/otp/verify getting its lookup right.
	t.Run("a ticket held across a password being set writes nothing", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, acc.phone, "424242")

		// Someone else sets a password in the meantime (this is the dashboard's
		// existing POST /admin/users/:id/password, reduced to its effect).
		hash, err := bcrypt.GenerateFromPassword([]byte("set-by-staff"), bcrypt.MinCost)
		if err != nil {
			t.Fatalf("hash: %v", err)
		}
		if _, err := pool.Exec(context.Background(),
			`UPDATE users SET password_hash = $2 WHERE id = $1`, acc.id, string(hash)); err != nil {
			t.Fatalf("seed password: %v", err)
		}

		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "too-late-now",
		})
		if status != http.StatusConflict {
			t.Errorf("status = %d, want 409 (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "password_already_set" {
			t.Errorf("code = %q, want %q", got, "password_already_set")
		}
		if hasToken(body) {
			t.Error("a stale ticket produced a session")
		}
		if got := storedPasswordHash(t, pool, acc.id); got != string(hash) {
			t.Error("the existing password was overwritten by a held ticket")
		}
	})

	// Sign-up: a number with no account at all. The row must appear here, at the
	// password step — not at verify, where an abandoned signup would leave an
	// empty passwordless row that anyone could then claim.
	t.Run("a new number becomes an account only when the password is set", func(t *testing.T) {
		phone := randomTestPhone()
		t.Cleanup(func() {
			bg := context.Background()
			_, _ = pool.Exec(bg, `DELETE FROM api_access_tokens WHERE user_id IN (SELECT id FROM users WHERE phone = $1)`, phone)
			_, _ = pool.Exec(bg, `DELETE FROM otp_codes WHERE phone = $1`, phone)
			_, _ = pool.Exec(bg, `DELETE FROM password_setup_tickets WHERE phone = $1`, phone)
			_, _ = pool.Exec(bg, `DELETE FROM users WHERE phone = $1`, phone)
		})

		ticket := verifyForSetup(t, r, phone, "424242")
		if n := countUsersWithPhone(t, pool, phone); n != 0 {
			t.Errorf("accounts after verify = %d, want 0 — verify must not create rows", n)
		}

		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": phone, "setup_ticket": ticket, "password": "brand-new-user",
		})
		if status != http.StatusOK {
			t.Fatalf("password set status = %d, want 200 (body: %v)", status, body)
		}
		if !hasToken(body) {
			t.Error("a completed signup did not produce a session")
		}
		if got, _ := body["returning_user"].(bool); got {
			t.Error("returning_user = true for a brand-new number")
		}
		if n := countUsersWithPhone(t, pool, phone); n != 1 {
			t.Errorf("accounts after set = %d, want 1", n)
		}
	})

	// Signup REQUIRES a verified code. Without a ticket there is no signup.
	t.Run("no ticket means no account and no password", func(t *testing.T) {
		phone := randomTestPhone()
		t.Cleanup(func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE phone = $1`, phone)
		})
		for _, ticket := range []string{"", "not-a-ticket", strings.Repeat("a", 64)} {
			status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
				"phone": phone, "setup_ticket": ticket, "password": "unverified-signup",
			})
			if status == http.StatusOK || hasToken(body) {
				t.Errorf("ticket %q: status = %d token = %v, want a refusal", ticket, status, hasToken(body))
			}
			if got, _ := body["code"].(string); got != "setup_ticket_invalid" {
				t.Errorf("ticket %q: code = %q, want %q", ticket, got, "setup_ticket_invalid")
			}
		}
		if n := countUsersWithPhone(t, pool, phone); n != 0 {
			t.Errorf("accounts created = %d, want 0", n)
		}
	})

	// A ticket is single-use: replaying it must not set a second password or
	// mint a second session.
	t.Run("a ticket cannot be spent twice", func(t *testing.T) {
		phone := randomTestPhone()
		t.Cleanup(func() {
			bg := context.Background()
			_, _ = pool.Exec(bg, `DELETE FROM api_access_tokens WHERE user_id IN (SELECT id FROM users WHERE phone = $1)`, phone)
			_, _ = pool.Exec(bg, `DELETE FROM users WHERE phone = $1`, phone)
		})
		ticket := verifyForSetup(t, r, phone, "424242")
		if status, _ := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": phone, "setup_ticket": ticket, "password": "first-and-only",
		}); status != http.StatusOK {
			t.Fatalf("first use status = %d, want 200", status)
		}
		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": phone, "setup_ticket": ticket, "password": "second-attempt",
		})
		if status == http.StatusOK || hasToken(body) {
			t.Errorf("replay status = %d token = %v, want a refusal", status, hasToken(body))
		}
	})

	// A ticket belongs to the number it was issued for. Otherwise one verified
	// signup would be a master key for every unclaimed account.
	t.Run("a ticket is bound to its own phone number", func(t *testing.T) {
		mine := insertAccount(t, pool, "user", "")
		victim := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, mine.phone, "424242")

		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": victim.phone, "setup_ticket": ticket, "password": "not-my-account",
		})
		if status == http.StatusOK || hasToken(body) {
			t.Errorf("status = %d token = %v, want a refusal", status, hasToken(body))
		}
		if storedPasswordHash(t, pool, victim.id) != "" {
			t.Error("a ticket for one number set a password on another")
		}
	})

	// An expired ticket is not a ticket. Ten minutes, and the proof is stale.
	t.Run("an expired ticket is refused", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, acc.phone, "424242")
		if _, err := pool.Exec(context.Background(),
			`UPDATE password_setup_tickets SET expires_at = now() - interval '1 minute' WHERE phone = $1`,
			acc.phone); err != nil {
			t.Fatalf("age the ticket: %v", err)
		}
		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "too-slow-typing",
		})
		if status != http.StatusGone {
			t.Errorf("status = %d, want 410 (body: %v)", status, body)
		}
		if got, _ := body["code"].(string); got != "setup_ticket_expired" {
			t.Errorf("code = %q, want %q", got, "setup_ticket_expired")
		}
		if storedPasswordHash(t, pool, acc.id) != "" {
			t.Error("an expired ticket still set a password")
		}
	})

	// Guessing a ticket is bounded the same way guessing a code is.
	t.Run("wrong tickets are counted and then exhausted", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		good := verifyForSetup(t, r, acc.phone, "424242")
		wrong := strings.Repeat("f", 64)
		for i := 0; i < setupTicketGuessBudget; i++ {
			status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
				"phone": acc.phone, "setup_ticket": wrong, "password": "guessing-away",
			})
			if status != http.StatusUnauthorized {
				t.Fatalf("attempt %d: status = %d, want 401 (body: %v)", i+1, status, body)
			}
		}
		// The budget is spent — even the RIGHT ticket is dead now.
		status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": good, "password": "guessing-away",
		})
		if status != http.StatusTooManyRequests {
			t.Errorf("status = %d, want 429 (body: %v)", status, body)
		}
		if storedPasswordHash(t, pool, acc.id) != "" {
			t.Error("a brute-forced ticket set a password")
		}
	})

	// Server-side password rules. The client mirrors them for instant feedback;
	// this is the one that decides, and it must decide before anything is
	// written — including before the ticket is spent.
	t.Run("password rules are enforced by the server", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, acc.phone, "424242")

		for _, tc := range []struct {
			name, password, wantCode string
			wantStatus               int
		}{
			{"seven characters", "1234567", "password_too_short", http.StatusBadRequest},
			{"empty", "", "password_too_short", http.StatusBadRequest},
			{"whitespace only", "          ", "password_too_short", http.StatusBadRequest},
			{"past bcrypt's 72-byte ceiling", strings.Repeat("x", 73), "password_too_long", http.StatusBadRequest},
		} {
			status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
				"phone": acc.phone, "setup_ticket": ticket, "password": tc.password,
			})
			if status != tc.wantStatus {
				t.Errorf("%s: status = %d, want %d (body: %v)", tc.name, status, tc.wantStatus, body)
			}
			if got, _ := body["code"].(string); got != tc.wantCode {
				t.Errorf("%s: code = %q, want %q", tc.name, got, tc.wantCode)
			}
			if hasToken(body) {
				t.Errorf("%s: a refused password produced a session", tc.name)
			}
			if storedPasswordHash(t, pool, acc.id) != "" {
				t.Fatalf("%s: a refused password was stored", tc.name)
			}
		}

		// The ticket survived every one of those, so a typo does not cost the
		// user their verification.
		if status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "12345678",
		}); status != http.StatusOK {
			t.Fatalf("the minimum-length password was refused: status = %d (body: %v)", status, body)
		}
	})

	// Set → sign in must round-trip exactly. /auth/login TRIMS the password it
	// compares, so a password stored untrimmed would look set and behave locked.
	t.Run("a padded password still signs in afterwards", func(t *testing.T) {
		acc := insertAccount(t, pool, "user", "")
		ticket := verifyForSetup(t, r, acc.phone, "424242")
		if status, body := postJSON(t, r, "/api/auth/password/set", map[string]any{
			"phone": acc.phone, "setup_ticket": ticket, "password": "  padded-password  ",
		}); status != http.StatusOK {
			t.Fatalf("password set status = %d (body: %v)", status, body)
		}
		status, body := postJSON(t, r, "/api/auth/login",
			map[string]any{"phone": acc.phone, "password": "padded-password"})
		if status != http.StatusOK || !hasToken(body) {
			t.Fatalf("sign-in after a padded password: status = %d token = %v", status, hasToken(body))
		}
	})
}

// TestOTPRequestRateLimitBoundsEnumeration pins that the signup flow cannot be
// swept across a phone book. Everything the flow reveals — whether a number has
// an account, whether it is claimable — sits behind /auth/otp/request, and that
// endpoint counts per IP (OTP_IP_MAX_REQUESTS_PER_HOUR, default 10/hour) as well
// as per phone. Without this the demo code, which is public, would turn signup
// into an unbounded oracle.
func TestOTPRequestRateLimitBoundsEnumeration(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	t.Setenv("OTP_IP_MAX_REQUESTS_PER_HOUR", "3")
	r := newAuthRouter(t, pool)

	// One attacker address, a different victim number every time — so nothing
	// but the per-IP budget can stop it.
	const attacker = "203.0.113.77:40000" // TEST-NET-3, reserved for documentation
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM otp_ip_rate_limit WHERE ip_address = '203.0.113.77'`)
	})

	allowed := 0
	for i := 0; i < 6; i++ {
		acc := insertAccount(t, pool, "user", "")
		status, _ := postJSONFrom(t, r, attacker, "/api/auth/otp/request",
			map[string]any{"phone": acc.phone, "mode": "demo"})
		if status == http.StatusOK {
			allowed++
			continue
		}
		if status != http.StatusTooManyRequests {
			t.Fatalf("request %d: status = %d, want 200 or 429", i+1, status)
		}
	}
	if allowed != 3 {
		t.Errorf("numbers probed from one address = %d, want 3 (the configured hourly cap)", allowed)
	}
}
