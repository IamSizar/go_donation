// chat_invite_accept_lifecycle_test.go — can a donor-chat invite still be
// ACCEPTED after the thread it belongs to was paused, ended or archived?
// (OPOS #26413)
//
// # WHY THIS EXISTS
//
// A pending invite outlives the conversation it belongs to. The retirement of
// the direct donor↔owner chat (cmd/retire-direct-chats →
// chatlifecycle.RetireAllDirectThreads) ends AND archives every open direct
// thread, pending ones included, and staff can pause or end any thread from
// the dashboard. The send path has refused such threads since migration 117,
// but POST /api/chats/:id/accept never looked at the lifecycle: it flipped the
// invite to active and pushed the initiator "chat accepted" for a thread
// neither of them could post into, or even open.
//
// Every assertion checks the DATABASE, not just the response: the invite's
// status must stay 'pending', and no "chat_accepted" notification row may
// exist for the initiator. notify.Notifier.Send writes that row before it
// attempts any FCM push, so no row means no push.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_accept_lifecycle
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_accept_lifecycle?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatInviteAccept -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// acceptedPushType is notify.ChatAcceptedMsg's notification_type — the row the
// initiator would receive if an accept went through.
const acceptedPushType = "chat_accepted"

// acceptedPushWait bounds how long the OPEN case waits for the handler's
// background goroutine to write its notification. It is a ceiling, not a
// sleep: the poll returns as soon as the row exists.
const acceptedPushWait = 5 * time.Second

// ─── Fixtures ───────────────────────────────────────────────────────────

// pendingInvite is one seeded donor↔owner invite: the donor asked, the owner
// has not answered yet.
type pendingInvite struct {
	ThreadID  int64
	Initiator int64 // the donor — would receive the "chat accepted" push
	Invitee   int64 // the owner — the only party allowed to accept
}

// seedPendingInvite inserts a pending kind='direct' thread, exactly the shape
// RetireAllDirectThreads selects, and removes it afterwards.
func seedPendingInvite(t *testing.T, pool *pgxpool.Pool) pendingInvite {
	return seedPendingInviteOfKind(t, pool, chat.KindDirect)
}

// seedPendingSupportInvite inserts the same pending thread as a SUPPORT one.
//
// It exists because a pending direct invite can no longer be accepted at all
// (OPOS #25284 — chat.Store.AcceptThread refuses it, pinned by
// chat_direct_kind_gate_test.go). A support thread is the only invite left on
// chat_threads that a successful accept can be demonstrated on, so it is what
// the "the gate must not refuse everything" controls use.
func seedPendingSupportInvite(t *testing.T, pool *pgxpool.Pool) pendingInvite {
	return seedPendingInviteOfKind(t, pool, chat.KindSupport)
}

func seedPendingInviteOfKind(t *testing.T, pool *pgxpool.Pool, kind string) pendingInvite {
	t.Helper()
	donor := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		 VALUES ($1, $2, 'pending', $1, $3) RETURNING id`, donor, owner, kind).Scan(&id); err != nil {
		t.Fatalf("insert pending %s chat thread: %v", kind, err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_threads WHERE id = $1`, id)
	})
	return pendingInvite{ThreadID: id, Initiator: donor, Invitee: owner}
}

// newInviteAcceptRouter mounts accept behind main.go's exact chain for that
// route: the authed group's RequireBearer + RequireApproved, plus
// RequireNotGuest on the route itself.
func newInviteAcceptRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	chatH := NewChatHandler(chat.New(pool), notify.New(pool), pool)
	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(tokens), auth.RequireApproved())
	authed.POST("/chats/:id/accept", auth.RequireNotGuest(), chatH.Accept)
	return r
}

// ─── Assertions against the database ───────────────────────────────────

// inviteStatus reads the consent status the accept must not have changed.
func inviteStatus(t *testing.T, pool *pgxpool.Pool, threadID int64) string {
	t.Helper()
	var status string
	if err := pool.QueryRow(context.Background(),
		`SELECT status FROM chat_threads WHERE id = $1`, threadID).Scan(&status); err != nil {
		t.Fatalf("read thread status: %v", err)
	}
	return status
}

