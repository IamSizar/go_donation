// chat_contact_block_test.go — does the K19 block actually fire on the write
// path, and does it stay off the two conversations it would break?
//
// # WHY THIS EXISTS SEPARATELY FROM THE FILTER'S OWN TESTS
//
// internal/moderation/contactfilter_test.go proves the DETECTION — which
// strings are contact details and which are donation amounts. It says nothing
// about whether the detector is wired to anything. These tests pin the WIRING,
// and specifically the two exemptions, which are the part most likely to be
// silently broken by a later change:
//
//   - A refused message must leave NO row in chat_messages. That is the whole
//     guarantee: every stored message fans out an 80-character push preview, so
//     "stored but hidden" would still have posted the number off the server.
//   - A SUPPORT thread must be untouched. POST /api/chats/support opens a
//     thread on the same table with a staff account as "owner", and a user
//     giving support their own phone number is the support request itself. A
//     filter that blocked it would look like a bug to every user who hit it.
//   - A STAFF sender must be untouched, because K19 casts the employee as
//     mediator and a mediator relays numbers.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_k19
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k19?sslmode=disable' \
//	  go test ./internal/handlers/ -run ContactBlock -v
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
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// ─── Harness ────────────────────────────────────────────────────────────

func newContactBlockPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping K19 contact-block integration test")
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

// contactBlockSeq keeps the generated phone numbers unique across subtests
// without colliding with whatever else is already in the database.
var contactBlockSeq int

// makeContactUser inserts one user at the given staff tier and removes it
// afterwards. Everything this test writes is removed by its own t.Cleanup —
// the shared test database must be left exactly as it was found.
func makeContactUser(t *testing.T, pool *pgxpool.Pool, tier string) int64 {
	t.Helper()
	ctx := context.Background()
	contactBlockSeq++
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, staff_tier, registration_status)
		 VALUES ($1, 1, 1, $2, 'approved') RETURNING id`,
		fmt.Sprintf("9647719%06d", contactBlockSeq), tier,
	).Scan(&id); err != nil {
		t.Fatalf("insert %s user: %v", tier, err)
	}
	// A profile too, so the thread list has a name to serve. Without one the
	// name comes back NULL for reasons that have nothing to do with K19, and
	// the "name survives, phone does not" assertion would pass vacuously.
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address)
		 VALUES ($1, $2, '', '')`,
		id, fmt.Sprintf("K19 Tester %d", contactBlockSeq),
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

