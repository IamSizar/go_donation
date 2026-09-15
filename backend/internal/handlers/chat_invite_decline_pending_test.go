// chat_invite_decline_pending_test.go — can an invite's recipient "decline" a
// conversation that is already under way? (OPOS #26427)
//
// # WHY THIS EXISTS
//
// Declining is the invitee's answer to a PENDING invite. Both decline stores —
// chat.Store.DeclineThread (donor chat) and marriagechat.Store.DeclineThread
// (marriage chat) — used to update the thread by id alone, so the recipient of
// an invite accepted long ago could flip the ongoing chat to 'declined'. That
// hides it from both participants' lists (ListThreadsForUser filters declined
// threads out) and refuses every further message (sending needs 'active').
// The Flutter notification tile puts that one tap away: it offers Decline on
// any chat_request notification whose thread the app has not loaded yet.
//
// What must still hold after the fix:
//   - a pending invite declines, in both chat systems;
//   - declining an invite that is ALREADY declined stays a harmless 200, as it
//     always was — the same tile re-offers Decline for it, because the list it
//     reads hides declined threads;
//   - a user who is not the recipient is refused exactly as before, and is
//     never told the thread's status;
//   - a pending invite whose thread was ended and archived still declines:
//     that is how a user dismisses a dead invite, and OPOS #26413 left decline
//     ungated by the lifecycle on purpose.
//
// Every assertion reads the thread's status back from the DATABASE rather than
// trusting the response.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_decline_pending
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_decline_pending?sslmode=disable' \
//	  go test ./internal/handlers/ -run ChatInviteDecline -v
package handlers

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
	"github.com/karam-flutter/humanitarian-backend/internal/marriagechat"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// declineRefusedMessage is the 409 body both chat systems return when the
// thread is already active. Pinned verbatim: it is what the user is shown.
const declineRefusedMessage = "This chat is already active, so it can no longer be declined."

// ─── Fixtures ───────────────────────────────────────────────────────────

// declineThread is one seeded thread in either chat system, described by the
// parties the decline rules care about.
type declineThread struct {
	Kind      chatlifecycle.Kind
	Table     string // the thread table, to read the status back
	Path      string // the decline route for this thread
	ThreadID  int64
	Recipient int64 // the only user allowed to decline
	// OtherParty is the participant who is NOT allowed to decline, and
	// OtherPartyError / StrangerError are the refusals each system gives
	// today — pinned so the fix cannot change them.
	OtherParty      int64
	OtherPartyError string
	StrangerError   string
}

// declineSeeder seeds one thread with the given consent status.
type declineSeeder func(t *testing.T, pool *pgxpool.Pool, status string) declineThread

// declineSystems is every chat system that has an invite decline route.
var declineSystems = []struct {
	name string
	seed declineSeeder
}{
	{"donor", seedDeclineDonorThread},
	{"marriage", seedDeclineMarriageThread},
}

// seedDeclineDonorThread inserts a kind='direct' donor↔owner thread the donor
// initiated, so the owner is the recipient, and removes it afterwards.
func seedDeclineDonorThread(t *testing.T, pool *pgxpool.Pool, status string) declineThread {
	t.Helper()
	donor := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO chat_threads (donor_user_id, owner_user_id, status, initiated_by, kind)
		 VALUES ($1, $2, $3, $1, 'direct') RETURNING id`, donor, owner, status).Scan(&id); err != nil {
		t.Fatalf("insert %s chat thread: %v", status, err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM chat_threads WHERE id = $1`, id)
	})
	return declineThread{
		Kind: chatlifecycle.KindDonor, Table: "chat_threads",
		Path:     fmt.Sprintf("/api/chats/%d/decline", id),
		ThreadID: id, Recipient: owner, OtherParty: donor,
		OtherPartyError: "Only the invited party can accept or decline.",
		StrangerError:   "You are not a participant in this chat.",
	}
}

