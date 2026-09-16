// marriage_invite_accept_lifecycle_test.go — can a marriage-chat invite still
// be ACCEPTED after staff paused, ended or archived the thread it belongs to?
// (OPOS #26426, the marriage twin of the donor-chat fix in OPOS #26413)
//
// # WHY THIS EXISTS
//
// Staff approving a meeting request (marriagechat.Store.ApproveMeetingRequest)
// opens a marriage_chat_threads row as 'pending', and the profile owner must
// accept it before anyone can post. While it is still pending, staff can
// pause, end or archive that thread from the dashboard
// (POST /api/admin/marriage/chats/:id/lifecycle). The send path has refused
// paused and ended threads since migration 117, but
// POST /api/marriage/chats/:id/accept never looked at the lifecycle: it
// flipped the invite to active and pushed the requester "marriage chat
// accepted" for a thread neither party could post into or, once archived,
// even open.
//
// Every refusal is checked in the DATABASE, not just in the response: the
// thread's status must stay 'pending', and no "marriage_chat_accepted"
// notification row may exist for the requester. notify.Notifier.Send writes
// that row before it attempts any FCM push, so no row means no push.
//
// The shared harness (newLifecyclePool, makeLifecycleUser, tokenFor, doJSON,
// setLifecycle) lives in chat_lifecycle_test.go; acceptedPushWait lives in
// chat_invite_accept_lifecycle_test.go.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_marriage_accept
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_marriage_accept?sslmode=disable' \
//	  go test ./internal/handlers/ -run MarriageInviteAccept -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"reflect"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// marriageAcceptedPushType is notify.MarriageChatAcceptedMsg's
// notification_type — the row the requester would receive if an accept went
// through.
const marriageAcceptedPushType = "marriage_chat_accepted"

// marriageNotOwnerError is the sentence MarriageChatHandler.chatErr answers
// for marriagechat.ErrNotOwner. It is what a non-owner got before the
// lifecycle gate existed, and what they must still get.
const marriageNotOwnerError = "Only the profile owner can accept or decline."

// ─── Fixtures ───────────────────────────────────────────────────────────

// pendingMarriageInvite is one approved meeting request whose thread the
// profile owner has not answered yet.
type pendingMarriageInvite struct {
	ThreadID  int64
	Requester int64 // asked for the meeting — would receive the "accepted" push
	Owner     int64 // owns the profile — the only party allowed to accept
}

// seedPendingMarriageInvite builds the invite the way production does: a
// profile, a meeting request from another member, and staff APPROVING it
// through marriagechat.Store.ApproveMeetingRequest, which opens the 'pending'
// thread. Everything it wrote is removed afterwards.
func seedPendingMarriageInvite(t *testing.T, pool *pgxpool.Pool) pendingMarriageInvite {
	t.Helper()
	ctx := context.Background()
	requester := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	staff := makeLifecycleUser(t, pool, "admin")
	lifecycleSeq++
	var profileID, requestID, threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code) VALUES ($1, $2) RETURNING id`,
		owner, fmt.Sprintf("MRG-ACC-%d", lifecycleSeq)).Scan(&profileID); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id) VALUES ($1, $2) RETURNING id`,
		requester, profileID).Scan(&requestID); err != nil {
		t.Fatalf("insert meeting request: %v", err)
	}
	// Registered before the approval, so a failed approval still cleans up.
	// Cleanups run last-in-first-out, so this runs before the users go.
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM app_notifications WHERE user_id = ANY($1)`, []int64{requester, owner})
		_, _ = pool.Exec(ctx, `UPDATE marriage_meeting_requests SET thread_id = NULL WHERE id = $1`, requestID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_threads WHERE id = $1`, threadID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_meeting_requests WHERE id = $1`, requestID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})
	thread, _, err := marriagechat.New(pool).ApproveMeetingRequest(ctx, requestID, staff)
	if err != nil {
		t.Fatalf("approve meeting request: %v", err)
	}
	threadID = thread.ID
	if thread.Status != "pending" {
		t.Fatalf("approved thread status = %q, want pending", thread.Status)
	}
	return pendingMarriageInvite{ThreadID: thread.ID, Requester: requester, Owner: owner}
}

// newMarriageAcceptRouter mounts accept, and the participant messages route
// the archived case is compared against, behind main.go's chain for them: the
// authed group's RequireBearer + RequireApproved, plus RequireNotGuest on
// both routes (the messages GET gained it in OPOS #26354).
func newMarriageAcceptRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	h := NewMarriageChatHandler(marriagechat.New(pool), notify.New(pool), pool)
	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(tokens), auth.RequireApproved())
	authed.POST("/marriage/chats/:id/accept", auth.RequireNotGuest(), h.Accept)
	authed.GET("/marriage/chats/:id/messages", auth.RequireNotGuest(), h.Messages)
	return r
}

// acceptMarriageInvite sends the accept for inv's thread as userID.
func acceptMarriageInvite(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, inv pendingMarriageInvite, userID int64) (int, map[string]any) {
	t.Helper()
	return doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/marriage/chats/%d/accept", inv.ThreadID),
		tokenFor(t, pool, userID), nil)
}

// ─── Assertions against the database ───────────────────────────────────

// marriageThreadStatus reads the consent status the accept must not have
// changed.
func marriageThreadStatus(t *testing.T, pool *pgxpool.Pool, threadID int64) string {
	t.Helper()
	var status string
	if err := pool.QueryRow(context.Background(),
		`SELECT status FROM marriage_chat_threads WHERE id = $1`, threadID).Scan(&status); err != nil {
		t.Fatalf("read marriage thread status: %v", err)
	}
	return status
}

// marriageAcceptedPushes counts "marriage chat accepted" notification rows for
// one user.
func marriageAcceptedPushes(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM app_notifications WHERE user_id = $1 AND notification_type = $2`,
		userID, marriageAcceptedPushType).Scan(&n); err != nil {
		t.Fatalf("count marriage accepted pushes: %v", err)
	}
	return n
}

