// Package handlers tests — the volunteer-signup delete and its conversation.
//
// DELETE /api/admin/volunteer_mission_signups/:id routes through trashRow,
// which snapshots the ROW into trash_items and then runs a real DELETE. The
// signup's ON DELETE CASCADE children are not in that snapshot:
//
//	volunteer_mission_signups
//	  └─ case_volunteer_chat_threads   (061, signup_id ... ON DELETE CASCADE)
//	       ├─ case_volunteer_chat_messages
//	       └─ case_volunteer_chat_reads
//
// So a delete used to take the whole Staff↔Volunteer↔Beneficiary conversation
// with it, and المهملات would hand back the signup alone — silent data loss
// with a Trash entry on top of it, which is worse than no Trash entry, because
// the operator has been told the action is undoable.
//
// The rule pinned here: a delete must never silently destroy messages.
//
// Integration tests; they skip unless TEST_DATABASE_URL is set, so
// `go test ./...` stays green on a bare checkout:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test -p 1 ./internal/handlers/ -run SignupDelete
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixtures ───────────────────────────────────────────────────────────

// signupChatFixture is one complete conversation: a volunteer, a beneficiary
// who owns a case, a mission, the signup joining them, and a chat thread.
type signupChatFixture struct {
	signupID int64
	threadID int64
	caseID   int64
}

// makeSignupWithThread builds the fixture. `messages` is how many chat
// messages to put in the thread — 0 produces the empty thread that
// EnsureThreadForSignup opens automatically the moment a signup is approved,
// which is the case that must STILL be deletable.
func makeSignupWithThread(t *testing.T, pool *pgxpool.Pool, messages int) signupChatFixture {
	t.Helper()
	ctx := context.Background()

	volunteer := insertAccount(t, pool, "user", "")
	beneficiary := insertAccount(t, pool, "user", "")

	var missionID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_missions (title, status)
		 VALUES ('signup-delete guard fixture', 'open') RETURNING id`,
	).Scan(&missionID); err != nil {
		t.Fatalf("insert mission: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM volunteer_missions WHERE id = $1`, missionID)
	})

	var caseID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO beneficiary_cases (user_id, case_code, public_title,
		                                verification_status, public_visibility)
		 VALUES ($1, $2, 'signup-delete guard fixture', 'approved', 'summary')
		 RETURNING id`, beneficiary.id, fmt.Sprintf("SIGNUP-GUARD-%d", missionID),
	).Scan(&caseID); err != nil {
		t.Fatalf("insert beneficiary case: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM beneficiary_cases WHERE id = $1`, caseID)
	})

	var signupID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_mission_signups
		   (user_id, mission_id, beneficiary_case_id, status, notes)
		 VALUES ($1, $2, $3, 'approved', 'guard fixture') RETURNING id`,
		volunteer.id, missionID, caseID,
	).Scan(&signupID); err != nil {
		t.Fatalf("insert signup: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		// A test that trashes the signup leaves a trash_items row behind, and
		// nothing else would ever remove it — repeat runs would silently grow
		// the Trash of whatever database TEST_DATABASE_URL points at. Mirrors
		// the cleanup in admin_delete_trash_test.go.
		_, _ = pool.Exec(bg,
			`DELETE FROM trash_items WHERE source_table = 'volunteer_mission_signups' AND row_id = $1`, signupID)
		_, _ = pool.Exec(bg, `DELETE FROM volunteer_mission_signups WHERE id = $1`, signupID)
	})

	var threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO case_volunteer_chat_threads
		   (signup_id, case_id, volunteer_user_id, beneficiary_user_id)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		signupID, caseID, volunteer.id, beneficiary.id,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert chat thread: %v", err)
	}

	for i := 0; i < messages; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO case_volunteer_chat_messages (thread_id, sender_user_id, sender_role, body)
			 VALUES ($1, $2, 'volunteer', $3)`,
			threadID, volunteer.id, "message worth keeping",
		); err != nil {
			t.Fatalf("insert chat message: %v", err)
		}
	}

	return signupChatFixture{signupID: signupID, threadID: threadID, caseID: caseID}
}

