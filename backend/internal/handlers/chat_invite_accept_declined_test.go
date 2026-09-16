// chat_invite_accept_declined_test.go — can a DECLINED chat invite still be
// accepted, and does asking again start a fresh one? (OPOS #26436)
//
// # WHY THIS EXISTS
//
// Both accept stores — chat.Store.AcceptThread (donor chat) and
// marriagechat.Store.AcceptThread (marriage chat) — flipped the thread to
// 'active' with no status condition. A recipient who had declined an invite
// could accept it later: the thread came back to life and the initiator was
// pushed "chat accepted" for a request they had been told was turned down.
//
// The owner's decision (2026-09-15) was "make it decline and re invite
// behavior": a declined invite is final, and to talk the initiator asks again.
//
//   - Donor chat has no "ask again". POST /api/chats/request answers 410 since
//     Phase 4 retired direct chats (chat.Store.RequestThread), so a declined
//     donor invite stays declined, and its refusal promises nothing more.
//   - Marriage chat asks again with a new meeting request
//     (POST /api/marriage/:id/request-meeting) that staff approve
//     (POST /api/admin/marriage/meeting-requests/:id/approve). The schema keeps
//     ONE thread per requester and profile (uq_marriage_chat_pair, migration
//     058), so the approval re-opens that declined thread as a fresh pending
//     invite, which shows in the owner's chat list and can be accepted.
//
// What must still hold:
//   - a pending invite accepts and pushes the initiator;
//   - accepting an already active thread stays an idempotent 200;
//   - anyone who may not accept gets today's 403 on a declined thread too, so
//     the new 409 never tells them the invite was declined;
//   - a new approval never demotes a chat that is already active.
//
// Every assertion reads status, lists and notifications back from the
// DATABASE or the real routes. Shared harness: chat_lifecycle_test.go
// (newLifecyclePool, makeLifecycleUser, tokenFor, doJSON),
// chat_invite_accept_lifecycle_test.go (seedPendingInvite, inviteStatus,
// acceptedPushes, waitForAcceptedPush) and
// marriage_invite_accept_lifecycle_test.go (seedPendingMarriageInvite,
// acceptMarriageInvite, marriageThreadStatus, marriageAcceptedPushes,
// waitForMarriageAcceptedPush).
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_declined_invite
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_declined_invite?sslmode=disable' \
//	  go test ./internal/handlers/ -run DeclinedInvite -v
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
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ─── Pinned responses ───────────────────────────────────────────────────

// wantInviteDeclinedCode is the machine code the app switches on. Pinned as a
// literal, not the handler's constant, so renaming the constant cannot
// silently change what installed apps receive.
const wantInviteDeclinedCode = "chat_invite_declined"

// The 409 sentences, pinned verbatim because they are what the user reads.
// The donor one promises nothing further: a donor chat cannot be requested
// again. The marriage one says what happens next, because it can.
const (
	wantDonorInviteDeclinedMessage    = "This chat request was declined, so it can no longer be accepted."
	wantMarriageInviteDeclinedMessage = "This chat request was declined, so it can no longer be accepted. If a new request is approved, it will come to you as a new invite."
)

// marriageRequestPushType is notify.MarriageChatRequestMsg's
// notification_type: the row the profile owner receives when staff approve a
// meeting request and an invite is waiting for them.
const marriageRequestPushType = "marriage_chat_request"

// ─── Fixtures ───────────────────────────────────────────────────────────

// newDeclinedInviteRouter mounts every route this file drives, behind
// main.go's chain for each: the authed group's RequireBearer + RequireApproved
// with RequireNotGuest (or GuestGetsEmptyList on the list) on the routes, and
// the admin group's RequireAdmin + RequirePermission("marriage", "edit") on
// the approval.
func newDeclinedInviteRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	n := notify.New(pool)
	chatH := NewChatHandler(chat.New(pool), n, pool)
	marriageChatH := NewMarriageChatHandler(marriagechat.New(pool), n, pool)
	// The wallet is only used by subscription purchases, not by RequestMeeting.
	marriageH := NewMarriageHandler(marriage.New(pool), n, nil)

	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(tokens), auth.RequireApproved())
	authed.POST("/chats/:id/accept", auth.RequireNotGuest(), chatH.Accept)
	authed.POST("/chats/:id/decline", auth.RequireNotGuest(), chatH.Decline)
	authed.GET("/marriage/chats", GuestGetsEmptyList(), marriageChatH.List)
	authed.POST("/marriage/chats/:id/accept", auth.RequireNotGuest(), marriageChatH.Accept)
	authed.POST("/marriage/chats/:id/decline", auth.RequireNotGuest(), marriageChatH.Decline)
	authed.POST("/marriage/:id/request-meeting", auth.RequireNotGuest(), marriageH.RequestMeeting)

	admin := r.Group("/api", auth.RequireAdmin(tokens))
	admin.POST("/admin/marriage/meeting-requests/:id/approve",
		auth.RequirePermission(permissions.New(pool), "marriage", "edit"),
		marriageChatH.AdminApproveMeetingRequest)
	return r
}

