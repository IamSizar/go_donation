// notifications_clear_test.go — notifications leave a user's list: on demand
// when they clear the read ones, and on their own once a read row is old.
//
// THE REPORT (client, 2026-09-16)
//
//	"marking a notifcation as read doesnt make it go aweay
//	 old notifications must go away"
//
// THE GAP
// Nothing ever removed a notification. GET /api/notifications returned every
// row a user had ever been sent, forever, and POST /api/notifications knew one
// action — mark_read — which only flipped a flag the list did not act on. There
// was no delete or clear endpoint and no retention rule anywhere in the
// backend, so the list a volunteer opened in month six held month one.
//
// WHAT IS PINNED HERE
//   - POST action=clear_read removes the caller's READ notifications from
//     every later read of the list, and leaves the unread ones alone;
//   - it clears broadcast rows (user_id IS NULL) for that caller only, without
//     touching what anybody else sees — those rows are shared;
//   - one user's clear never touches another user's list;
//   - a READ row older than the retention window falls out of the list by
//     itself, and an equally old UNREAD row does not: an unread notification
//     is one the user has never seen, and ageing it out would be losing it.
//
// Nothing here deletes a row. clear_read stamps cleared_at (migration 125) and
// the list stops selecting it; the record survives for the admin exports.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_clear_notif
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_clear_notif?sslmode=disable' \
//	  go test ./internal/handlers/ -run Notifications_Clear -v
package handlers

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newClearNotificationsRouter wires the list and the POST action exactly as
// main.go does: the authed group's RequireBearer + RequireApproved.
func newClearNotificationsRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	h := NewNotificationsHandler(notify.New(pool))
	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)), auth.RequireApproved())
	authed.GET("/notifications", h.List)
	authed.POST("/notifications", h.Post)
	return r
}

// seedOwnNotification writes one row addressed to userID, read or unread, and
// aged by backdating created_at (and read_at, so an old row is old in both
// senses). age 0 means "just now".
func seedOwnNotification(t *testing.T, pool *pgxpool.Pool, userID int64,
	title string, isRead bool, age time.Duration,
) int64 {
	t.Helper()
	read := 0
	if isRead {
		read = 1
	}
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO app_notifications
		   (user_id, title, body, notification_type, is_read, read_at, created_at)
		 VALUES ($1, $2, 'Body', 'system_test', $3::int,
		         CASE WHEN $3::int = 1 THEN NOW() - $4::interval ELSE NULL END,
		         NOW() - $4::interval)
		 RETURNING id`,
		userID, title, read, age.String(),
	).Scan(&id)
	if err != nil {
		t.Fatalf("seed notification %q: %v", title, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM app_notifications WHERE id = $1`, id)
	})
	return id
}

// seedBroadcastNotification writes one row addressed to nobody in particular,
// which every user sees until they mark it read for themselves.
func seedBroadcastNotification(t *testing.T, pool *pgxpool.Pool, title string) int64 {
	t.Helper()
	var id int64
	err := pool.QueryRow(context.Background(),
		`INSERT INTO app_notifications (user_id, title, body, notification_type, is_read)
		 VALUES (NULL, $1, 'Body', 'system_test', 0)
		 RETURNING id`, title,
	).Scan(&id)
	if err != nil {
		t.Fatalf("seed broadcast %q: %v", title, err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = pool.Exec(ctx, `DELETE FROM app_notification_reads WHERE notification_id = $1`, id)
		_, _ = pool.Exec(ctx, `DELETE FROM app_notifications WHERE id = $1`, id)
	})
	return id
}

// listedIDs returns every notification id the user's list currently returns.
func listedIDs(t *testing.T, r *gin.Engine, token string) []int64 {
	t.Helper()
	rows, _ := listNotifications(t, r, token, "/api/notifications?read_status=all&limit=200")
	return idsOf(rows)
}

// holdsID reports whether ids holds want.
func holdsID(ids []int64, want int64) bool {
	for _, id := range ids {
		if id == want {
			return true
		}
	}
	return false
}

// clearRead POSTs the clear action and fails unless the server accepted it.
func clearRead(t *testing.T, r *gin.Engine, token string, userID int64) map[string]any {
	t.Helper()
	code, body := postAs(t, r, token, "/api/notifications", map[string]any{
		"action":  "clear_read",
		"user_id": userID,
	})
	if code != http.StatusOK {
		t.Fatalf("POST clear_read: status = %d, want 200 (body %v)", code, body)
	}
	return body
}

// ─── Clearing the read notifications ────────────────────────────────────

func TestNotifications_ClearReadRemovesOnlyTheReadOnes(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newClearNotificationsRouter(pool)
	user := makeChatGroupUser(t, pool, "Clear Reader")
	token := tokenForChatGroupUser(t, pool, user)

	unread := seedOwnNotification(t, pool, user, "Still unread", false, 0)
	read := seedOwnNotification(t, pool, user, "Already read", true, 0)

	before := listedIDs(t, r, token)
	if !holdsID(before, unread) || !holdsID(before, read) {
		t.Fatalf("before the clear, list = %v, want it to hold both %d and %d", before, unread, read)
	}

	clearRead(t, r, token, user)

	after := listedIDs(t, r, token)
	if holdsID(after, read) {
		t.Fatalf("the read notification %d is still listed after clear_read: %v", read, after)
	}
	if !holdsID(after, unread) {
		t.Fatalf("the unread notification %d was cleared too: %v — clear_read must only take read rows", unread, after)
	}
}

