// Package handlers tests — the account delete and the records it took with it.
//
// DELETE /api/admin/users/:id routes through trashRow, which snapshots the
// `users` ROW into trash_items and then runs a real DELETE. Everything hanging
// off that row by ON DELETE CASCADE is destroyed and is NOT in the snapshot —
// read out of the live database, not guessed from the migrations:
//
//	users
//	  ├─ chat_threads (donor_user_id / owner_user_id / initiated_by)
//	  │    └─ chat_messages, chat_reads
//	  ├─ marriage_chat_threads / staff_chat_threads / case_volunteer_chat_threads
//	  │    └─ …_messages, …_reads
//	  ├─ wallet_transactions          ← the money the account holds
//	  └─ marriage_subscription_purchases
//
// So one mis-click on a Super-Admin's Delete button destroyed every
// conversation the person was part of and their whole wallet ledger, and
// المهملات then offered a restore that brings back the `users` row alone.
//
// The rule pinned here is the one ee50aae established for volunteer signups: a
// delete must never silently destroy records that cannot be reconstructed —
// and the guard must key off evidence that something would ACTUALLY be lost,
// never off the mere existence of a child row, or the account rows every user
// gets automatically (user_profiles, notification_preferences) would make
// every account permanently undeletable.
//
// Integration tests; they skip unless TEST_DATABASE_URL is set, so
// `go test ./...` stays green on a bare checkout:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test -p 1 ./internal/handlers/ -run UserDelete
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixtures ───────────────────────────────────────────────────────────

// userRecordsFixture is one account plus the things a delete would cascade.
type userRecordsFixture struct {
	userID   int64
	threadID int64
}

// makeUserWithRecords builds an account that holds `messages` chat messages in
// a donor↔owner thread and `walletRows` wallet transactions.
//
// Both counts can be 0, which is the account that must STILL be deletable.
func makeUserWithRecords(t *testing.T, pool *pgxpool.Pool, messages, walletRows int) userRecordsFixture {
	t.Helper()
	ctx := context.Background()

	victim := insertAccount(t, pool, "user", "")
	other := insertAccount(t, pool, "user", "")

	// Every account gets these two the moment it is used; they are not
	// evidence of anything and must never block a delete on their own.
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address)
		 VALUES ($1, 'records guard fixture', 'male', 'Mosul')`, victim.id); err != nil {
		t.Fatalf("insert user profile: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO notification_preferences (user_id, category) VALUES ($1, 'general')`,
		victim.id); err != nil {
		t.Fatalf("insert notification preference: %v", err)
	}

	var threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, initiated_by)
		 VALUES ($1, $2, $1) RETURNING id`, victim.id, other.id,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert chat thread: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_threads WHERE id = $1`, threadID)
	})

	for i := 0; i < messages; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO chat_messages (thread_id, sender_user_id, body)
			 VALUES ($1, $2, 'message worth keeping')`, threadID, victim.id); err != nil {
			t.Fatalf("insert chat message: %v", err)
		}
	}
	for i := 0; i < walletRows; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO wallet_transactions (user_id, amount_iqd, type, note)
			 VALUES ($1, 25000, 'topup', 'records guard fixture')`, victim.id); err != nil {
			t.Fatalf("insert wallet transaction: %v", err)
		}
	}

	t.Cleanup(func() {
		bg := context.Background()
		// A test that trashes the account leaves a trash_items row behind and
		// nothing else would ever remove it — repeat runs would silently grow
		// the Trash of whatever database TEST_DATABASE_URL points at.
		_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'users' AND row_id = $1`, victim.id)
		_, _ = pool.Exec(bg, `DELETE FROM wallet_transactions WHERE user_id = $1`, victim.id)
		_, _ = pool.Exec(bg, `DELETE FROM notification_preferences WHERE user_id = $1`, victim.id)
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, victim.id)
	})

	return userRecordsFixture{userID: victim.id, threadID: threadID}
}

// countChatMessages reports how many messages survive in the thread.
func countChatMessages(t *testing.T, pool *pgxpool.Pool, threadID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM chat_messages WHERE thread_id = $1`, threadID).Scan(&n); err != nil {
		t.Fatalf("count chat messages: %v", err)
	}
	return n
}