// declineDonorInvite seeds a pending donor invite and has the invitee decline
// it through the real decline route, the way a user turns one down.
func declineDonorInvite(t *testing.T, r *gin.Engine, pool *pgxpool.Pool) pendingInvite {
	t.Helper()
	inv := seedPendingInvite(t, pool)
	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/decline", inv.ThreadID),
		tokenFor(t, pool, inv.Invitee), nil)
	if code != http.StatusOK || body["status"] != "declined" {
		t.Fatalf("decline donor invite: status = %d body = %v, want 200 declined", code, body)
	}
	return inv
}

// declineMarriageThread has the profile owner decline inv's thread through the
// real decline route.
func declineMarriageThread(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, inv pendingMarriageInvite) {
	t.Helper()
	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/marriage/chats/%d/decline", inv.ThreadID),
		tokenFor(t, pool, inv.Owner), nil)
	if code != http.StatusOK || body["status"] != "declined" {
		t.Fatalf("decline marriage invite: status = %d body = %v, want 200 declined", code, body)
	}
}

// declineMarriageInvite seeds a pending marriage invite (approved by staff
// through the store) and has the profile owner decline it.
func declineMarriageInvite(t *testing.T, r *gin.Engine, pool *pgxpool.Pool) pendingMarriageInvite {
	t.Helper()
	inv := seedPendingMarriageInvite(t, pool)
	declineMarriageThread(t, r, pool, inv)
	return inv
}

// acceptDonorInvite sends the donor accept for inv's thread as userID.
func acceptDonorInvite(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, inv pendingInvite, userID int64) (int, map[string]any) {
	t.Helper()
	return doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/chats/%d/accept", inv.ThreadID),
		tokenFor(t, pool, userID), nil)
}

// jsonID reads a numeric id out of a decoded JSON body, failing the test when
// it is missing (encoding/json decodes every number as float64).
func jsonID(t *testing.T, body map[string]any, key string) int64 {
	t.Helper()
	v, ok := body[key].(float64)
	if !ok {
		t.Fatalf("response has no numeric %q: %v", key, body)
	}
	return int64(v)
}

// ─── Assertions ─────────────────────────────────────────────────────────

// assertInviteDeclinedRefusal pins the whole 409 body, so an extra field (a
// lifecycle reason, a thread status) cannot leak into it unnoticed.
func assertInviteDeclinedRefusal(t *testing.T, code int, body map[string]any, wantMessage string) {
	t.Helper()
	want := map[string]any{"success": false, "code": wantInviteDeclinedCode, "error": wantMessage}
	if code != http.StatusConflict || !reflect.DeepEqual(body, want) {
		t.Fatalf("status = %d body = %v, want 409 %v", code, body, want)
	}
}

