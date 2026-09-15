// notifications_guest_test.go proves that a guest account cannot read a chat
// through its notifications (OPOS #26424).
//
// THE GAP
// Guests must not read chats. Since PR #83 (and OPOS #26354 for the direct and
// marriage chats) the chat READ routes refuse a guest session. But a chat
// message also writes an app_notifications row whose body is the message
// itself, cut to 80 characters (handlers/chat.go and chat_group.go). Two
// routes hand those rows back and neither is guest-gated:
//
//   - GET /api/notifications — the Alerts list. The app computes its unread
//     badge from this same list, and ?read_status=unread / ?unread_only=1 is
//     the server's unread filter.
//   - GET /api/dashboard — summary.recent_notifications, the newest three.
//
// So a guest who was in a chat before commit 9d1cde5 could still read message
// snippets there. Both routes must stay open to guests — campaign, news,
// partner and support-ticket notifications are theirs to see — so the fix is
// a filter on the notification TYPE for guest accounts, not a route gate.
//
// The router below wires these routes exactly as main.go does: the authed
// group's RequireBearer + RequireApproved and no per-route guest gate.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_guest_notif
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_guest_notif?sslmode=disable' \
//	  go test ./internal/handlers/ -run GuestNotifications -v
package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/dashboard"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// ─── Harness ────────────────────────────────────────────────────────────

// guestNotifPreview is the chat message text seeded into both chat
// notifications. It is distinctive enough that finding it anywhere in a raw
// response body can only mean the preview leaked.
const guestNotifPreview = "meet me at the clinic gate at nine and bring the file"

// newGuestNotificationsRouter wires the notification list and the dashboard
// summary exactly as main.go does: RequireBearer + RequireApproved on the
// authed group, and no RequireNotGuest on either route.
func newGuestNotificationsRouter(pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	notificationsH := NewNotificationsHandler(notify.New(pool))
	dashboardH := NewDashboardHandler(dashboard.New(pool), users.NewStore(pool))
	r := gin.New()
	authed := r.Group("/api", auth.RequireBearer(auth.NewTokenStore(pool)), auth.RequireApproved())
	authed.GET("/notifications", notificationsH.List)
	authed.GET("/notifications/", notificationsH.List)
	authed.GET("/dashboard", dashboardH.Get)
	authed.GET("/dashboard/", dashboardH.Get)
	return r
}

// seededNotifications holds the id of each notification seedNotificationMix
// wrote, so assertions can name exactly which rows a caller should see.
type seededNotifications struct {
	legacyUntyped int64 // notification_type NULL, as pre-typed rows are
	campaign      int64 // new_campaign — a broadcast guests legitimately get
	supportReply  int64 // support_ticket_replied — tickets stay guest-readable
	chatMessage   int64 // chat_message — carries the message preview
	chatGroup     int64 // chat_group_message — carries the message preview
}

// all returns every seeded id, in insertion order.
func (s seededNotifications) all() []int64 {
	return []int64{s.legacyUntyped, s.campaign, s.supportReply, s.chatMessage, s.chatGroup}
}

// nonChat returns the seeded ids a guest must still see, in insertion order.
func (s seededNotifications) nonChat() []int64 {
	return []int64{s.legacyUntyped, s.campaign, s.supportReply}
}

// seedNotificationMix writes one notification of each kind for userID.
//
// The typed rows go through Notifier.Send with the real templates, so the
// stored type, body and priority are what production writes. The untyped row
// is inserted directly: nothing writes a NULL type today, but the column
// allows it, and the filter must not hide such a row by accident.
//
// Insertion order is fixed and matters for the dashboard's LIMIT 3 (see
// TestGuestNotifications_DashboardHidesChatNotifications).
func seedNotificationMix(t *testing.T, pool *pgxpool.Pool, userID int64) seededNotifications {
	t.Helper()
	ctx := context.Background()
	n := notify.New(pool)
	var s seededNotifications
	if err := pool.QueryRow(ctx,
		`INSERT INTO app_notifications (user_id, title, body, notification_type, priority)
		 VALUES ($1, 'Legacy notice', 'A notice written before types existed.', NULL, 0)
		 RETURNING id`, userID,
	).Scan(&s.legacyUntyped); err != nil {
		t.Fatalf("insert legacy untyped notification: %v", err)
	}
	s.campaign = sendOrFail(t, n, userID, notify.NewCampaignMsg("Winter Relief", 11))
	s.supportReply = sendOrFail(t, n, userID, notify.SupportRepliedMsg("Card payment", 12))
	s.chatMessage = sendOrFail(t, n, userID, notify.ChatNewMessageMsg("Donor", guestNotifPreview, 13))
	s.chatGroup = sendOrFail(t, n, userID, notify.GroupMaskedNewMessageMsg("Donor 1", guestNotifPreview, 14))
	return s
}

