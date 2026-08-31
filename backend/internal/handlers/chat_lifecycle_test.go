// chat_lifecycle_test.go — does END and PAUSE actually stop a message being
// stored, in ALL FOUR chat systems, on the SERVER?
//
// # WHY THESE ARE THE TESTS THAT MATTER
//
// The Flutter app hides its composer on a paused or ended chat and the
// dashboard greys out its reply box. Neither is enforcement: both are one
// crafted HTTP request away from being irrelevant. So every assertion here
// goes through the real route with a real token and then checks the DATABASE
// — "was a row written?" — rather than believing the response.
//
// Four systems, four tables, four separate handlers, and the enforcement is
// one shared function. A test per system is what stops the next person wiring
// a fifth chat and forgetting the gate.
//
// The authorization boundary gets its own test: a PARTICIPANT must not be
// able to end, pause, archive or delete their own chat. Only staff may.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chatlifecycle
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chatlifecycle?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatLifecycle -v
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

func newLifecyclePool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping chat lifecycle integration test")
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
	t.Cleanup(pool.Close)
	return pool
}

// lifecycleSeq keeps generated phone numbers unique inside one run.
var lifecycleSeq int

// makeLifecycleUser inserts a user at the given staff tier, with a profile,
// and removes both afterwards — this suite leaves the database as it found it.
func makeLifecycleUser(t *testing.T, pool *pgxpool.Pool, tier string) int64 {
	t.Helper()
	ctx := context.Background()
	lifecycleSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, staff_tier, registration_status)
		 VALUES ($1, 1, 1, $2, 'approved') RETURNING id`,
		fmt.Sprintf("9647733%06d", lifecycleSeq), tier,
	).Scan(&id); err != nil {
		t.Fatalf("insert %s user: %v", tier, err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address) VALUES ($1, $2, '', '')`,
		id, fmt.Sprintf("Lifecycle Tester %d", lifecycleSeq),
	); err != nil {
		t.Fatalf("insert profile: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// tokenFor issues a real bearer token, so every request in this file travels
// the same authentication path production does.
func tokenFor(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(context.Background(), userID, "lifecycle-test", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_access_tokens WHERE user_id = $1`, userID)
	})
	return session.AccessToken
}

// doJSON performs one request and decodes the response.
func doJSON(t *testing.T, r *gin.Engine, method, path, token string, body any) (int, map[string]any) {
	t.Helper()
	var payload string
	if body != nil {
		b, _ := json.Marshal(body)
		payload = string(b)
	}
	req := httptest.NewRequest(method, path, strings.NewReader(payload))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

// countRows is the assertion that actually matters: a refused send must leave
// NOTHING behind, because a stored message is also a pushed notification.
func countRows(t *testing.T, pool *pgxpool.Pool, table string, threadID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM "+table+" WHERE thread_id = $1", threadID).Scan(&n); err != nil {
		t.Fatalf("count %s: %v", table, err)
	}
	return n
}

// setLifecycle drives the state directly, for the tests whose subject is the
// SEND path rather than the transition itself.
func setLifecycle(t *testing.T, pool *pgxpool.Pool, table string, threadID int64, state, reason string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		"UPDATE "+table+" SET lifecycle = $2, lifecycle_reason = $3 WHERE id = $1",
		threadID, state, reason); err != nil {
		t.Fatalf("set %s lifecycle: %v", table, err)
	}
}

// ─── PAUSE and END refuse a send, in all four systems ───────────────────

func TestChatLifecycle_PausedThreadRefusesMessage(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)

	for _, f := range allFixtures(t, pool) {
		t.Run(string(f.Kind), func(t *testing.T) {
			setLifecycle(t, pool, f.ThreadTable, f.ThreadID, chatlifecycle.StatePaused,
				"Under review by our team")

			code, body := doJSON(t, r, http.MethodPost, f.SendPath,
				tokenFor(t, pool, f.SenderID), map[string]string{"body": "hello?"})

			if code != http.StatusConflict {
				t.Fatalf("status = %d, want 409 (body %v)", code, body)
			}
			if body["code"] != chatLifecycleRefusedCode {
				t.Fatalf("code = %v, want %q", body["code"], chatLifecycleRefusedCode)
			}
			// The refusal must say WHY, in the staff member's own words.
			if msg, _ := body["error"].(string); !strings.Contains(msg, "Under review by our team") {
				t.Fatalf("error = %q, expected it to carry the staff reason", msg)
			}
			// Printed so the refusal a user actually receives is visible in
			// the test log, not just asserted about.
			t.Logf("server refusal: %d %v", code, body)
			// The guarantee: nothing stored, so nothing pushed.
			if n := countRows(t, pool, f.MsgTable, f.ThreadID); n != 0 {
				t.Fatalf("%s has %d rows after a refused send; want 0", f.MsgTable, n)
			}
		})
	}
}

func TestChatLifecycle_EndedThreadRefusesMessage(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)

	for _, f := range allFixtures(t, pool) {
		t.Run(string(f.Kind), func(t *testing.T) {
			setLifecycle(t, pool, f.ThreadTable, f.ThreadID, chatlifecycle.StateEnded, "")

			code, body := doJSON(t, r, http.MethodPost, f.SendPath,
				tokenFor(t, pool, f.SenderID), map[string]string{"body": "one more thing"})

			if code != http.StatusConflict {
				t.Fatalf("status = %d, want 409 (body %v)", code, body)
			}
			if body["lifecycle"] != chatlifecycle.StateEnded {
				t.Fatalf("lifecycle = %v, want %q", body["lifecycle"], chatlifecycle.StateEnded)
			}
			if n := countRows(t, pool, f.MsgTable, f.ThreadID); n != 0 {
				t.Fatalf("%s has %d rows after a refused send; want 0", f.MsgTable, n)
			}
		})
	}
}

// An OPEN thread must behave exactly as it did before any of this existed.
// Without this, "everything is refused" would pass the two tests above.
func TestChatLifecycle_OpenThreadStillWorks(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)

	for _, f := range allFixtures(t, pool) {
		t.Run(string(f.Kind), func(t *testing.T) {
			code, body := doJSON(t, r, http.MethodPost, f.SendPath,
				tokenFor(t, pool, f.SenderID), map[string]string{"body": "a perfectly ordinary message"})
			if code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %v)", code, body)
			}
			if n := countRows(t, pool, f.MsgTable, f.ThreadID); n != 1 {
				t.Fatalf("%s has %d rows; want 1", f.MsgTable, n)
			}
		})
	}
}

// ─── Resume, and the finality of END ────────────────────────────────────

func TestChatLifecycle_ResumeRestoresAPausedChat(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staff := makeLifecycleUser(t, pool, "admin")
	staffToken := tokenFor(t, pool, staff)
	f := seedDonorChat(t, pool)

	// Pause through the real staff route, not by hand.
	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/admin/chats/%d/lifecycle", f.ThreadID),
		staffToken, map[string]string{"action": "pause", "reason": "cooling off"})
	if code != http.StatusOK || body["lifecycle"] != chatlifecycle.StatePaused {
		t.Fatalf("pause: status %d body %v", code, body)
	}
	if code, _ := doJSON(t, r, http.MethodPost, f.SendPath, tokenFor(t, pool, f.SenderID),
		map[string]string{"body": "hi"}); code != http.StatusConflict {
		t.Fatalf("paused send status = %d, want 409", code)
	}

	// Resume, and the thread works again.
	code, body = doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/admin/chats/%d/lifecycle", f.ThreadID),
		staffToken, map[string]string{"action": "resume"})
	if code != http.StatusOK || body["lifecycle"] != chatlifecycle.StateOpen {
		t.Fatalf("resume: status %d body %v", code, body)
	}
	// Resuming clears the reason — the explanation belonged to the pause.
	if body["reason"] != nil {
		t.Fatalf("reason = %v after resume, want null", body["reason"])
	}
	if code, body := doJSON(t, r, http.MethodPost, f.SendPath, tokenFor(t, pool, f.SenderID),
		map[string]string{"body": "we are back"}); code != http.StatusOK {
		t.Fatalf("resumed send status = %d, want 200 (body %v)", code, body)
	}
	if n := countRows(t, pool, f.MsgTable, f.ThreadID); n != 1 {
		t.Fatalf("chat_messages = %d, want the one message sent after resume", n)
	}
}

func TestChatLifecycle_EndedChatCannotBeResumed(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staffToken := tokenFor(t, pool, makeLifecycleUser(t, pool, "admin"))
	f := seedDonorChat(t, pool)
	path := fmt.Sprintf("/api/admin/chats/%d/lifecycle", f.ThreadID)

	if code, body := doJSON(t, r, http.MethodPost, path, staffToken,
		map[string]string{"action": "end", "reason": "resolved"}); code != http.StatusOK {
		t.Fatalf("end: status %d body %v", code, body)
	}
	// END is final by the owner's decision: there is no way back.
	code, body := doJSON(t, r, http.MethodPost, path, staffToken, map[string]string{"action": "resume"})
	if code != http.StatusConflict {
		t.Fatalf("resume-after-end status = %d, want 409 (body %v)", code, body)
	}
	var state string
	if err := pool.QueryRow(context.Background(),
		`SELECT lifecycle FROM chat_threads WHERE id = $1`, f.ThreadID).Scan(&state); err != nil {
		t.Fatalf("read lifecycle: %v", err)
	}
	if state != chatlifecycle.StateEnded {
		t.Fatalf("lifecycle = %q after a refused resume, want %q", state, chatlifecycle.StateEnded)
	}
}

// Ending must not destroy history — the whole point of END over DELETE.
func TestChatLifecycle_EndKeepsTheHistory(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)
	staffToken := tokenFor(t, pool, makeLifecycleUser(t, pool, "admin"))
	f := seedDonorChat(t, pool)

	if code, _ := doJSON(t, r, http.MethodPost, f.SendPath, tokenFor(t, pool, f.SenderID),
		map[string]string{"body": "something worth keeping"}); code != http.StatusOK {
		t.Fatalf("seed message failed")
	}
	if code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/admin/chats/%d/lifecycle", f.ThreadID),
		staffToken, map[string]string{"action": "end"}); code != http.StatusOK {
		t.Fatalf("end: status %d body %v", code, body)
	}
	if n := countRows(t, pool, "chat_messages", f.ThreadID); n != 1 {
		t.Fatalf("chat_messages = %d after END; ending must not delete history", n)
	}
}

// ─── The authorization boundary: participants are not moderators ────────

// TestChatLifecycle_ParticipantCannotModerate is the test the whole design
// rests on. A donor is a real, authenticated user with a valid token and is
// unambiguously a party to this conversation — and still may not end, pause,
// archive or delete it. Only staff may, in every one of the four systems.
func TestChatLifecycle_ParticipantCannotModerate(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newLifecycleRouter(pool)

	for _, f := range allFixtures(t, pool) {
		t.Run(string(f.Kind), func(t *testing.T) {
			participant := f.SenderID
			if f.Kind == chatlifecycle.KindStaff {
				// The staff chat's participants ARE staff, so "a participant"
				// is not a meaningful test there — an ordinary app user is.
				participant = makeLifecycleUser(t, pool, "user")
			}
			token := tokenFor(t, pool, participant)
			base := map[chatlifecycle.Kind]string{
				chatlifecycle.KindDonor:    "/api/admin/chats/%d",
				chatlifecycle.KindMarriage: "/api/admin/marriage/chats/%d",
				chatlifecycle.KindStaff:    "/api/admin/staff-chats/%d",
				chatlifecycle.KindCase:     "/api/admin/case-chats/%d",
			}[f.Kind]
			path := fmt.Sprintf(base, f.ThreadID)

			for _, action := range []string{"end", "pause", "archive", "unarchive"} {
				code, body := doJSON(t, r, http.MethodPost, path+"/lifecycle", token,
					map[string]string{"action": action})
				if code != http.StatusUnauthorized && code != http.StatusForbidden {
					t.Fatalf("%s by a participant returned %d, want 401/403 (body %v)", action, code, body)
				}
			}
			code, body := doJSON(t, r, http.MethodDelete, path, token, nil)
			if code != http.StatusUnauthorized && code != http.StatusForbidden {
				t.Fatalf("delete by a participant returned %d, want 401/403 (body %v)", code, body)
			}
			// And none of it changed anything.
			var state string
			var archived *string
			if err := pool.QueryRow(context.Background(),
				"SELECT lifecycle, archived_at::text FROM "+f.ThreadTable+" WHERE id = $1",
				f.ThreadID).Scan(&state, &archived); err != nil {
				t.Fatalf("thread should still exist: %v", err)
			}
			if state != chatlifecycle.StateOpen || archived != nil {
				t.Fatalf("participant moved the thread to lifecycle=%q archived=%v", state, archived)
			}
		})
	}
}
