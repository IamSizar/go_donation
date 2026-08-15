// dashboard_access_test.go — the authorisation boundary for /api/admin/*.
//
// WHY THIS FILE EXISTS (A15)
//
// The client reported that ordinary app users could reach the admin dashboard.
// They could: `users.is_admin` (a SMALLINT legacy flag) used to be an
// INDEPENDENT grant on every dashboard gate — `RequireAdmin`, `RequireAdminTier`
// and `AdminLogin` all short-circuited on `is_admin = 1` BEFORE looking at
// `staff_tier`. Production still contains a row in exactly that shape
// (is_admin = 1, staff_tier = 'user'), i.e. an ordinary app user holding the
// legacy flag. Because the mobile app and the dashboard share one token store,
// that user's ORDINARY app token — minted by POST /api/auth/login — sailed
// through `RequireAdmin`.
//
// These tests pin the boundary so the short-circuit can never come back:
// `staff_tier` is the only field that grants dashboard access.
//
// The integration tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_a15
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_a15?sslmode=disable' \
//	  go test ./internal/auth/ -run Dashboard -v
package auth

import (
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newTestPool connects to the throwaway database named by TEST_DATABASE_URL and
// brings its schema up to date. Skips the test when the variable is unset so a
// developer (or CI) without a local Postgres still gets a green `go test ./...`.
func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping dashboard-access integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	// Real migrations, not a hand-written fixture schema: the gate reads a dozen
	// user columns and a fixture would silently drift away from production.
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// insertUser creates one throwaway user row in the shape the test cares about
// and registers its deletion, so tests never leak rows into each other.
func insertUser(t *testing.T, pool *pgxpool.Pool, isAdmin int, staffTier string) int64 {
	t.Helper()
	ctx := context.Background()
	// Phone is UNIQUE; randomise it so parallel/repeat runs don't collide.
	phone := fmt.Sprintf("99900%08d", rand.Intn(100000000))
	var id int64
	err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, is_admin, staff_tier,
		                    registration_status, account_status)
		 VALUES ($1, 1, 1, $2, $3, 'approved', 'active')
		 RETURNING id`, phone, isAdmin, staffTier).Scan(&id)
	if err != nil {
		t.Fatalf("insert user (is_admin=%d staff_tier=%s): %v", isAdmin, staffTier, err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM api_access_tokens WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// adminRouter wires RequireAdmin in front of a sentinel handler on the real
// admin path, so the assertion is "did the request reach the handler", not
// "did some helper return a bool".
func adminRouter(store *TokenStore, reached *bool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/admin/campaigns", RequireAdmin(store), func(c *gin.Context) {
		*reached = true
		c.JSON(http.StatusOK, gin.H{"status": "success"})
	})
	return r
}

// callAdminRoute issues a real app token for userID — exactly what
// POST /api/auth/login hands a mobile user — and replays it against the admin
// route. Returns the status code and whether the handler body ran.
func callAdminRoute(t *testing.T, pool *pgxpool.Pool, userID int64) (status int, reached bool) {
	t.Helper()
	store := NewTokenStore(pool)
	session, err := store.IssueToken(context.Background(), userID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
	router := adminRouter(store, &reached)
	req := httptest.NewRequest(http.MethodGet, "/api/admin/campaigns", nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec.Code, reached
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestDashboardAccessBoundary is the A15 regression test: which resolved users
// may cross RequireAdmin, driven end-to-end through a real token.
//
// The `legacy is_admin flag, no staff tier` case is the one that reproduces the
// client's report — it is the exact shape of production user 23 — and it FAILED
// (handler reached, 200 OK) before `is_admin` was removed from the gate.
func TestDashboardAccessBoundary(t *testing.T) {
	pool := newTestPool(t)

	cases := []struct {
		name       string
		isAdmin    int
		staffTier  string
		wantStatus int
		wantReach  bool
	}{
		{
			// THE HOLE. An ordinary app user (tier 'user') carrying the legacy
			// flag. Their normal mobile login token must not open the dashboard.
			name:       "legacy is_admin flag but staff_tier=user is rejected",
			isAdmin:    1,
			staffTier:  "user",
			wantStatus: http.StatusForbidden,
			wantReach:  false,
		},
		{
			name:       "plain app user is rejected",
			isAdmin:    0,
			staffTier:  "user",
			wantStatus: http.StatusForbidden,
			wantReach:  false,
		},
		{
			// Guards the other direction: the fix must not lock real staff out.
			// This is the shape of production user 34 (is_admin = 0, super_admin).
			name:       "super_admin without the legacy flag is admitted",
			isAdmin:    0,
			staffTier:  "super_admin",
			wantStatus: http.StatusOK,
			wantReach:  true,
		},
		{
			name:       "employee tier is admitted",
			isAdmin:    0,
			staffTier:  "employee",
			wantStatus: http.StatusOK,
			wantReach:  true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := insertUser(t, pool, tc.isAdmin, tc.staffTier)
			status, reached := callAdminRoute(t, pool, id)
			if status != tc.wantStatus {
				t.Errorf("status = %d, want %d", status, tc.wantStatus)
			}
			if reached != tc.wantReach {
				t.Errorf("handler reached = %v, want %v", reached, tc.wantReach)
			}
		})
	}
}

// TestDashboardAccessRejectsMissingAndBogusTokens keeps the 401 half of the gate
// honest: no token and a well-formed-but-unknown token must both be refused
// before the handler runs.
func TestDashboardAccessRejectsMissingAndBogusTokens(t *testing.T) {
	pool := newTestPool(t)
	store := NewTokenStore(pool)

	for _, tc := range []struct {
		name   string
		header string
	}{
		{"no Authorization header", ""},
		{"malformed header", "Basic hunter2"},
		{"unknown token", "Bearer " + "0123456789abcdef01." +
			"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			reached := false
			router := adminRouter(store, &reached)
			req := httptest.NewRequest(http.MethodGet, "/api/admin/campaigns", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)
			if rec.Code != http.StatusUnauthorized {
				t.Errorf("status = %d, want 401", rec.Code)
			}
			if reached {
				t.Error("handler ran for an unauthenticated request")
			}
		})
	}
}

// ─── Tier gate (no database needed) ─────────────────────────────────────

// TestRequireAdminTierRejectsLegacyIsAdmin covers the SECOND gate the legacy
// flag short-circuited. RequireAdminTier guards the admin-level writes (trash
// restore, payment methods, catalogue CRUD, settings), and it too admitted
// is_admin = 1 regardless of tier. It reads the user straight off the gin
// context, so this needs no database and runs everywhere.
func TestRequireAdminTierRejectsLegacyIsAdmin(t *testing.T) {
	for _, tc := range []struct {
		name       string
		user       *ResolvedUser
		wantStatus int
		wantReach  bool
	}{
		{
			name:       "legacy is_admin flag but staff_tier=user is rejected",
			user:       &ResolvedUser{UserID: 23, IsAdmin: 1, StaffTier: "user"},
			wantStatus: http.StatusForbidden,
			wantReach:  false,
		},
		{
			name:       "supervisor is not admin-level",
			user:       &ResolvedUser{UserID: 2, IsAdmin: 0, StaffTier: "supervisor"},
			wantStatus: http.StatusForbidden,
			wantReach:  false,
		},
		{
			name:       "admin tier is admitted",
			user:       &ResolvedUser{UserID: 3, IsAdmin: 0, StaffTier: "admin"},
			wantStatus: http.StatusOK,
			wantReach:  true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			gin.SetMode(gin.TestMode)
			reached := false
			r := gin.New()
			// Mimic RequireAdmin having already attached the resolved user.
			r.POST("/api/admin/trash/:id/restore",
				func(c *gin.Context) { c.Set(contextUserKey, tc.user) },
				RequireAdminTier(),
				func(c *gin.Context) {
					reached = true
					c.JSON(http.StatusOK, gin.H{"status": "success"})
				})

			rec := httptest.NewRecorder()
			r.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/admin/trash/7/restore", nil))
			if rec.Code != tc.wantStatus {
				t.Errorf("status = %d, want %d", rec.Code, tc.wantStatus)
			}
			if reached != tc.wantReach {
				t.Errorf("handler reached = %v, want %v", reached, tc.wantReach)
			}
		})
	}
}
