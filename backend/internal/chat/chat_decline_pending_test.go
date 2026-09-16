// chat_decline_pending_test.go — DeclineThread must refuse a thread that is
// already active, at the store layer (OPOS #26427).
//
// The HTTP half, which also covers the marriage chat, is
// internal/handlers/chat_invite_decline_pending_test.go. This file pins the
// store contract a future caller relies on: an active thread comes back as
// ErrNotPending with its status untouched, a pending invite declines, and an
// already-declined invite declines again without error.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chat
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chat?sslmode=disable' \
//	  go test ./internal/chat/ -run DeclineThread -v
package chat

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// seedDeclineThread inserts a donor-initiated direct thread with the given
// status and removes it afterwards. It returns the thread id and the owner,
// who as the non-initiator is the only party allowed to decline.
//
// Declining is not gated on kind — a user may always dismiss an invite — so
// these fixtures stay 'direct'. ACCEPTING is gated (OPOS #25284), which is why
// chat_accept_declined_test.go asks for KindSupport instead.
func seedDeclineThread(t *testing.T, pool *pgxpool.Pool, status string) (threadID, recipient int64) {
	return seedDeclineThreadOfKind(t, pool, KindDirect, status)
}

// seedDeclineThreadOfKind is seedDeclineThread with the thread's kind spelled
// out, for the tests whose subject is a path kind decides.
func seedDeclineThreadOfKind(t *testing.T, pool *pgxpool.Pool, kind, status string) (threadID, recipient int64) {
	t.Helper()
	donor := makeTestUser(t, pool, "donor")
	owner := makeTestUser(t, pool, "owner")
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		 VALUES ($1, $2, $3, $1, $4) RETURNING id`, donor, owner, status, kind).Scan(&threadID); err != nil {
		t.Fatalf("insert %s/%s thread: %v", kind, status, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM chat_threads WHERE id = $1`, threadID)
	})
	return threadID, owner
}

// storedStatus reads a thread's status straight from the table.
func storedStatus(t *testing.T, pool *pgxpool.Pool, threadID int64) string {
	t.Helper()
	var status string
	if err := pool.QueryRow(context.Background(),
		`SELECT status FROM chat_threads WHERE id = $1`, threadID).Scan(&status); err != nil {
		t.Fatalf("read status: %v", err)
	}
	return status
}

// TestDeclineThreadRefusesActiveThread is the bug at the store layer: the
// recipient declining an active chat must get ErrNotPending, not a silent
// status flip that ends the conversation.
func TestDeclineThreadRefusesActiveThread(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	threadID, recipient := seedDeclineThread(t, pool, "active")

	_, err := s.DeclineThread(context.Background(), threadID, recipient)
	if !errors.Is(err, ErrNotPending) {
		t.Errorf("err = %v, want ErrNotPending", err)
	}
	if got := storedStatus(t, pool, threadID); got != "active" {
		t.Errorf("stored status = %q, want active", got)
	}
}

// TestDeclineThreadDeclinesPendingInvite is the control for the test above.
func TestDeclineThreadDeclinesPendingInvite(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	threadID, recipient := seedDeclineThread(t, pool, "pending")

	th, err := s.DeclineThread(context.Background(), threadID, recipient)
	if err != nil || th.Status != "declined" {
		t.Fatalf("thread = %+v err = %v, want status declined and no error", th, err)
	}
	if got := storedStatus(t, pool, threadID); got != "declined" {
		t.Errorf("stored status = %q, want declined", got)
	}
}

// TestDeclineThreadIsIdempotentForDeclinedInvite pins that declining twice is
// not an error, as it never was.
func TestDeclineThreadIsIdempotentForDeclinedInvite(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	threadID, recipient := seedDeclineThread(t, pool, "declined")

	th, err := s.DeclineThread(context.Background(), threadID, recipient)
	if err != nil || th.Status != "declined" {
		t.Fatalf("thread = %+v err = %v, want status declined and no error", th, err)
	}
}
