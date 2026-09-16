// chat_accept_declined_test.go — AcceptThread must refuse a DECLINED invite, at
// the store layer (OPOS #26436).
//
// The HTTP half, which also covers the marriage chat and its re-invite path,
// is internal/handlers/chat_invite_accept_declined_test.go. This file pins the
// store contract a future caller relies on:
//   - a declined invite comes back as ErrInviteDeclined, with its status
//     untouched and no initiator id, so no caller pushes "chat accepted";
//   - a pending invite accepts and returns the initiator to notify;
//   - an already active thread is still an idempotent success.
//
// Donor direct chats cannot be requested again (RequestThread answers
// ErrDirectChatRetired), so for this store a declined invite is final.
//
// The fixtures (seedDeclineThread, storedStatus) live in
// chat_decline_pending_test.go.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_chat
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_chat?sslmode=disable' \
//	  go test ./internal/chat/ -run AcceptThread -v
package chat

import (
	"context"
	"errors"
	"testing"
)

// TestAcceptThreadRefusesDeclinedInvite is the bug at the store layer: the
// recipient accepting an invite they declined must get ErrInviteDeclined, not
// a silent flip back to active.
func TestAcceptThreadRefusesDeclinedInvite(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	threadID, recipient := seedDeclineThread(t, pool, "declined")

	_, initiator, err := s.AcceptThread(context.Background(), threadID, recipient)
	if !errors.Is(err, ErrInviteDeclined) {
		t.Errorf("err = %v, want ErrInviteDeclined", err)
	}
	if initiator != 0 {
		t.Errorf("initiator = %d, want 0 so no caller notifies anyone", initiator)
	}
	if got := storedStatus(t, pool, threadID); got != "declined" {
		t.Errorf("stored status = %q, want declined", got)
	}
}

// TestAcceptThreadAcceptsPendingInvite is the control for the test above.
func TestAcceptThreadAcceptsPendingInvite(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	threadID, recipient := seedDeclineThread(t, pool, "pending")

	th, initiator, err := s.AcceptThread(context.Background(), threadID, recipient)
	if err != nil || th.Status != "active" {
		t.Fatalf("thread = %+v err = %v, want status active and no error", th, err)
	}
	if initiator == 0 || initiator != th.InitiatedBy {
		t.Errorf("initiator = %d, want the thread's initiator %d", initiator, th.InitiatedBy)
	}
	if got := storedStatus(t, pool, threadID); got != "active" {
		t.Errorf("stored status = %q, want active", got)
	}
}

// TestAcceptThreadIsIdempotentOnActiveThread pins that a repeated accept on an
// active thread is still a success, as it was before the status condition.
func TestAcceptThreadIsIdempotentOnActiveThread(t *testing.T) {
	pool := newTestPool(t)
	s := New(pool)
	threadID, recipient := seedDeclineThread(t, pool, "active")

	th, initiator, err := s.AcceptThread(context.Background(), threadID, recipient)
	if err != nil || th.Status != "active" {
		t.Fatalf("thread = %+v err = %v, want status active and no error", th, err)
	}
	if initiator == 0 || initiator != th.InitiatedBy {
		t.Errorf("initiator = %d, want the thread's initiator %d", initiator, th.InitiatedBy)
	}
}