// countWalletTransactions reports how much of the account's ledger survives.
func countWalletTransactions(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM wallet_transactions WHERE user_id = $1`, userID).Scan(&n); err != nil {
		t.Fatalf("count wallet transactions: %v", err)
	}
	return n
}

// ─── The rule ───────────────────────────────────────────────────────────

// TestUserDeleteRefusesWhenItWouldDestroyRecords is the regression that
// matters. Before the guard this delete answered 200 "trashed": true, and the
// conversation and the ledger were gone from the database for good.
func TestUserDeleteRefusesWhenItWouldDestroyRecords(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeUserWithRecords(t, pool, 3, 2)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).User, f.userID)

	if status != http.StatusConflict {
		t.Errorf("status = %d, want 409 — a delete that destroys a conversation and a wallet ledger must be refused (body: %s)", status, body)
	}

	// The refusal is worthless if the row went anyway.
	var accountStillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, f.userID).Scan(&accountStillThere); err != nil {
		t.Fatalf("check account: %v", err)
	}
	if !accountStillThere {
		t.Error("the account was deleted despite the refusal")
	}
	if n := countChatMessages(t, pool, f.threadID); n != 3 {
		t.Errorf("%d of 3 messages survived — the conversation was destroyed", n)
	}
	if n := countWalletTransactions(t, pool, f.userID); n != 2 {
		t.Errorf("%d of 2 wallet transactions survived — the money ledger was destroyed", n)
	}

	// Nothing may reach the Trash either: an entry there tells the operator the
	// row is recoverable, and a restore would return the account alone.
	if n := trashCountFor(t, pool, "users", f.userID); n != 0 {
		t.Errorf("%d trash entries for a refused delete, want 0", n)
	}
}

// TestUserDeleteRefusalTellsTheOperatorWhy — a refusal the operator cannot act
// on is a dead end. The body must carry a stable machine `code` so the Arabic
// dashboard renders Arabic, and it must say how much is at stake.
func TestUserDeleteRefusalTellsTheOperatorWhy(t *testing.T) {
	pool := newAuthTestPool(t)

	f := makeUserWithRecords(t, pool, 2, 1)

	_, body := callDelete(t, NewAdminDeleteHandler(pool).User, f.userID)

	var resp struct {
		Success            bool   `json:"success"`
		Error              string `json:"error"`
		Code               string `json:"code"`
		Messages           int    `json:"messages"`
		WalletTransactions int    `json:"wallet_transactions"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("unmarshal refusal body %q: %v", body, err)
	}
	if resp.Success {
		t.Error("success = true on a refused delete")
	}
	if resp.Code != "user_has_records" {
		t.Errorf("code = %q, want user_has_records — the dashboard keys its localised message off this", resp.Code)
	}
	if resp.Messages != 2 {
		t.Errorf("messages = %d, want 2 — the operator needs to know how much would be lost", resp.Messages)
	}
	if resp.WalletTransactions != 1 {
		t.Errorf("wallet_transactions = %d, want 1", resp.WalletTransactions)
	}
	if resp.Error == "" {
		t.Error("no fallback message; a client without the code mapping would show nothing")
	}
}

// TestUserDeleteStillWorksForAnAccountWithNothingToLose guards the opposite
// failure, and it is the reason the guard counts records rather than children:
// user_profiles and notification_preferences are created for every account
// that is ever used, so refusing on the existence of a cascade child would
// have made every account permanently undeletable — a far bigger regression
// than the bug. An account that holds no conversation and no money still goes
// to the Trash exactly as before.
func TestUserDeleteStillWorksForAnAccountWithNothingToLose(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeUserWithRecords(t, pool, 0, 0)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).User, f.userID)

	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — an account with nothing to lose must still be deletable (body: %s)", status, body)
	}
	var stillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, f.userID).Scan(&stillThere); err != nil {
		t.Fatalf("check account: %v", err)
	}
	if stillThere {
		t.Error("the account was not deleted")
	}
	if n := trashCountFor(t, pool, "users", f.userID); n != 1 {
		t.Errorf("%d trash entries, want 1 — the delete must stay recoverable", n)
	}
}
