// Submitting a brand-new registration must alert staff — OPOS #25275.
//
// WHY THIS EXISTS
// The registrant screen has always said "awaiting supervisor review," but
// RegistrationHandler had no Notifier at all: nothing ever told staff a
// review was waiting. NewBeneficiaryCaseAdminMsg / NewProjectRequestAdminMsg
// (both tagged "Requirement B1" in internal/notify/templates.go) cover an
// ELIGIBLE person submitting a case or aid request AFTER their account
// exists — B1 never reached the registration form itself, which is the very
// first submission any new account makes.
//
// A grandfathered account completing its profile (registration_status
// already 'approved') must NOT re-alert staff — that path was already
// reviewed once; this test also pins that the alert only fires for a
// genuine new ('pending') submission.
//
// Needs a throwaway Postgres and is skipped unless TEST_DATABASE_URL is set,
// same convention as admin_user_edit_guard_test.go:
//
//	createdb godonation_reg_notify
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_reg_notify?sslmode=disable' \
//	  go test ./internal/handlers/ -run RegistrationSubmit -v
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
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/storage"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// newRegistrationRouter wires the REAL route exactly as main.go does —
// bearer auth, then the handler, with a real Notifier over the same pool.
func newRegistrationRouter(t *testing.T, pool *pgxpool.Pool) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	tokenStore := auth.NewTokenStore(pool)
	userStore := users.NewStore(pool)
	notifier := notify.New(pool)
	regH := NewRegistrationHandler(userStore, storage.NewLocal(t.TempDir()), notifier)
	r.POST("/api/registration/submit", auth.RequireBearer(tokenStore), regH.Submit)
	return r
}

// insertIncompleteUser creates a brand-new account in the shape a fresh
// phone-OTP signup leaves it in: no role yet, registration_status
// 'incomplete' — the exact state Submit is meant to move out of pending.
func insertIncompleteUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	phone := randomTestPhone()
	var id int64
	err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, is_admin, registration_status)
		 VALUES ($1, NULL, 1, 0, 'incomplete') RETURNING id`, phone,
	).Scan(&id)
	if err != nil {
		t.Fatalf("insert incomplete user: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM app_notifications WHERE related_entity_type = 'users' AND related_entity_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM api_access_tokens WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// countStaffAlerts polls briefly — BroadcastToStaff runs off-request in a
// goroutine, so the row is not guaranteed to exist the instant the HTTP
// response returns.
func countStaffAlerts(t *testing.T, pool *pgxpool.Pool, registrantID int64) int {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		var n int
		if err := pool.QueryRow(context.Background(),
			`SELECT COUNT(*) FROM app_notifications
			  WHERE notification_type = 'admin_new_registration'
			    AND related_entity_type = 'users' AND related_entity_id = $1`,
			registrantID,
		).Scan(&n); err != nil {
			t.Fatalf("count staff alerts: %v", err)
		}
		if n > 0 || time.Now().After(deadline) {
			return n
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func TestRegistrationSubmitAlertsStaffOnlyWhenPending(t *testing.T) {
	pool := newAuthTestPool(t)

	t.Run("new registration alerts staff", func(t *testing.T) {
		insertAccount(t, pool, "employee", "") // BroadcastToStaff needs someone to notify
		registrant := insertIncompleteUser(t, pool)

		tokenStore := auth.NewTokenStore(pool)
		session, err := tokenStore.IssueToken(context.Background(), registrant, "test-agent", "127.0.0.1")
		if err != nil {
			t.Fatalf("issue token: %v", err)
		}

		body, _ := json.Marshal(map[string]any{
			"full_name": "Ali Hassan",
			"address":   "Erbil, Iraq",
			"role_id":   1,
		})
		req := httptest.NewRequest(http.MethodPost, "/api/registration/submit", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+session.AccessToken)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		newRegistrationRouter(t, pool).ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %s)", rec.Code, rec.Body.String())
		}
		var resp struct {
			RegistrationStatus string `json:"registration_status"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		if resp.RegistrationStatus != "pending" {
			t.Fatalf("registration_status = %q, want pending", resp.RegistrationStatus)
		}

		if n := countStaffAlerts(t, pool, registrant); n == 0 {
			t.Errorf("staff alerts = 0, want at least 1 — a pending registration must notify staff")
		}
	})

	t.Run("a grandfathered approved account completing its profile does not re-alert", func(t *testing.T) {
		registrant := insertIncompleteUser(t, pool)
		// Fast-forward straight to 'approved', as if this account had already
		// been reviewed once before (the "grandfathered" case the handler's
		// own comment describes).
		if _, err := pool.Exec(context.Background(),
			`UPDATE users SET registration_status = 'approved', role_id = 1 WHERE id = $1`, registrant,
		); err != nil {
			t.Fatalf("pre-approve user: %v", err)
		}

		tokenStore := auth.NewTokenStore(pool)
		session, err := tokenStore.IssueToken(context.Background(), registrant, "test-agent", "127.0.0.1")
		if err != nil {
			t.Fatalf("issue token: %v", err)
		}

		body, _ := json.Marshal(map[string]any{
			"full_name": "Sara Ahmed",
			"address":   "Duhok, Iraq",
			"role_id":   1,
		})
		req := httptest.NewRequest(http.MethodPost, "/api/registration/submit", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+session.AccessToken)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		newRegistrationRouter(t, pool).ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (body: %s)", rec.Code, rec.Body.String())
		}

		// A real negative can't be proven by absence alone on a timing-based
		// system, so give the (nonexistent) alert the same window a real one
		// would need, then assert zero.
		if n := countStaffAlerts(t, pool, registrant); n != 0 {
			t.Errorf("staff alerts = %d, want 0 — a grandfathered profile completion was already reviewed once", n)
		}
	})
}