// sendOrFail sends m to userID and fails the test unless a row was written.
func sendOrFail(t *testing.T, n *notify.Notifier, userID int64, m notify.LocalizedMessage) int64 {
	t.Helper()
	id, err := n.Send(context.Background(), userID, m)
	if err != nil || id <= 0 {
		t.Fatalf("send %s to user %d: id=%d err=%v", m.Type, userID, id, err)
	}
	return id
}

// notificationRow is the part of a notification item the assertions read.
type notificationRow struct {
	ID     int64   `json:"id"`
	UserID *int64  `json:"user_id"`
	Type   *string `json:"notification_type"`
}

// getRawAs performs a GET as token and returns the status and raw body. The
// raw body matters: the preview check must see every field, not a decoded one.
func getRawAs(t *testing.T, r *gin.Engine, token, path string) (int, string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code, w.Body.String()
}

// listNotifications GETs a /api/notifications path and decodes its items.
func listNotifications(t *testing.T, r *gin.Engine, token, path string) ([]notificationRow, string) {
	t.Helper()
	code, raw := getRawAs(t, r, token, path)
	if code != http.StatusOK {
		t.Fatalf("GET %s: status = %d, want 200 (body %s)", path, code, raw)
	}
	var out struct {
		Success bool              `json:"success"`
		Items   []notificationRow `json:"items"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil || !out.Success {
		t.Fatalf("GET %s: undecodable or unsuccessful body %s (err %v)", path, raw, err)
	}
	return out.Items, raw
}

// dashboardRecent GETs /api/dashboard and decodes summary.recent_notifications.
func dashboardRecent(t *testing.T, r *gin.Engine, token string) ([]notificationRow, string) {
	t.Helper()
	code, raw := getRawAs(t, r, token, "/api/dashboard")
	if code != http.StatusOK {
		t.Fatalf("GET /api/dashboard: status = %d, want 200 (body %s)", code, raw)
	}
	var out struct {
		Summary struct {
			Recent []notificationRow `json:"recent_notifications"`
		} `json:"summary"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		t.Fatalf("GET /api/dashboard: undecodable body %s (err %v)", raw, err)
	}
	return out.Summary.Recent, raw
}

// ownIDs returns, in response order, the ids of the rows addressed to userID.
// Broadcast rows (user_id NULL) from migration seed data may also be listed;
// they are not this test's rows, so exact-set assertions ignore them.
func ownIDs(rows []notificationRow, userID int64) []int64 {
	ids := []int64{}
	for _, row := range rows {
		if row.UserID != nil && *row.UserID == userID {
			ids = append(ids, row.ID)
		}
	}
	return ids
}

// seededChatTypes are the two chat types seedNotificationMix writes. The full
// classification is pinned in internal/notify/chat_types_test.go; this test
// only needs to recognise the rows it seeded itself.
var seededChatTypes = []string{"chat_message", "chat_group_message"}

// idsOf returns every row's id, in response order. The dashboard needs this
// rather than ownIDs: its rows carry no user_id field, and its query is
// "WHERE user_id = $1" alone, so every row it returns is the caller's own.
func idsOf(rows []notificationRow) []int64 {
	ids := make([]int64, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.ID)
	}
	return ids
}

// chatTypesIn returns every seeded chat notification_type present in rows.
func chatTypesIn(rows []notificationRow) []string {
	found := []string{}
	for _, row := range rows {
		if row.Type != nil && slices.Contains(seededChatTypes, *row.Type) {
			found = append(found, *row.Type)
		}
	}
	return found
}

// sameIDSet reports whether got and want hold the same ids, ignoring order.
func sameIDSet(got, want []int64) bool {
	a, b := slices.Clone(got), slices.Clone(want)
	slices.Sort(a)
	slices.Sort(b)
	return slices.Equal(a, b)
}

// listPaths are the list and unread-count reads the app and the server
// support. Both the guest test and the member control walk this same list.
var listPaths = []string{
	"/api/notifications",
	"/api/notifications/",
	"/api/notifications?read_status=unread",
	"/api/notifications?unread_only=1",
}

// ─── A guest's list and unread count exclude chat notifications ────────