// makeContactThread inserts an ACTIVE thread between two users. Active because
// the block sits downstream of the accept step and this test is not about the
// accept step.
func makeContactThread(t *testing.T, pool *pgxpool.Pool, donorID, ownerID int64) int64 {
	t.Helper()
	ctx := context.Background()
	var id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by)
		 VALUES ($1, $2, 'active', $1) RETURNING id`,
		donorID, ownerID,
	).Scan(&id); err != nil {
		t.Fatalf("insert thread: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		// Children first — chat_contact_blocks cascades from the thread, but
		// being explicit keeps the cleanup correct if that ever changes.
		_, _ = pool.Exec(ctx, `DELETE FROM chat_contact_blocks WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_threads WHERE id = $1`, id)
	})
	return id
}

// newContactBlockRouter wires the mobile send route exactly as main.go does.
func newContactBlockRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	h := NewChatHandler(chat.New(pool), notify.New(pool), pool)
	r := gin.New()
	r.POST("/api/chats/:id/messages",
		auth.RequireBearer(auth.NewTokenStore(pool)), h.PostMessage)
	return r
}

// sendAs posts a message as one user and returns the status and decoded body.
func sendAs(t *testing.T, pool *pgxpool.Pool, r *gin.Engine, userID, threadID int64, body string) (int, map[string]any) {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(context.Background(), userID, "k19-test", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for user %d: %v", userID, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_access_tokens WHERE user_id = $1`, userID)
	})
	payload, _ := json.Marshal(map[string]string{"body": body})
	req := httptest.NewRequest(http.MethodPost,
		fmt.Sprintf("/api/chats/%d/messages", threadID), strings.NewReader(string(payload)))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func countMessages(t *testing.T, pool *pgxpool.Pool, threadID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_messages WHERE thread_id = $1`, threadID).Scan(&n); err != nil {
		t.Fatalf("count messages: %v", err)
	}
	return n
}

// ─── The block itself ───────────────────────────────────────────────────

func TestContactBlock_RefusesAndStoresNothing(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newContactBlockRouter(pool)
	donor := makeContactUser(t, pool, "user")
	owner := makeContactUser(t, pool, "user")
	thread := makeContactThread(t, pool, donor, owner)

	code, body := sendAs(t, pool, r, donor, thread, "call me on 07701234567 please")

	if code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want %d (body %v)", code, http.StatusUnprocessableEntity, body)
	}
	if body["code"] != contactBlockedCode {
		t.Fatalf("code = %v, want %q", body["code"], contactBlockedCode)
	}
	// The guarantee: nothing was stored, so nothing was pushed.
	if n := countMessages(t, pool, thread); n != 0 {
		t.Fatalf("chat_messages has %d rows for the refused message; want 0", n)
	}
	// The supervision record was written, and it does NOT carry the number.
	var kind, redacted string
	if err := pool.QueryRow(context.Background(),
		`SELECT kind, redacted_body FROM chat_contact_blocks WHERE thread_id = $1`, thread,
	).Scan(&kind, &redacted); err != nil {
		t.Fatalf("expected a recorded attempt: %v", err)
	}
	if kind != "phone" {
		t.Fatalf("kind = %q, want \"phone\"", kind)
	}
	if strings.Contains(redacted, "07701234567") {
		t.Fatalf("redacted_body = %q still carries the number", redacted)
	}
}

func TestContactBlock_LetsOrdinaryMessagesThrough(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newContactBlockRouter(pool)
	donor := makeContactUser(t, pool, "user")
	owner := makeContactUser(t, pool, "user")
	thread := makeContactThread(t, pool, donor, owner)

	// A donation amount, a case reference and a date — the exact digit runs a
	// filter must not eat, on the real write path rather than in isolation.
	code, body := sendAs(t, pool, r, donor, thread,
		"I sent 250,000 IQD for case CSE-2026-001 on 2026-08-16")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %v)", code, body)
	}
	if n := countMessages(t, pool, thread); n != 1 {
		t.Fatalf("chat_messages has %d rows; want 1", n)
	}
}

// ─── The two exemptions ─────────────────────────────────────────────────

func TestContactBlock_SupportThreadIsExempt(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newContactBlockRouter(pool)
	user := makeContactUser(t, pool, "user")
	support := makeContactUser(t, pool, "employee") // the support account
	thread := makeContactThread(t, pool, user, support)

	// A user telling SUPPORT their own number is the support request, not an
	// extortion risk. If this ever starts failing, every support conversation
	// that begins "my number is…" is broken.
	code, body := sendAs(t, pool, r, user, thread, "my number is 07701234567, please call me")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — support threads must not be filtered (body %v)", code, body)
	}
	if n := countMessages(t, pool, thread); n != 1 {
		t.Fatalf("chat_messages has %d rows; want 1", n)
	}
}

// ─── The other half of "personal-data blocking": the READ path ──────────

// TestContactBlock_PeerThreadListWithholdsCounterpartPhone pins the hole that
// made the write-path filter pointless on its own.
//
// VERIFICATION_REPORT flagged that the thread list hands each party the other's
// real `phone`. It does — subject only to the counterpart's OWN privacy toggle,
// which is off by default. So while the filter above refuses a message carrying
// a phone number, GET /api/chats was handing the same number over in JSON on
// the row above it. Blocking the exchange while serving the number is not
// protection, it is theatre.
//
// The name is deliberately NOT withheld: the app renders it as the
// conversation title, it is already governed by the K8 privacy system, and
// removing it is a product decision rather than a leak fix. The phone is
// parsed by the app but never displayed, so withholding it costs nothing.
func TestContactBlock_PeerThreadListWithholdsCounterpartPhone(t *testing.T) {
	pool := newContactBlockPool(t)
	donor := makeContactUser(t, pool, "user")
	owner := makeContactUser(t, pool, "user")
	makeContactThread(t, pool, donor, owner)

	views, err := chat.New(pool).ListThreadsForUser(context.Background(), donor)
	if err != nil {
		t.Fatalf("list threads: %v", err)
	}
	if len(views) != 1 {
		t.Fatalf("got %d threads, want 1", len(views))
	}
	if views[0].OtherPhone != nil {
		t.Fatalf("OtherPhone = %q — a supervised peer thread must not hand over the counterpart's number",
			*views[0].OtherPhone)
	}
	// The name must still be there, or the conversation loses its title.
	if views[0].OtherName == nil {
		t.Fatal("OtherName was withheld too; only the phone should be")
	}
}

// A support thread is the counter-case: the counterpart is staff, the thread is
// not the donor↔beneficiary pair K19 covers, and nothing is withheld.
func TestContactBlock_SupportThreadListKeepsStaffPhone(t *testing.T) {
	pool := newContactBlockPool(t)
	user := makeContactUser(t, pool, "user")
	support := makeContactUser(t, pool, "employee")
	makeContactThread(t, pool, user, support)

	views, err := chat.New(pool).ListThreadsForUser(context.Background(), user)
	if err != nil {
		t.Fatalf("list threads: %v", err)
	}
	if len(views) != 1 {
		t.Fatalf("got %d threads, want 1", len(views))
	}
	if views[0].OtherPhone == nil {
		t.Fatal("OtherPhone was withheld on a SUPPORT thread; only peer threads are filtered")
	}
}

func TestContactBlock_StaffSenderIsExempt(t *testing.T) {
	pool := newContactBlockPool(t)
	r := newContactBlockRouter(pool)
	// A staff member who is themselves a party to the thread: K19's mediator,
	// relaying a number on someone's behalf.
	staff := makeContactUser(t, pool, "supervisor")
	owner := makeContactUser(t, pool, "user")
	thread := makeContactThread(t, pool, staff, owner)

	code, body := sendAs(t, pool, r, staff, thread, "The coordinator can be reached on 07701234567")

	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — a staff relay must not be filtered (body %v)", code, body)
	}
	if n := countMessages(t, pool, thread); n != 1 {
		t.Fatalf("chat_messages has %d rows; want 1", n)
	}
}