func TestNotifications_ClearReadIsPerUser(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newClearNotificationsRouter(pool)

	mine := makeChatGroupUser(t, pool, "Clears Their List")
	myToken := tokenForChatGroupUser(t, pool, mine)
	theirs := makeChatGroupUser(t, pool, "Clears Nothing")
	theirToken := tokenForChatGroupUser(t, pool, theirs)

	myRead := seedOwnNotification(t, pool, mine, "Mine, read", true, 0)
	theirRead := seedOwnNotification(t, pool, theirs, "Theirs, read", true, 0)

	// A broadcast row both users can see. Only the clearing user has read it,
	// so only their copy may disappear — the row itself is shared.
	broadcast := seedBroadcastNotification(t, pool, "Everyone gets this")

	clearRead(t, r, myToken, mine)

	after := listedIDs(t, r, myToken)
	if holdsID(after, myRead) {
		t.Fatalf("my read row %d survived my clear: %v", myRead, after)
	}

	theirList := listedIDs(t, r, theirToken)
	if !holdsID(theirList, theirRead) {
		t.Fatalf("my clear removed another user's read row %d: %v", theirRead, theirList)
	}
	if !holdsID(theirList, broadcast) {
		t.Fatalf("my clear removed the shared broadcast row %d from another user's list: %v", broadcast, theirList)
	}
}

func TestNotifications_ClearReadHidesABroadcastForThatUserOnly(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newClearNotificationsRouter(pool)

	mine := makeChatGroupUser(t, pool, "Reads The Broadcast")
	myToken := tokenForChatGroupUser(t, pool, mine)
	theirs := makeChatGroupUser(t, pool, "Ignores The Broadcast")
	theirToken := tokenForChatGroupUser(t, pool, theirs)

	broadcast := seedBroadcastNotification(t, pool, "Shared announcement")

	// Read it as me, through the real endpoint, then clear.
	code, body := postAs(t, r, myToken, "/api/notifications", map[string]any{
		"action":  "mark_read",
		"id":      broadcast,
		"user_id": mine,
	})
	if code != http.StatusOK {
		t.Fatalf("POST mark_read: status = %d (body %v)", code, body)
	}
	clearRead(t, r, myToken, mine)

	if after := listedIDs(t, r, myToken); holdsID(after, broadcast) {
		t.Fatalf("the broadcast %d I read and cleared is still in my list: %v", broadcast, after)
	}
	if theirs := listedIDs(t, r, theirToken); !holdsID(theirs, broadcast) {
		t.Fatalf("clearing the broadcast %d for me removed it for everyone: %v", broadcast, theirs)
	}
}

// ─── Old notifications age out by themselves ────────────────────────────

func TestNotifications_OldReadRowsFallOutOfTheList(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newClearNotificationsRouter(pool)
	user := makeChatGroupUser(t, pool, "Long Time Member")
	token := tokenForChatGroupUser(t, pool, user)

	beyond := notify.ReadRetention + 48*time.Hour
	within := notify.ReadRetention - 48*time.Hour

	oldRead := seedOwnNotification(t, pool, user, "Old and read", true, beyond)
	oldUnread := seedOwnNotification(t, pool, user, "Old and unread", false, beyond)
	recentRead := seedOwnNotification(t, pool, user, "Recent and read", true, within)

	after := listedIDs(t, r, token)
	if holdsID(after, oldRead) {
		t.Fatalf("a read notification older than the %s window is still listed (%d): %v",
			notify.ReadRetention, oldRead, after)
	}
	if !holdsID(after, oldUnread) {
		t.Fatalf("an UNREAD notification was aged out (%d): %v — the user has never seen it", oldUnread, after)
	}
	if !holdsID(after, recentRead) {
		t.Fatalf("a read notification inside the window was aged out (%d): %v", recentRead, after)
	}
}

// ─── The action's own guards ────────────────────────────────────────────

func TestNotifications_ClearReadRefusesAnotherUsersID(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newClearNotificationsRouter(pool)

	mine := makeChatGroupUser(t, pool, "Caller")
	myToken := tokenForChatGroupUser(t, pool, mine)
	theirs := makeChatGroupUser(t, pool, "Victim")
	theirRead := seedOwnNotification(t, pool, theirs, "Theirs, read", true, 0)

	code, _ := postAs(t, r, myToken, "/api/notifications", map[string]any{
		"action":  "clear_read",
		"user_id": theirs,
	})
	if code != http.StatusUnauthorized {
		t.Fatalf("clearing another user's notifications: status = %d, want 401", code)
	}

	var cleared *time.Time
	if err := pool.QueryRow(context.Background(),
		`SELECT cleared_at FROM app_notifications WHERE id = $1`, theirRead).Scan(&cleared); err != nil {
		t.Fatalf("read back the victim's row: %v", err)
	}
	if cleared != nil {
		t.Fatalf("the refused request still cleared the victim's row %d", theirRead)
	}
}