// countCaseVolMessages reports how many messages survive in the thread.
func countCaseVolMessages(t *testing.T, pool *pgxpool.Pool, threadID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM case_volunteer_chat_messages WHERE thread_id = $1`,
		threadID).Scan(&n); err != nil {
		t.Fatalf("count messages: %v", err)
	}
	return n
}

// ─── The rule ───────────────────────────────────────────────────────────

// TestSignupDeleteRefusesWhenTheConversationHasMessages is the regression that
// matters. Before the guard, this delete returned 200 "trashed": true and the
// three messages were gone from the database for good.
func TestSignupDeleteRefusesWhenTheConversationHasMessages(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeSignupWithThread(t, pool, 3)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).VolunteerMissionSignup, f.signupID)

	if status != http.StatusConflict {
		t.Errorf("status = %d, want 409 — a delete that destroys a conversation must be refused (body: %s)", status, body)
	}

	// The refusal is worthless if the row went anyway.
	var signupStillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM volunteer_mission_signups WHERE id = $1)`,
		f.signupID).Scan(&signupStillThere); err != nil {
		t.Fatalf("check signup: %v", err)
	}
	if !signupStillThere {
		t.Error("the signup was deleted despite the refusal")
	}
	if n := countCaseVolMessages(t, pool, f.threadID); n != 3 {
		t.Errorf("%d of 3 messages survived — the conversation was destroyed", n)
	}

	// Nothing may reach the Trash either: an entry there tells the operator the
	// row is recoverable, and this one was never deleted.
	if n := trashCountFor(t, pool, "volunteer_mission_signups", f.signupID); n != 0 {
		t.Errorf("%d trash entries for a refused delete, want 0", n)
	}
}

// TestSignupDeleteRefusalTellsTheOperatorWhy — a refusal the operator cannot
// act on is a dead end. The body must carry a stable machine `code` so the
// dashboard can render the reason in the operator's own language (the Arabic
// dashboard shows no English), and it must say how much is at stake.
func TestSignupDeleteRefusalTellsTheOperatorWhy(t *testing.T) {
	pool := newAuthTestPool(t)

	f := makeSignupWithThread(t, pool, 2)

	_, body := callDelete(t, NewAdminDeleteHandler(pool).VolunteerMissionSignup, f.signupID)

	var resp struct {
		Success  bool   `json:"success"`
		Error    string `json:"error"`
		Code     string `json:"code"`
		Messages int    `json:"messages"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("unmarshal refusal body %q: %v", body, err)
	}
	if resp.Success {
		t.Error("success = true on a refused delete")
	}
	if resp.Code != "signup_has_chat_history" {
		t.Errorf("code = %q, want signup_has_chat_history — the dashboard keys its localised message off this", resp.Code)
	}
	if resp.Messages != 2 {
		t.Errorf("messages = %d, want 2 — the operator needs to know how much would be lost", resp.Messages)
	}
	if resp.Error == "" {
		t.Error("no fallback message; a client without the code mapping would show nothing")
	}
}

// TestSignupDeleteStillWorksWithNoConversation guards the opposite failure,
// and it is not a hypothetical one: casevolchat.EnsureThreadForSignup opens a
// thread automatically the moment a signup with a linked case is approved.
// Refusing on the mere EXISTENCE of a thread would therefore have made nearly
// every approved signup permanently undeletable — a much bigger regression
// than the bug being fixed.
//
// The rule is about MESSAGES, so an empty thread must not block anything.
func TestSignupDeleteStillWorksWithNoConversation(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeSignupWithThread(t, pool, 0)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).VolunteerMissionSignup, f.signupID)

	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — an empty thread has no conversation to protect (body: %s)", status, body)
	}
	var stillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM volunteer_mission_signups WHERE id = $1)`,
		f.signupID).Scan(&stillThere); err != nil {
		t.Fatalf("check signup: %v", err)
	}
	if stillThere {
		t.Error("the signup was not deleted")
	}
	if n := trashCountFor(t, pool, "volunteer_mission_signups", f.signupID); n != 1 {
		t.Errorf("%d trash entries, want 1 — the delete must stay recoverable", n)
	}
}

// TestSignupDeleteStillWorksWithNoThreadAtAll — the plain case: a signup that
// was never linked to a beneficiary case has no thread row of any kind. It
// must delete exactly as it did before this guard existed.
func TestSignupDeleteStillWorksWithNoThreadAtAll(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	volunteer := insertAccount(t, pool, "user", "")
	var missionID, signupID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_missions (title, status)
		 VALUES ('no-thread fixture', 'open') RETURNING id`).Scan(&missionID); err != nil {
		t.Fatalf("insert mission: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM volunteer_missions WHERE id = $1`, missionID)
	})
	if err := pool.QueryRow(ctx,
		`INSERT INTO volunteer_mission_signups (user_id, mission_id, status, notes)
		 VALUES ($1, $2, 'pending', 'no-thread fixture') RETURNING id`,
		volunteer.id, missionID).Scan(&signupID); err != nil {
		t.Fatalf("insert signup: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg,
			`DELETE FROM trash_items WHERE source_table = 'volunteer_mission_signups' AND row_id = $1`, signupID)
		_, _ = pool.Exec(bg, `DELETE FROM volunteer_mission_signups WHERE id = $1`, signupID)
	})

	status, body := callDelete(t, NewAdminDeleteHandler(pool).VolunteerMissionSignup, signupID)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %s)", status, body)
	}
	if n := trashCountFor(t, pool, "volunteer_mission_signups", signupID); n != 1 {
		t.Errorf("%d trash entries, want 1", n)
	}
}