// acceptedPushes counts "chat accepted" notification rows for one user.
func acceptedPushes(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM app_notifications WHERE user_id = $1 AND notification_type = $2`,
		userID, acceptedPushType).Scan(&n); err != nil {
		t.Fatalf("count accepted pushes: %v", err)
	}
	return n
}

// waitForAcceptedPush polls until the handler's background send has written
// the initiator's notification, or fails at the deadline.
func waitForAcceptedPush(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	deadline := time.Now().Add(acceptedPushWait)
	for acceptedPushes(t, pool, userID) == 0 {
		if time.Now().After(deadline) {
			t.Fatalf("no %q notification for user %d within %s", acceptedPushType, userID, acceptedPushWait)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// assertInviteUntouched is the guarantee a refusal must keep: still pending,
// and nobody was told it was accepted. The handler refuses before it starts
// the background send, so a zero here is final, not a race.
func assertInviteUntouched(t *testing.T, pool *pgxpool.Pool, inv pendingInvite) {
	t.Helper()
	if s := inviteStatus(t, pool, inv.ThreadID); s != "pending" {
		t.Fatalf("status = %q after a refused accept, want %q", s, "pending")
	}
	if n := acceptedPushes(t, pool, inv.Initiator); n != 0 {
		t.Fatalf("initiator has %d %q notifications after a refused accept, want 0", n, acceptedPushType)
	}
}

// ─── Paused and ended invites are refused like a send ───────────────────

// TestChatInviteAccept_ClosedThreadRefused pins that accepting a paused or
// ended invite answers with the SAME refusal the send path gives
// (refuseIfNotSendable): 409, code chat_lifecycle_closed, the lifecycle, and
// staff's reason in their own words.
func TestChatInviteAccept_ClosedThreadRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newInviteAcceptRouter(pool)

	cases := []struct {
		state  string
		reason string
	}{
		{chatlifecycle.StateEnded, "Resolved by our team"},
		{chatlifecycle.StatePaused, "Under review by our team"},
	}
	for _, tc := range cases {
		t.Run(tc.state, func(t *testing.T) {
			inv := seedPendingInvite(t, pool)
			setLifecycle(t, pool, "chat_threads", inv.ThreadID, tc.state, tc.reason)

			code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", inv.ThreadID),
				tokenFor(t, pool, inv.Invitee), nil)
			t.Logf("accept on a %s invite: %d %v", tc.state, code, body)

			reason := tc.reason
			want := (&chatlifecycle.SendRefusedError{State: chatlifecycle.State{
				Lifecycle: tc.state, Reason: &reason,
			}}).UserMessage()
			if code != http.StatusConflict {
				t.Fatalf("status = %d, want 409 (body %v)", code, body)
			}
			if body["code"] != chatLifecycleRefusedCode || body["lifecycle"] != tc.state ||
				body["lifecycle_reason"] != tc.reason || body["error"] != want {
				t.Fatalf("body = %v, want the send path's refusal for %q", body, tc.state)
			}
			assertInviteUntouched(t, pool, inv)
		})
	}
}

// TestChatInviteAccept_RetiredInviteRefused reproduces the reported scenario
// with the real transitions cmd/retire-direct-chats applies — END then
// ARCHIVE, through chatlifecycle.Apply — scoped to this one thread so the
// shared test database is not swept. An ended thread is refused as ended even
// though it is also archived, matching what the send path says about it.
func TestChatInviteAccept_RetiredInviteRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newInviteAcceptRouter(pool)
	staff := makeLifecycleUser(t, pool, "admin")
	inv := seedPendingInvite(t, pool)

	ctx := context.Background()
	const reason = "OPOS #25284 Phase 4 — direct donor-owner chat retired"
	for _, action := range []string{chatlifecycle.ActionEnd, chatlifecycle.ActionArchive} {
		if _, err := chatlifecycle.Apply(ctx, pool, chatlifecycle.KindDonor, inv.ThreadID, action, reason, staff); err != nil {
			t.Fatalf("apply %s: %v", action, err)
		}
	}

	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", inv.ThreadID),
		tokenFor(t, pool, inv.Invitee), nil)
	t.Logf("accept on a retired invite: %d %v", code, body)
	if code != http.StatusConflict || body["code"] != chatLifecycleRefusedCode ||
		body["lifecycle"] != chatlifecycle.StateEnded {
		t.Fatalf("status = %d body = %v, want 409 %s/%s", code, body, chatLifecycleRefusedCode, chatlifecycle.StateEnded)
	}
	assertInviteUntouched(t, pool, inv)
}

// ─── Archived but still open ────────────────────────────────────────────

// TestChatInviteAccept_ArchivedOpenInviteRefused covers the one state the send
// gate lets through. Archiving is independent of open/paused/ended
// (chatlifecycle.Apply), so an archived thread CAN be open. The send path
// allows it because staff may still be working it; accepting is a
// participant's action, and an archived thread is hidden from both
// participants — gone from ListThreadsForUser, 404 on its messages route. So
// accept answers the same 404 the participant read path does, and the
// initiator is not pushed to a chat they cannot open.
func TestChatInviteAccept_ArchivedOpenInviteRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newInviteAcceptRouter(pool)
	staff := makeLifecycleUser(t, pool, "admin")
	inv := seedPendingInvite(t, pool)

	st, err := chatlifecycle.Apply(context.Background(), pool, chatlifecycle.KindDonor, inv.ThreadID,
		chatlifecycle.ActionArchive, "", staff)
	if err != nil || st.Lifecycle != chatlifecycle.StateOpen || !st.IsArchived {
		t.Fatalf("archive: state %+v err %v, want archived AND open", st, err)
	}

	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", inv.ThreadID),
		tokenFor(t, pool, inv.Invitee), nil)
	t.Logf("accept on an archived open invite: %d %v", code, body)
	if code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 (body %v)", code, body)
	}
	assertInviteUntouched(t, pool, inv)
}

// ─── The gate must not break or leak ────────────────────────────────────

// TestChatInviteAccept_OpenInviteStillAccepts is the control: without it,
// "every accept is refused" would pass every test above.
//
// On a SUPPORT invite, since a direct one is now refused by kind whatever its
// lifecycle says (see seedPendingSupportInvite). The route, handler and store
// path are the same; only the column differs.
func TestChatInviteAccept_OpenInviteStillAccepts(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newInviteAcceptRouter(pool)
	inv := seedPendingSupportInvite(t, pool)

	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", inv.ThreadID),
		tokenFor(t, pool, inv.Invitee), nil)
	if code != http.StatusOK || body["status"] != "active" {
		t.Fatalf("status = %d body = %v, want 200 active", code, body)
	}
	if s := inviteStatus(t, pool, inv.ThreadID); s != "active" {
		t.Fatalf("stored status = %q, want active", s)
	}
	waitForAcceptedPush(t, pool, inv.Initiator)
}

// TestChatInviteAccept_StrangerLearnsNothing pins the ORDER of the checks.
// The lifecycle refusal carries staff's reason in their own words, so a user
// who is not in the thread must be turned away as a non-participant first,
// never shown the reason by guessing a thread id.
func TestChatInviteAccept_StrangerLearnsNothing(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newInviteAcceptRouter(pool)
	inv := seedPendingInvite(t, pool)
	setLifecycle(t, pool, "chat_threads", inv.ThreadID, chatlifecycle.StateEnded, "Private staff note")

	stranger := makeLifecycleUser(t, pool, "user")
	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", inv.ThreadID),
		tokenFor(t, pool, stranger), nil)
	if code != http.StatusForbidden || body["lifecycle_reason"] != nil || body["code"] != nil {
		t.Fatalf("status = %d body = %v, want a plain 403 with no lifecycle detail", code, body)
	}
	assertInviteUntouched(t, pool, inv)
}