// marriageRequestPushes counts "marriage chat request" rows for one user.
func marriageRequestPushes(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM app_notifications WHERE user_id = $1 AND notification_type = $2`,
		userID, marriageRequestPushType).Scan(&n); err != nil {
		t.Fatalf("count marriage request pushes: %v", err)
	}
	return n
}

// waitForMarriageRequestPushes polls until the owner has at least want invite
// notification rows, written by the approval's background send, or fails at
// the deadline. A ceiling, not a sleep.
func waitForMarriageRequestPushes(t *testing.T, pool *pgxpool.Pool, userID int64, want int) {
	t.Helper()
	deadline := time.Now().Add(acceptedPushWait)
	for marriageRequestPushes(t, pool, userID) < want {
		if time.Now().After(deadline) {
			t.Fatalf("user %d has %d %q notifications after %s, want at least %d",
				userID, marriageRequestPushes(t, pool, userID), marriageRequestPushType, acceptedPushWait, want)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// ownerListedStatus reads the thread's row from the owner's own chat list,
// GET /api/marriage/chats, and reports its status. found is false when the
// list does not show the thread at all (declined threads are hidden).
func ownerListedStatus(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, inv pendingMarriageInvite) (status string, found bool) {
	t.Helper()
	code, body := doJSON(t, r, http.MethodGet, "/api/marriage/chats", tokenFor(t, pool, inv.Owner), nil)
	items, ok := body["items"].([]any)
	if code != http.StatusOK || !ok {
		t.Fatalf("owner chat list: status = %d body = %v, want 200 with items", code, body)
	}
	for _, it := range items {
		row, _ := it.(map[string]any)
		if id, _ := row["id"].(float64); int64(id) == inv.ThreadID {
			s, _ := row["status"].(string)
			return s, true
		}
	}
	return "", false
}

// ─── The bug: a declined invite must not be accepted ────────────────────

// TestDeclinedInviteAccept_DonorRefused is the reported bug in donor chat: the
// invitee declines, then accepts. It must be refused, the thread must stay
// declined, and the initiator must not be told it was accepted. The handler
// refuses before it starts the background send, so a zero count is final.
func TestDeclinedInviteAccept_DonorRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclinedInviteRouter(pool)
	inv := declineDonorInvite(t, r, pool)

	code, body := acceptDonorInvite(t, r, pool, inv, inv.Invitee)
	t.Logf("accept on a declined donor invite: %d %v", code, body)
	assertInviteDeclinedRefusal(t, code, body, wantDonorInviteDeclinedMessage)
	if s := inviteStatus(t, pool, inv.ThreadID); s != "declined" {
		t.Errorf("stored status = %q after a refused accept, want declined", s)
	}
	if n := acceptedPushes(t, pool, inv.Initiator); n != 0 {
		t.Errorf("initiator has %d %q notifications after a refused accept, want 0", n, acceptedPushType)
	}
}

// TestDeclinedInviteAccept_MarriageRefused is the same bug in marriage chat.
func TestDeclinedInviteAccept_MarriageRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclinedInviteRouter(pool)
	inv := declineMarriageInvite(t, r, pool)

	code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner)
	t.Logf("accept on a declined marriage invite: %d %v", code, body)
	assertInviteDeclinedRefusal(t, code, body, wantMarriageInviteDeclinedMessage)
	if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "declined" {
		t.Errorf("stored status = %q after a refused accept, want declined", s)
	}
	if n := marriageAcceptedPushes(t, pool, inv.Requester); n != 0 {
		t.Errorf("requester has %d %q notifications after a refused accept, want 0", n, marriageAcceptedPushType)
	}
}

// ─── What the fix must keep ─────────────────────────────────────────────

// TestDeclinedInviteAccept_PendingAcceptsThenRepeatIsIdempotent is the control
// for both tests above, in both systems: a pending invite accepts and pushes
// the initiator, and accepting it a second time is still a 200 on an active
// thread rather than a refusal.
func TestDeclinedInviteAccept_PendingAcceptsThenRepeatIsIdempotent(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclinedInviteRouter(pool)

	t.Run("donor", func(t *testing.T) {
		inv := seedPendingInvite(t, pool)
		for attempt := 1; attempt <= 2; attempt++ {
			code, body := acceptDonorInvite(t, r, pool, inv, inv.Invitee)
			if code != http.StatusOK || body["status"] != "active" {
				t.Fatalf("accept #%d: status = %d body = %v, want 200 active", attempt, code, body)
			}
			if s := inviteStatus(t, pool, inv.ThreadID); s != "active" {
				t.Fatalf("accept #%d: stored status = %q, want active", attempt, s)
			}
			waitForAcceptedPush(t, pool, inv.Initiator)
		}
	})
	t.Run("marriage", func(t *testing.T) {
		inv := seedPendingMarriageInvite(t, pool)
		for attempt := 1; attempt <= 2; attempt++ {
			code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner)
			if code != http.StatusOK || body["status"] != "active" {
				t.Fatalf("accept #%d: status = %d body = %v, want 200 active", attempt, code, body)
			}
			if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "active" {
				t.Fatalf("accept #%d: stored status = %q, want active", attempt, s)
			}
			waitForMarriageAcceptedPush(t, pool, inv.Requester)
		}
	})
}

// TestDeclinedInviteAccept_NonRecipientLearnsNothing pins the ORDER of the
// checks on a declined thread: whoever may not accept gets exactly today's 403,
// with no code, so the 409 never tells a stranger or the initiator that the
// invite was declined.
func TestDeclinedInviteAccept_NonRecipientLearnsNothing(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclinedInviteRouter(pool)

	type caller struct {
		who       string
		userID    int64
		wantError string
	}
	assertPlain403 := func(t *testing.T, c caller, code int, body map[string]any) {
		t.Helper()
		if code != http.StatusForbidden || body["error"] != c.wantError || body["code"] != nil {
			t.Errorf("%s: status = %d body = %v, want the plain 403 %q", c.who, code, body, c.wantError)
		}
	}

	t.Run("donor", func(t *testing.T) {
		inv := declineDonorInvite(t, r, pool)
		callers := []caller{
			{"initiator", inv.Initiator, "Only the invited party can accept or decline."},
			{"stranger", makeLifecycleUser(t, pool, "user"), "You are not a participant in this chat."},
		}
		for _, c := range callers {
			code, body := acceptDonorInvite(t, r, pool, inv, c.userID)
			assertPlain403(t, c, code, body)
		}
		if s := inviteStatus(t, pool, inv.ThreadID); s != "declined" {
			t.Errorf("stored status = %q, want declined", s)
		}
	})
	t.Run("marriage", func(t *testing.T) {
		inv := declineMarriageInvite(t, r, pool)
		callers := []caller{
			{"requester", inv.Requester, marriageNotOwnerError},
			{"stranger", makeLifecycleUser(t, pool, "user"), marriageNotOwnerError},
		}
		for _, c := range callers {
			code, body := acceptMarriageInvite(t, r, pool, inv, c.userID)
			assertPlain403(t, c, code, body)
		}
		if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "declined" {
			t.Errorf("stored status = %q, want declined", s)
		}
	})
}

// ─── Re-invite: asking again starts a fresh marriage invite ─────────────

// requestMeeting files a meeting request about profileID through the app's
// route, as the requester, and returns the request id. Its row is removed
// afterwards; deleting it also removes a thread that points at it
// (marriage_chat_threads.meeting_request_id cascades).
func requestMeeting(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, requester, profileID int64) int64 {
	t.Helper()
	code, body := doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/marriage/%d/request-meeting", profileID),
		tokenFor(t, pool, requester), map[string]any{"message": "May we talk?", "request_type": "meeting"})
	if code != http.StatusOK || body["status"] != "pending" {
		t.Fatalf("request meeting: status = %d body = %v, want 200 pending", code, body)
	}
	requestID := jsonID(t, body, "id")
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marriage_meeting_requests WHERE id = $1`, requestID)
	})
	return requestID
}