func TestGuestNotifications_ListHidesChatNotifications(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newGuestNotificationsRouter(pool)
	guest := makeGuestUser(t, pool)
	seeded := seedNotificationMix(t, pool, guest)
	token := tokenForChatGroupUser(t, pool, guest)

	for _, path := range listPaths {
		t.Run(path, func(t *testing.T) {
			rows, raw := listNotifications(t, r, token, path)

			if found := chatTypesIn(rows); len(found) > 0 {
				t.Fatalf("guest was shown chat notifications %v — guests must not read chats", found)
			}
			if strings.Contains(raw, guestNotifPreview) {
				t.Fatalf("guest response contains the chat message preview: %s", raw)
			}
			if got := ownIDs(rows, guest); !sameIDSet(got, seeded.nonChat()) {
				t.Fatalf("guest's own rows = %v, want exactly the non-chat rows %v (untyped, campaign, support reply)",
					got, seeded.nonChat())
			}
		})
	}

	// Asking for a chat type by name must not reopen the door.
	t.Run("type=chat_message", func(t *testing.T) {
		rows, raw := listNotifications(t, r, token, "/api/notifications?type=chat_message")
		if len(rows) != 0 || strings.Contains(raw, guestNotifPreview) {
			t.Fatalf("guest filtering by type=chat_message got %d rows (body %s), want none", len(rows), raw)
		}
	})
}

// ─── A full account's list is unchanged ─────────────────────────────────

func TestGuestNotifications_MemberListUnchanged(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newGuestNotificationsRouter(pool)
	member := makeChatGroupUser(t, pool, "Member Name")
	seeded := seedNotificationMix(t, pool, member)
	token := tokenForChatGroupUser(t, pool, member)

	for _, path := range listPaths {
		t.Run(path, func(t *testing.T) {
			rows, raw := listNotifications(t, r, token, path)

			if got := ownIDs(rows, member); !sameIDSet(got, seeded.all()) {
				t.Fatalf("member's own rows = %v, want all seeded rows %v", got, seeded.all())
			}
			if !strings.Contains(raw, guestNotifPreview) {
				t.Fatalf("member response lost the chat preview — members must see their chat notifications")
			}
		})
	}

	t.Run("type=chat_message", func(t *testing.T) {
		rows, _ := listNotifications(t, r, token, "/api/notifications?type=chat_message")
		if got := ownIDs(rows, member); !slices.Equal(got, []int64{seeded.chatMessage}) {
			t.Fatalf("member filtering by type=chat_message got %v, want [%d]", got, seeded.chatMessage)
		}
	})
}

// ─── The dashboard's recent notifications follow the same rule ──────────

// TestGuestNotifications_DashboardHidesChatNotifications pins the second read
// path. recent_notifications is "ORDER BY is_read, priority DESC, id DESC
// LIMIT 3". With every row unread, the seeded priorities are support reply 80,
// campaign 35, and 0 for the rest, so:
//   - a member gets [support reply, campaign, chat group] — the newest 0;
//   - a guest gets [support reply, campaign, untyped] once chat rows are gone.
//
// Exact ids, not "no chat types": the store swallows query errors into an
// empty list, and an empty list would otherwise pass the guest check.
func TestGuestNotifications_DashboardHidesChatNotifications(t *testing.T) {
	pool := newChatGroupPool(t)
	r := newGuestNotificationsRouter(pool)

	t.Run("guest", func(t *testing.T) {
		guest := makeGuestUser(t, pool)
		seeded := seedNotificationMix(t, pool, guest)
		rows, raw := dashboardRecent(t, r, tokenForChatGroupUser(t, pool, guest))

		want := []int64{seeded.supportReply, seeded.campaign, seeded.legacyUntyped}
		if got := idsOf(rows); !slices.Equal(got, want) {
			t.Fatalf("guest recent_notifications = %v, want %v (chat rows excluded) — body %s", got, want, raw)
		}
		if strings.Contains(raw, guestNotifPreview) {
			t.Fatalf("guest dashboard contains the chat message preview: %s", raw)
		}
	})

	t.Run("member", func(t *testing.T) {
		member := makeChatGroupUser(t, pool, "Member Name")
		seeded := seedNotificationMix(t, pool, member)
		rows, _ := dashboardRecent(t, r, tokenForChatGroupUser(t, pool, member))

		want := []int64{seeded.supportReply, seeded.campaign, seeded.chatGroup}
		if got := idsOf(rows); !slices.Equal(got, want) {
			t.Fatalf("member recent_notifications = %v, want %v (unchanged)", got, want)
		}
	})
}