// seedDeclineMarriageThread inserts a marriage thread with the parent rows it
// requires (profile, meeting request). The profile owner is the recipient.
func seedDeclineMarriageThread(t *testing.T, pool *pgxpool.Pool, status string) declineThread {
	t.Helper()
	ctx := context.Background()
	requester := makeLifecycleUser(t, pool, "user")
	owner := makeLifecycleUser(t, pool, "user")
	lifecycleSeq++
	var profileID, requestID, id int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code) VALUES ($1, $2) RETURNING id`,
		owner, fmt.Sprintf("MRG-DP-%d", lifecycleSeq)).Scan(&profileID); err != nil {
		t.Fatalf("insert marriage profile: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id) VALUES ($1, $2) RETURNING id`,
		requester, profileID).Scan(&requestID); err != nil {
		t.Fatalf("insert meeting request: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_chat_threads (meeting_request_id, profile_id, requester_user_id, owner_user_id, status)
		 VALUES ($1, $2, $3, $4, $5) RETURNING id`,
		requestID, profileID, requester, owner, status).Scan(&id); err != nil {
		t.Fatalf("insert %s marriage thread: %v", status, err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_reads WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_messages WHERE thread_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_chat_threads WHERE id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_meeting_requests WHERE id = $1`, requestID)
		_, _ = pool.Exec(ctx, `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})
	return declineThread{
		Kind: chatlifecycle.KindMarriage, Table: "marriage_chat_threads",
		Path:     fmt.Sprintf("/api/marriage/chats/%d/decline", id),
		ThreadID: id, Recipient: owner, OtherParty: requester,
		OtherPartyError: "Only the profile owner can accept or decline.",
		StrangerError:   "Only the profile owner can accept or decline.",
	}
}

// newDeclineRouter mounts both decline routes behind main.go's exact chain:
// the authed group's RequireBearer + RequireApproved, plus RequireNotGuest on
// each route.
func newDeclineRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	n := notify.New(pool)
	chatH := NewChatHandler(chat.New(pool), n, pool)
	marriageH := NewMarriageChatHandler(marriagechat.New(pool), n, pool)
	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(tokens), auth.RequireApproved())
	authed.POST("/chats/:id/decline", auth.RequireNotGuest(), chatH.Decline)
	authed.POST("/marriage/chats/:id/decline", auth.RequireNotGuest(), marriageH.Decline)
	return r
}

// declineStatus reads the consent status straight from the thread's table.
func declineStatus(t *testing.T, pool *pgxpool.Pool, th declineThread) string {
	t.Helper()
	var status string
	if err := pool.QueryRow(context.Background(),
		"SELECT status FROM "+th.Table+" WHERE id = $1", th.ThreadID).Scan(&status); err != nil {
		t.Fatalf("read %s status: %v", th.Table, err)
	}
	return status
}

// ─── The bug: an active chat must not be declined ───────────────────────

// TestChatInviteDecline_ActiveThreadRefused is the reported bug, in both
// systems: the recipient declines a thread that is already active. It must be
// refused with 409 and the chat must stay active.
func TestChatInviteDecline_ActiveThreadRefused(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclineRouter(pool)
	for _, sys := range declineSystems {
		t.Run(sys.name, func(t *testing.T) {
			th := sys.seed(t, pool, "active")
			code, body := doJSON(t, r, http.MethodPost, th.Path, tokenFor(t, pool, th.Recipient), nil)
			t.Logf("decline on an active %s thread: %d %v", sys.name, code, body)
			if code != http.StatusConflict || body["success"] != false || body["error"] != declineRefusedMessage {
				t.Errorf("status = %d body = %v, want 409 %q", code, body, declineRefusedMessage)
			}
			if s := declineStatus(t, pool, th); s != "active" {
				t.Errorf("stored status = %q after declining an active chat, want %q", s, "active")
			}
		})
	}
}

// ─── What the fix must keep ─────────────────────────────────────────────

// TestChatInviteDecline_PendingInviteDeclines is the control: without it,
// "every decline is refused" would pass the test above.
func TestChatInviteDecline_PendingInviteDeclines(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclineRouter(pool)
	for _, sys := range declineSystems {
		t.Run(sys.name, func(t *testing.T) {
			th := sys.seed(t, pool, "pending")
			code, body := doJSON(t, r, http.MethodPost, th.Path, tokenFor(t, pool, th.Recipient), nil)
			if code != http.StatusOK || body["status"] != "declined" {
				t.Errorf("status = %d body = %v, want 200 declined", code, body)
			}
			if s := declineStatus(t, pool, th); s != "declined" {
				t.Errorf("stored status = %q, want declined", s)
			}
		})
	}
}

// TestChatInviteDecline_AlreadyDeclinedStaysSuccessful pins that a repeated
// decline is still a 200. The notification tile re-offers Decline for a
// declined invite (the thread list it reads hides declined threads), so a
// refusal here would turn a working tap into a dead button.
func TestChatInviteDecline_AlreadyDeclinedStaysSuccessful(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclineRouter(pool)
	for _, sys := range declineSystems {
		t.Run(sys.name, func(t *testing.T) {
			th := sys.seed(t, pool, "declined")
			code, body := doJSON(t, r, http.MethodPost, th.Path, tokenFor(t, pool, th.Recipient), nil)
			if code != http.StatusOK || body["status"] != "declined" {
				t.Errorf("status = %d body = %v, want 200 declined", code, body)
			}
			if s := declineStatus(t, pool, th); s != "declined" {
				t.Errorf("stored status = %q, want declined", s)
			}
		})
	}
}

// TestChatInviteDecline_NonRecipientRefusedAsBefore pins today's refusals for
// the other participant and for a stranger, on a pending AND an active thread.
// The active case pins the ORDER of the checks: a user with no right to decline
// gets the same 403 either way, so the new 409 never tells them the status.
func TestChatInviteDecline_NonRecipientRefusedAsBefore(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclineRouter(pool)
	for _, sys := range declineSystems {
		for _, status := range []string{"pending", "active"} {
			t.Run(sys.name+"/"+status, func(t *testing.T) {
				th := sys.seed(t, pool, status)
				stranger := makeLifecycleUser(t, pool, "user")
				actors := []struct {
					who    string
					userID int64
					want   string
				}{
					{"other party", th.OtherParty, th.OtherPartyError},
					{"stranger", stranger, th.StrangerError},
				}
				for _, a := range actors {
					code, body := doJSON(t, r, http.MethodPost, th.Path, tokenFor(t, pool, a.userID), nil)
					if code != http.StatusForbidden || body["error"] != a.want {
						t.Errorf("%s: status = %d body = %v, want 403 %q", a.who, code, body, a.want)
					}
				}
				if s := declineStatus(t, pool, th); s != status {
					t.Errorf("stored status = %q after refused declines, want %q", s, status)
				}
			})
		}
	}
}

// TestChatInviteDecline_RetiredPendingInviteStillDeclines pins the lifecycle
// behaviour this fix must NOT change: a pending invite whose thread staff ended
// and archived (the real transitions, through chatlifecycle.Apply) can still
// be declined, so the user can dismiss a dead invite.
func TestChatInviteDecline_RetiredPendingInviteStillDeclines(t *testing.T) {
	pool := newLifecyclePool(t)
	r := newDeclineRouter(pool)
	for _, sys := range declineSystems {
		t.Run(sys.name, func(t *testing.T) {
			staff := makeLifecycleUser(t, pool, "admin")
			th := sys.seed(t, pool, "pending")
			for _, action := range []string{chatlifecycle.ActionEnd, chatlifecycle.ActionArchive} {
				if _, err := chatlifecycle.Apply(context.Background(), pool, th.Kind, th.ThreadID,
					action, "Retired by our team", staff); err != nil {
					t.Fatalf("apply %s: %v", action, err)
				}
			}
			code, body := doJSON(t, r, http.MethodPost, th.Path, tokenFor(t, pool, th.Recipient), nil)
			if code != http.StatusOK || body["status"] != "declined" {
				t.Errorf("status = %d body = %v, want 200 declined", code, body)
			}
			if s := declineStatus(t, pool, th); s != "declined" {
				t.Errorf("stored status = %q, want declined", s)
			}
		})
	}
}