// waitForMarriageAcceptedPush polls until the handler's background send has
// written the requester's notification, or fails at the deadline. The wait is
// a ceiling, not a sleep: it returns as soon as the row exists.
func waitForMarriageAcceptedPush(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	deadline := time.Now().Add(acceptedPushWait)
	for marriageAcceptedPushes(t, pool, userID) == 0 {
		if time.Now().After(deadline) {
			t.Fatalf("no %q notification for user %d within %s", marriageAcceptedPushType, userID, acceptedPushWait)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// assertMarriageInviteUntouched is the guarantee a refusal must keep: still
// pending, and the requester was not told it was accepted. The handler refuses
// before it starts the background send, so a zero here is final, not a race.
func assertMarriageInviteUntouched(t *testing.T, pool *pgxpool.Pool, inv pendingMarriageInvite) {
	t.Helper()
	if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "pending" {
		t.Fatalf("status = %q after a refused accept, want %q", s, "pending")
	}
	if n := marriageAcceptedPushes(t, pool, inv.Requester); n != 0 {
		t.Fatalf("requester has %d %q notifications after a refused accept, want 0", n, marriageAcceptedPushType)
	}
}

// ─── Paused, ended and retired invites are refused like a send ─────────

// TestMarriageInviteAccept_ClosedThreadRefused pins that accepting a paused or
// ended invite answers with the SAME refusal the send path and the donor
// accept give (refuseIfNotSendable): 409, code chat_lifecycle_closed, the
// lifecycle, and staff's reason in their own words.
func TestMarriageInviteAccept_ClosedThreadRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newMarriageAcceptRouter(pool)

	cases := []struct {
		state  string
		reason string
	}{
		{chatlifecycle.StateEnded, "Resolved by our team"},
		{chatlifecycle.StatePaused, "Under review by our team"},
	}
	for _, tc := range cases {
		t.Run(tc.state, func(t *testing.T) {
			inv := seedPendingMarriageInvite(t, pool)
			setLifecycle(t, pool, "marriage_chat_threads", inv.ThreadID, tc.state, tc.reason)

			code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner)
			t.Logf("accept on a %s marriage invite: %d %v", tc.state, code, body)

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
			assertMarriageInviteUntouched(t, pool, inv)
		})
	}
}

// TestMarriageInviteAccept_RetiredInviteRefused covers a thread staff both
// ENDED and ARCHIVED, applied through the real chatlifecycle.Apply transitions
// the dashboard's lifecycle route uses. RetireAllDirectThreads sweeps only
// donor threads, but staff can put a marriage thread into the same state by
// hand. An ended thread is refused as ended even though it is also archived,
// matching what the send path says about it.
func TestMarriageInviteAccept_RetiredInviteRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newMarriageAcceptRouter(pool)
	staff := makeLifecycleUser(t, pool, "admin")
	inv := seedPendingMarriageInvite(t, pool)

	ctx := context.Background()
	const reason = "This introduction has been closed by our team"
	for _, action := range []string{chatlifecycle.ActionEnd, chatlifecycle.ActionArchive} {
		if _, err := chatlifecycle.Apply(ctx, pool, chatlifecycle.KindMarriage, inv.ThreadID, action, reason, staff); err != nil {
			t.Fatalf("apply %s: %v", action, err)
		}
	}

	code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner)
	t.Logf("accept on a retired marriage invite: %d %v", code, body)
	if code != http.StatusConflict || body["code"] != chatLifecycleRefusedCode ||
		body["lifecycle"] != chatlifecycle.StateEnded || body["lifecycle_reason"] != reason {
		t.Fatalf("status = %d body = %v, want 409 %s/%s with the reason", code, body,
			chatLifecycleRefusedCode, chatlifecycle.StateEnded)
	}
	assertMarriageInviteUntouched(t, pool, inv)
}

