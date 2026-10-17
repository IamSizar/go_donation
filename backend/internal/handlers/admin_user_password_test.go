// admin_user_password_test.go — client report #79/#87: "the new password in the
// Edit User window does not work".
//
// Root cause: AdminLogin finds a dashboard account BY USERNAME, the Edit window
// offered a password box but no username box, and POST .../password happily
// stored a hash on a staff account that had no username — so the save
// "succeeded" and every sign-in then failed. These tests drive the real route
// and then the real sign-in to prove a password set from the dashboard is one
// the person can actually use.
//
//	TEST_DATABASE_URL=postgres://localhost/r2test?sslmode=disable \
//	  go test ./internal/handlers/ -run AdminUserPassword -v
package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

func newPasswordRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/api/admin/users/:id/password",
		auth.RequireAdmin(auth.NewTokenStore(pool)),
		NewAdminStatusHandler(pool, nil, nil).UserPassword,
	)
	ah := NewAuthHandler(auth.NewTokenStore(pool), auth.NewOTPStore(pool), users.NewStore(pool), nil, auth.NewLoginLockStore(pool), nil)
	r.POST("/api/auth/admin/login", ah.AdminLogin)
	r.POST("/api/auth/login", ah.Login)
	return r
}

func postJSONAs(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, actorID int64, path string, body map[string]any) (int, map[string]any) {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if actorID != 0 {
		s, err := auth.NewTokenStore(pool).IssueToken(context.Background(), actorID, "test-agent", "127.0.0.1")
		if err != nil {
			t.Fatalf("token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+s.AccessToken)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

func uniqueName(prefix string) string {
	return fmt.Sprintf("%s%d", prefix, time.Now().UnixNano()%1_000_000_000)
}

func dropUsername(t *testing.T, pool *pgxpool.Pool, name string) {
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `UPDATE users SET username = NULL WHERE username = $1`, name) })
}

func TestAdminUserPasswordStaffNeedsUsername(t *testing.T) {
	pool := newAuthTestPool(t)
	r := newPasswordRouter(pool)
	actor := insertAccount(t, pool, "super_admin", "")
	staff := insertAccount(t, pool, "supervisor", "")
	path := fmt.Sprintf("/api/admin/users/%d/password", staff.id)

	// 1. Password alone on a staff account with no username is refused up
	//    front, with a code the dashboard can act on — it used to "succeed".
	st, body := postJSONAs(t, r, pool, actor.id, path, map[string]any{"password": "secret99"})
	if st != http.StatusBadRequest || body["code"] != "username_required" {
		t.Fatalf("password-only on username-less staff = %d %v, want 400 username_required", st, body)
	}

	// 2. Username + password together: saved, and the person can sign in.
	name := uniqueName("sup")
	dropUsername(t, pool, name)
	st, body = postJSONAs(t, r, pool, actor.id, path, map[string]any{"password": "secret99", "username": "  " + name + " "})
	if st != http.StatusOK {
		t.Fatalf("username+password = %d %v, want 200", st, body)
	}
	st, body = postJSONAs(t, r, pool, 0, "/api/auth/admin/login", map[string]any{"username": name, "password": "secret99"})
	if st != http.StatusOK {
		t.Fatalf("dashboard sign-in with the dashboard-set credentials = %d %v, want 200", st, body)
	}

	// 3. Changing only the password later (username already on the row) works
	//    and the new password is the one that signs in.
	st, _ = postJSONAs(t, r, pool, actor.id, path, map[string]any{"password": "other1234"})
	if st != http.StatusOK {
		t.Fatalf("password-only on staff WITH username = %d, want 200", st)
	}
	if st, _ = postJSONAs(t, r, pool, 0, "/api/auth/admin/login", map[string]any{"username": name, "password": "secret99"}); st == http.StatusOK {
		t.Fatalf("old password still signs in after change")
	}
	if st, body = postJSONAs(t, r, pool, 0, "/api/auth/admin/login", map[string]any{"username": name, "password": "other1234"}); st != http.StatusOK {
		t.Fatalf("new password does not sign in: %d %v", st, body)
	}

	// 4. Username-only edit must not wipe the password.
	name2 := uniqueName("sup")
	dropUsername(t, pool, name2)
	if st, body = postJSONAs(t, r, pool, actor.id, path, map[string]any{"password": "", "username": name2}); st != http.StatusOK {
		t.Fatalf("username-only = %d %v", st, body)
	}
	if st, body = postJSONAs(t, r, pool, 0, "/api/auth/admin/login", map[string]any{"username": name2, "password": "other1234"}); st != http.StatusOK {
		t.Fatalf("username-only edit cleared/changed the password: %d %v", st, body)
	}
}

func TestAdminUserPasswordUsernameRules(t *testing.T) {
	pool := newAuthTestPool(t)
	r := newPasswordRouter(pool)
	actor := insertAccount(t, pool, "super_admin", "")
	a := insertAccount(t, pool, "employee", "")
	b := insertAccount(t, pool, "employee", "")
	name := uniqueName("dup")
	dropUsername(t, pool, name)

	if st, body := postJSONAs(t, r, pool, actor.id, fmt.Sprintf("/api/admin/users/%d/password", a.id), map[string]any{"password": "secret99", "username": name}); st != http.StatusOK {
		t.Fatalf("first username = %d %v", st, body)
	}
	st, body := postJSONAs(t, r, pool, actor.id, fmt.Sprintf("/api/admin/users/%d/password", b.id), map[string]any{"password": "secret99", "username": name})
	if st != http.StatusConflict || body["code"] != "username_taken" {
		t.Fatalf("duplicate username = %d %v, want 409 username_taken", st, body)
	}
	st, body = postJSONAs(t, r, pool, actor.id, fmt.Sprintf("/api/admin/users/%d/password", b.id), map[string]any{"password": "secret99", "username": "a b"})
	if st != http.StatusBadRequest || body["code"] != "username_invalid" {
		t.Fatalf("bad username = %d %v, want 400 username_invalid", st, body)
	}
}

// A plain app user needs no username: a password alone is accepted and is then
// required by the phone sign-in (the Phase 20 password gate).
func TestAdminUserPasswordPlainUserPhoneLogin(t *testing.T) {
	pool := newAuthTestPool(t)
	r := newPasswordRouter(pool)
	actor := insertAccount(t, pool, "super_admin", "")
	u := insertAccount(t, pool, "user", "")
	if st, body := postJSONAs(t, r, pool, actor.id, fmt.Sprintf("/api/admin/users/%d/password", u.id), map[string]any{"password": "secret99"}); st != http.StatusOK {
		t.Fatalf("plain user password = %d %v", st, body)
	}
	st, body := postJSONAs(t, r, pool, 0, "/api/auth/login", map[string]any{"phone": u.phone, "password": "secret99"})
	if st != http.StatusOK {
		t.Fatalf("phone sign-in with dashboard-set password = %d %v, want 200", st, body)
	}
}