// requestMeetingAgain files a new meeting request about the profile of inv's
// thread, as its requester.
func requestMeetingAgain(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, inv pendingMarriageInvite) int64 {
	t.Helper()
	var profileID int64
	if err := pool.QueryRow(context.Background(),
		`SELECT profile_id FROM marriage_chat_threads WHERE id = $1`, inv.ThreadID).Scan(&profileID); err != nil {
		t.Fatalf("read thread profile: %v", err)
	}
	return requestMeeting(t, r, pool, inv.Requester, profileID)
}

// approveMeetingRequest approves a meeting request through the dashboard's
// route, as a staff member.
func approveMeetingRequest(t *testing.T, r *gin.Engine, pool *pgxpool.Pool, requestID int64) (int, map[string]any) {
	t.Helper()
	staff := makeLifecycleUser(t, pool, "admin")
	return doJSON(t, r, http.MethodPost, fmt.Sprintf("/api/admin/marriage/meeting-requests/%d/approve", requestID),
		tokenFor(t, pool, staff), nil)
}

// seedRouteApprovedMarriageInvite builds a pending invite entirely through the
// production routes: the requester asks, staff approve, and the owner's invite
// notification is written. Unlike seedPendingMarriageInvite, the owner
// therefore already holds that notification, exactly as in production.
func seedRouteApprovedMarriageInvite(t *testing.T, r *gin.Engine, pool *pgxpool.Pool) pendingMarriageInvite {
	t.Helper()
	ctx := context.Background()
	requester := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	lifecycleSeq++
	var profileID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code) VALUES ($1, $2) RETURNING id`,
		owner, fmt.Sprintf("MRG-REINV-%d", lifecycleSeq)).Scan(&profileID); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	// Registered before anything references the profile, so it runs after
	// every later cleanup (LIFO) and before the users go.
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM app_notifications WHERE user_id = ANY($1)`, []int64{requester, owner})
		_, _ = pool.Exec(ctx, `UPDATE marriage_meeting_requests SET thread_id = NULL WHERE profile_id = $1`, profileID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_threads WHERE profile_id = $1`, profileID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_meeting_requests WHERE profile_id = $1`, profileID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})

	requestID := requestMeeting(t, r, pool, requester, profileID)
	code, body := approveMeetingRequest(t, r, pool, requestID)
	if code != http.StatusOK || body["status"] != "pending" {
		t.Fatalf("first approval: status = %d body = %v, want 200 pending", code, body)
	}
	waitForMarriageRequestPushes(t, pool, owner, 1)
	return pendingMarriageInvite{ThreadID: jsonID(t, body, "thread_id"), Requester: requester, Owner: owner}
}