// ─── Archived but still open ────────────────────────────────────────────

// TestMarriageInviteAccept_ArchivedOpenInviteAnswersLikeMessagesRoute covers
// the one state the send gate lets through. Archiving is independent of
// open/paused/ended, so an archived thread CAN be open. It is hidden from both
// participants (ListThreadsForUser filters archived_at), and the participant
// messages route, GET /api/marriage/chats/:id/messages, answers 404 for it
// through refuseIfArchivedForParticipant. Accept must give the owner that
// exact answer, compared here response to response, and must not push the
// requester to a chat they cannot open.
func TestMarriageInviteAccept_ArchivedOpenInviteAnswersLikeMessagesRoute(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newMarriageAcceptRouter(pool)
	staff := makeLifecycleUser(t, pool, "admin")
	inv := seedPendingMarriageInvite(t, pool)

	st, err := chatlifecycle.Apply(context.Background(), pool, chatlifecycle.KindMarriage, inv.ThreadID,
		chatlifecycle.ActionArchive, "", staff)
	if err != nil || st.Lifecycle != chatlifecycle.StateOpen || !st.IsArchived {
		t.Fatalf("archive: state %+v err %v, want archived AND open", st, err)
	}

	token := tokenFor(t, pool, inv.Owner)
	readCode, readBody := doJSON(t, r, http.MethodGet,
		fmt.Sprintf("/api/marriage/chats/%d/messages", inv.ThreadID), token, nil)
	if readCode != http.StatusNotFound {
		t.Fatalf("messages route on an archived thread = %d %v, want 404; the premise of this test is gone",
			readCode, readBody)
	}

	code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner)
	t.Logf("accept on an archived open marriage invite: %d %v (messages route: %d %v)",
		code, body, readCode, readBody)
	if code != readCode || !reflect.DeepEqual(body, readBody) {
		t.Fatalf("accept = %d %v, want the messages route's %d %v", code, body, readCode, readBody)
	}
	assertMarriageInviteUntouched(t, pool, inv)
}

// ─── The gate must not break or leak ────────────────────────────────────

// TestMarriageInviteAccept_OpenInviteStillAccepts is the control: without it,
// "every accept is refused" would pass every test above.
func TestMarriageInviteAccept_OpenInviteStillAccepts(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newMarriageAcceptRouter(pool)
	inv := seedPendingMarriageInvite(t, pool)

	code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner)
	if code != http.StatusOK || body["status"] != "active" {
		t.Fatalf("status = %d body = %v, want 200 active", code, body)
	}
	if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "active" {
		t.Fatalf("stored status = %q, want active", s)
	}
	waitForMarriageAcceptedPush(t, pool, inv.Requester)
}

// TestMarriageInviteAccept_NonOwnerRefusedAsBefore pins the ORDER of the
// checks. The lifecycle refusal carries staff's reason in their own words, so
// anyone who is not the profile owner must be turned away first with exactly
// the 403 they got before the gate existed. That holds for a stranger guessing
// thread ids and for the requester, who is in the thread but may not accept.
func TestMarriageInviteAccept_NonOwnerRefusedAsBefore(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newMarriageAcceptRouter(pool)

	callers := []struct {
		name   string
		caller func(inv pendingMarriageInvite) int64
	}{
		{"stranger", func(pendingMarriageInvite) int64 { return makeLifecycleUser(t, pool, "user") }},
		{"requester", func(inv pendingMarriageInvite) int64 { return inv.Requester }},
	}
	for _, tc := range callers {
		t.Run(tc.name, func(t *testing.T) {
			inv := seedPendingMarriageInvite(t, pool)
			setLifecycle(t, pool, "marriage_chat_threads", inv.ThreadID, chatlifecycle.StateEnded, "Private staff note")

			code, body := acceptMarriageInvite(t, r, pool, inv, tc.caller(inv))
			if code != http.StatusForbidden || body["error"] != marriageNotOwnerError ||
				body["lifecycle_reason"] != nil || body["code"] != nil {
				t.Fatalf("status = %d body = %v, want the plain 403 %q with no lifecycle detail",
					code, body, marriageNotOwnerError)
			}
			assertMarriageInviteUntouched(t, pool, inv)
		})
	}
}
