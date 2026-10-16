// chat_guest_support_test.go proves that a lightweight guest account cannot
// open or post in any chat, including support. Support messaging requires a
// full signed-in account.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k20?sslmode=disable' \
//	  go test ./internal/handlers/ -run GuestSupport -v
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// ─── Harness ────────────────────────────────────────────────────────────

// makeGuestUser inserts a real guest row — is_guest true, no phone — matching
// what handlers.GuestRegister actually creates.
func makeGuestUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	ctx := context.Background()
	contactBlockSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (username, password_hash, role_id, active, staff_tier, is_guest, registration_status)
		 VALUES ($1, 'x', NULL, 1, 'user', TRUE, 'approved') RETURNING id`,
		fmt.Sprintf("k20guest%d", contactBlockSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert guest: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	return id
}

// configureSupportUser points the support chat at a staff account, the way the
// Settings page does, and puts the setting back afterwards.
func configureSupportUser(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	ctx := context.Background()
	var previous *string
	_ = pool.QueryRow(ctx, `SELECT value FROM app_settings WHERE key = 'support_user_id'`).Scan(&previous)
	if _, err := pool.Exec(ctx,
		`INSERT INTO app_settings (key, value) VALUES ('support_user_id', $1)
		 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
		fmt.Sprintf("%d", userID),
	); err != nil {
		t.Fatalf("configure support user: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		if previous == nil {
			_, _ = pool.Exec(ctx, `DELETE FROM app_settings WHERE key = 'support_user_id'`)
			return
		}
		_, _ = pool.Exec(ctx,
			`UPDATE app_settings SET value = $1 WHERE key = 'support_user_id'`, *previous)
	})
}

// newGuestChatRouter wires the guest-reachable chat routes exactly as main.go
// does, because the gates ARE what is under test. R2 #16 (client 2026-10-16):
// a guest may open a support thread and post in it (no RequireNotGuest there;
// GuestSupportThreadOnly on the thread routes keeps every OTHER thread shut).
func newGuestChatRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	h := NewChatHandler(chat.New(pool), notify.New(pool), pool)
	bearer := auth.RequireBearer(auth.NewTokenStore(pool))
	approved := auth.RequireApproved()
	r := gin.New()
	r.POST("/api/chats/support", bearer, approved, h.SupportThread)
	r.POST("/api/chats/request", bearer, approved, auth.RequireNotGuest(), h.Request)
	r.POST("/api/chats/:id/messages", bearer, approved, h.GuestSupportThreadOnly(), h.PostMessage)
	return r
}

func guestPost(t *testing.T, pool *pgxpool.Pool, r *gin.Engine, userID int64, path, body string) (int, map[string]any) {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(context.Background(), userID, "k20-test", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_access_tokens WHERE user_id = $1`, userID)
	})
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

// ─── Support is open to visitors (R2 #16) ───────────────────────────────

func TestGuestSupport_GuestCanOpenASupportThread(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newGuestChatRouter(pool)
	support := makeContactUser(t, pool, "employee")
	configureSupportUser(t, pool, support)
	guest := makeGuestUser(t, pool)

	code, body := guestPost(t, pool, r, guest, "/api/chats/support", `{}`)
	if code != http.StatusOK && code != http.StatusCreated {
		t.Fatalf("status = %d, want 200/201 — a visitor may contact support (body %v)", code, body)
	}
}

func TestGuestSupport_GuestCanPostToSupport(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newGuestChatRouter(pool)
	support := makeContactUser(t, pool, "employee")
	guest := makeGuestUser(t, pool)
	thread := makeContactThread(t, pool, guest, support) // already 'active'
	if _, err := pool.Exec(context.Background(),
		`UPDATE chat_threads SET kind = 'support' WHERE id = $1`, thread); err != nil {
		t.Fatalf("mark support: %v", err)
	}

	code, body := guestPost(t, pool, r, guest,
		fmt.Sprintf("/api/chats/%d/messages", thread), `{"body":"How do I register for aid?"}`)
	if code != http.StatusOK && code != http.StatusCreated {
		t.Fatalf("status = %d, want 200/201 — a visitor may message support (body %v)", code, body)
	}
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_messages WHERE thread_id = $1`, thread).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n != 1 {
		t.Fatalf("chat_messages has %d rows, want 1", n)
	}
}

// ─── What a guest MAY NOT do — the abuse surface ────────────────────────

func TestGuestSupport_GuestCannotOpenAPeerChat(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newGuestChatRouter(pool)
	guest := makeGuestUser(t, pool)

	code, body := guestPost(t, pool, r, guest, "/api/chats/request", `{"donation_id":1}`)
	if code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 — a throwaway account must not be able to open a chat with a user (body %v)", code, body)
	}
	if body["code"] != "guest_restricted" {
		t.Fatalf("code = %v, want \"guest_restricted\"", body["code"])
	}
}

// The one that matters most. Opening the support route must not accidentally
// open every OTHER thread: if a guest ever ends up party to a donor↔beneficiary
// thread, they must still be unable to post into it.
func TestGuestSupport_GuestCannotPostIntoAPeerThread(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newGuestChatRouter(pool)
	guest := makeGuestUser(t, pool)
	ordinary := makeContactUser(t, pool, "user")
	thread := makeContactThread(t, pool, guest, ordinary)

	code, body := guestPost(t, pool, r, guest,
		fmt.Sprintf("/api/chats/%d/messages", thread), `{"body":"hello"}`)
	if code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 — a guest may only talk to staff (body %v)", code, body)
	}
	if body["code"] != "guest_restricted" {
		t.Fatalf("code = %v, want \"guest_restricted\"", body["code"])
	}
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_messages WHERE thread_id = $1`, thread).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n != 0 {
		t.Fatalf("chat_messages has %d rows; the refused guest message must not be stored", n)
	}
}