// TestDeclinedInviteReinvite_MarriageNewRequestOpensFreshInvite is the path
// the decision depends on, driven through the production routes end to end:
// staff approve, the owner declines, the requester asks again, staff approve
// again, and the owner has a pending invite in their own chat list that they
// can accept. Before the fix the approval reused the pair's declined thread
// without resetting it, so the "new" invite stayed declined and hidden — only
// the accept bug made it acceptable.
func TestDeclinedInviteReinvite_MarriageNewRequestOpensFreshInvite(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclinedInviteRouter(pool)
	inv := seedRouteApprovedMarriageInvite(t, r, pool)
	declineMarriageThread(t, r, pool, inv)
	if _, found := ownerListedStatus(t, r, pool, inv); found {
		t.Fatalf("a declined thread is still in the owner's list; the premise of this test is gone")
	}

	requestID := requestMeetingAgain(t, r, pool, inv)
	code, body := approveMeetingRequest(t, r, pool, requestID)
	t.Logf("approve a new meeting request after a decline: %d %v", code, body)
	if code != http.StatusOK || body["status"] != "pending" {
		t.Fatalf("approve: status = %d body = %v, want 200 pending", code, body)
	}
	if got := jsonID(t, body, "thread_id"); got != inv.ThreadID {
		t.Fatalf("approve opened thread %d, want the pair's existing thread %d (uq_marriage_chat_pair)", got, inv.ThreadID)
	}
	if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "pending" {
		t.Fatalf("stored status = %q after the new approval, want pending", s)
	}
	if s, found := ownerListedStatus(t, r, pool, inv); !found || s != "pending" {
		t.Fatalf("owner's chat list shows the thread = %v with status %q, want it listed as pending", found, s)
	}

	code, body = acceptMarriageInvite(t, r, pool, inv, inv.Owner)
	t.Logf("accept the fresh invite: %d %v", code, body)
	if code != http.StatusOK || body["status"] != "active" {
		t.Fatalf("accept fresh invite: status = %d body = %v, want 200 active", code, body)
	}
	if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "active" {
		t.Fatalf("stored status = %q after accepting the fresh invite, want active", s)
	}
	waitForMarriageAcceptedPush(t, pool, inv.Requester)
}

// TestDeclinedInviteReinvite_MarriageApprovalKeepsActiveChatActive pins the
// other side of the reset: only a DECLINED thread is re-opened. A new request
// approved for a pair whose chat is already active must not send that chat
// back to pending, which would lock both parties out until the owner accepted
// again.
func TestDeclinedInviteReinvite_MarriageApprovalKeepsActiveChatActive(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclinedInviteRouter(pool)
	inv := seedPendingMarriageInvite(t, pool)
	if code, body := acceptMarriageInvite(t, r, pool, inv, inv.Owner); code != http.StatusOK {
		t.Fatalf("accept: status = %d body = %v, want 200", code, body)
	}

	requestID := requestMeetingAgain(t, r, pool, inv)
	code, body := approveMeetingRequest(t, r, pool, requestID)
	if code != http.StatusOK || body["status"] != "active" {
		t.Fatalf("approve: status = %d body = %v, want 200 active", code, body)
	}
	if s := marriageThreadStatus(t, pool, inv.ThreadID); s != "active" {
		t.Fatalf("stored status = %q after a new approval, want active", s)
	}
}
