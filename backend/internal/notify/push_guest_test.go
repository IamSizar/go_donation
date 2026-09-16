// push_guest_test.go proves that a guest's phone never receives a chat push
// (OPOS #26443).
//
// THE GAP
// Since #104 (OPOS #26424) a guest's notification list hides chat-type rows,
// because several of them carry the chat message itself as an 80-character
// preview. But Send still fires sendPush for every row it writes, and
// activeDevicesFor selects every active device of the user without reading
// users.is_guest. POST /api/notifications/device is not guest-gated either. So
// a guest who is a grandfathered chat participant still saw the preview on
// their lock screen: the push was the remaining leak.
//
// THE DECISION
//   - A guest gets no push for a type in ChatNotificationTypes, the same list
//     the in-app filter uses.
//   - A guest keeps every other push: broadcasts and support-ticket updates.
//   - Members are unchanged.
//   - The in-app row is still written; the list already hides it from a guest.
//
// HOW THE PUSH IS OBSERVED
// There is no FCM interface to fake. Each test builds a real fcmClient whose
// access token is already cached, so accessTokenFor makes no OAuth call, and
// whose http.Client has a recording RoundTripper. Every FCM messages:send
// request is recorded and answered 200. Any other request is recorded as
// unexpected and refused, so nothing leaves the machine.
//
// sendPush is called directly rather than through Send, because Send fires it
// in a goroutine the test cannot wait on. Proving "no push happened" after a
// goroutine would need a sleep; calling the push decision synchronously makes
// every count exact. TestGuestPush_SendStillStoresTheChatRow covers the Send
// half of the decision.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_guest_push
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_guest_push?sslmode=disable' \
//	  go test ./internal/notify/ -run GuestPush -v
package notify

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────

// fcmSendHost is the only host a push may reach (see fcmClient.sendOne).
const fcmSendHost = "fcm.googleapis.com"

// recordedPush is one FCM messages:send request the recorder answered.
type recordedPush struct {
	Token string
	Title string
	Body  string
}

// fcmRecorder is an http.RoundTripper standing in for Firebase. It never
// touches *testing.T: Send's push goroutine can outlive a test, and logging
// through a finished test panics.
type fcmRecorder struct {
	mu         sync.Mutex
	pushes     []recordedPush
	unexpected []string
}

// RoundTrip records an FCM send and answers it the way FCM does. Any other
// request, or a send whose body does not decode, is recorded as unexpected
// and refused.
func (r *fcmRecorder) RoundTrip(req *http.Request) (*http.Response, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if req.URL.Host != fcmSendHost || !strings.HasSuffix(req.URL.Path, "/messages:send") {
		r.unexpected = append(r.unexpected, req.Method+" "+req.URL.String())
		return nil, fmt.Errorf("fcmRecorder: unexpected request to %s", req.URL)
	}
	var payload struct {
		Message struct {
			Token        string `json:"token"`
			Notification struct {
				Title string `json:"title"`
				Body  string `json:"body"`
			} `json:"notification"`
		} `json:"message"`
	}
	if err := json.NewDecoder(req.Body).Decode(&payload); err != nil {
		r.unexpected = append(r.unexpected, "undecodable FCM body: "+err.Error())
		return nil, fmt.Errorf("fcmRecorder: decode FCM body: %w", err)
	}
	r.pushes = append(r.pushes, recordedPush{
		Token: payload.Message.Token,
		Title: payload.Message.Notification.Title,
		Body:  payload.Message.Notification.Body,
	})
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{"Content-Type": []string{"application/json"}},
		Body:       io.NopCloser(strings.NewReader(`{"name":"projects/test-project/messages/1"}`)),
		Request:    req,
	}, nil
}

// snapshot returns copies of what the recorder has seen so far.
func (r *fcmRecorder) snapshot() (pushes []recordedPush, unexpected []string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.pushes), slices.Clone(r.unexpected)
}

// newRecordingNotifier returns a Notifier whose FCM client talks only to a
// fresh recorder. The cached access token keeps accessTokenFor offline.
func newRecordingNotifier(pool *pgxpool.Pool) (*Notifier, *fcmRecorder) {
	rec := &fcmRecorder{}
	client := &fcmClient{
		projectID:    "test-project",
		accessToken:  "test-access-token",
		tokenExpires: time.Now().Add(time.Hour),
		httpClient:   &http.Client{Transport: rec},
	}
	return &Notifier{Pool: pool, fcm: client}, rec
}

// makeGuestNotifyUser inserts a real guest row (is_guest TRUE, no phone),
// matching what handlers.GuestRegister creates. Deleting the user cascades to
// its user_device_tokens rows.
func makeGuestNotifyUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	catSeq++
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (username, password_hash, role_id, active, staff_tier, is_guest, registration_status)
		 VALUES ($1, 'x', NULL, 1, 'user', TRUE, 'approved') RETURNING id`,
		fmt.Sprintf("pushguest%05d%04d", catRunTag, catSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert guest: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM app_notifications WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// registerTestDevice registers one English-language device for userID through
// the same RegisterDevice path POST /api/notifications/device uses.
func registerTestDevice(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	token := fmt.Sprintf("test-device-%05d-%d", catRunTag, userID)
	n := &Notifier{Pool: pool}
	if err := n.RegisterDevice(context.Background(), userID, 0, token, "android", "", "", "en"); err != nil {
		t.Fatalf("register device for user %d: %v", userID, err)
	}
	return token
}

// assertOnePushTo fails unless the recorder saw exactly one push, to token,
// carrying m's English title and body (the device registered as "en").
func assertOnePushTo(t *testing.T, rec *fcmRecorder, token string, m LocalizedMessage) {
	t.Helper()
	pushes, unexpected := rec.snapshot()
	if len(unexpected) > 0 {
		t.Fatalf("unexpected HTTP requests: %v", unexpected)
	}
	if len(pushes) != 1 {
		t.Fatalf("pushes = %d, want 1 for type %q: %+v", len(pushes), m.Type, pushes)
	}
	got := pushes[0]
	if got.Token != token || got.Title != m.Title.En || got.Body != m.Body.En {
		t.Fatalf("push = %+v, want token %q, title %q, body %q", got, token, m.Title.En, m.Body.En)
	}
}

// ─── Tests ──────────────────────────────────────────────────────────────

// TestGuestPush_NoChatPushReachesAGuestDevice is the leak itself. Every
// conversation template, sent to a guest with a registered phone, must not
// produce a single FCM request.
func TestGuestPush_NoChatPushReachesAGuestDevice(t *testing.T) {
	pool := newCategoryTestPool(t)
	guest := makeGuestNotifyUser(t, pool)
	registerTestDevice(t, pool, guest)

	for name, m := range conversationTemplates() {
		t.Run(name, func(t *testing.T) {
			n, rec := newRecordingNotifier(pool)
			if err := n.sendPush(context.Background(), guest, m); err != nil {
				t.Fatalf("sendPush(%s): %v", m.Type, err)
			}
			pushes, unexpected := rec.snapshot()
			if len(unexpected) > 0 {
				t.Fatalf("unexpected HTTP requests: %v", unexpected)
			}
			if len(pushes) != 0 {
				t.Fatalf("a guest's phone got %d push(es) of type %q: %+v; guests must not receive chat pushes",
					len(pushes), m.Type, pushes)
			}
		})
	}
}

// TestGuestPush_MemberStillGetsChatPushes pins that members are unchanged, and
// that the recorder really sees pushes, so the zero above is not vacuous.
func TestGuestPush_MemberStillGetsChatPushes(t *testing.T) {
	pool := newCategoryTestPool(t)
	member := makeNotifyUser(t, pool)
	token := registerTestDevice(t, pool, member)

	for name, m := range conversationTemplates() {
		t.Run(name, func(t *testing.T) {
			n, rec := newRecordingNotifier(pool)
			if err := n.sendPush(context.Background(), member, m); err != nil {
				t.Fatalf("sendPush(%s): %v", m.Type, err)
			}
			assertOnePushTo(t, rec, token, m)
		})
	}
}

// TestGuestPush_GuestKeepsNonChatPushes pins that the gate is about chats, not
// guests: all-user broadcasts and support-ticket updates still reach a
// guest's phone.
func TestGuestPush_GuestKeepsNonChatPushes(t *testing.T) {
	pool := newCategoryTestPool(t)
	guest := makeGuestNotifyUser(t, pool)
	token := registerTestDevice(t, pool, guest)

	templates := guestVisibleTemplates()
	// admin_announcement is built inline in handlers/push.go, not by a template.
	templates["admin_announcement"] = LocalizedMessage{
		Title: LocalText{En: "Announcement"},
		Body:  LocalText{En: "The office is closed on Friday."},
		Type:  "admin_announcement",
	}
	for name, m := range templates {
		t.Run(name, func(t *testing.T) {
			n, rec := newRecordingNotifier(pool)
			if err := n.sendPush(context.Background(), guest, m); err != nil {
				t.Fatalf("sendPush(%s): %v", m.Type, err)
			}
			assertOnePushTo(t, rec, token, m)
		})
	}
}

// TestGuestPush_UpgradedGuestGetsChatPushesAgain pins that the gate reads the
// live users.is_guest column. users.UpgradeGuestPhone flips it to FALSE, and
// from then on the account is a member like any other.
func TestGuestPush_UpgradedGuestGetsChatPushesAgain(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()
	upgraded := makeGuestNotifyUser(t, pool)
	token := registerTestDevice(t, pool, upgraded)
	if _, err := pool.Exec(ctx, `UPDATE users SET is_guest = FALSE WHERE id = $1`, upgraded); err != nil {
		t.Fatalf("upgrade guest: %v", err)
	}

	m := ChatNewMessageMsg("Donor", "the upgraded account sees this", 1)
	n, rec := newRecordingNotifier(pool)
	if err := n.sendPush(ctx, upgraded, m); err != nil {
		t.Fatalf("sendPush: %v", err)
	}
	assertOnePushTo(t, rec, token, m)
}

// TestGuestPush_SendStillStoresTheChatRow pins the other half of the decision:
// only the push is withheld. Send still writes the in-app row for a guest, and
// List (OPOS #26424) is what hides it.
//
// The Notifier has no FCM client, so the push goroutine Send starts cannot
// reach a recorder after this test has finished.
func TestGuestPush_SendStillStoresTheChatRow(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()
	guest := makeGuestNotifyUser(t, pool)

	n := &Notifier{Pool: pool}
	id, err := n.Send(ctx, guest, ChatNewMessageMsg("Donor", "the row is still written", 1))
	if err != nil || id <= 0 {
		t.Fatalf("Send(chat_message) to a guest: id=%d err=%v; the in-app row must still be written", id, err)
	}
	var storedType string
	if err := pool.QueryRow(ctx,
		`SELECT notification_type FROM app_notifications WHERE id = $1 AND user_id = $2`, id, guest,
	).Scan(&storedType); err != nil {
		t.Fatalf("read the stored row: %v", err)
	}
	if storedType != "chat_message" {
		t.Fatalf("stored notification_type = %q, want chat_message", storedType)
	}
}

// TestGuestPush_GuestLookupFailsClosedForChatTypesOnly pins what happens when
// the recipient's guest status cannot be read.
//
// For a chat type the push is withheld. Pushing a chat preview to a guest is
// the leak this fixes, and a withheld push still leaves the in-app row, so a
// member loses nothing they cannot open in the app. For every other type no
// lookup is made at all, so an outage can never mute a broadcast or a
// support-ticket update.
func TestGuestPush_GuestLookupFailsClosedForChatTypesOnly(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()

	t.Run("recipient row missing", func(t *testing.T) {
		// users.id is INTEGER, so this id fits the column and no fixture uses it.
		const missingUserID int64 = 2_000_000_000
		var exists bool
		if err := pool.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, missingUserID,
		).Scan(&exists); err != nil {
			t.Fatalf("check user %d: %v", missingUserID, err)
		}
		if exists {
			t.Fatalf("user %d exists in the test database; pick an id no row uses", missingUserID)
		}
		n := &Notifier{Pool: pool}
		if !n.shouldWithholdChatPush(ctx, missingUserID, "chat_message") {
			t.Fatalf("a chat push was allowed for user %d, whose guest status could not be read", missingUserID)
		}
	})

	t.Run("database unreachable", func(t *testing.T) {
		member := makeNotifyUser(t, pool)
		closed, err := pgxpool.NewWithConfig(ctx, pool.Config())
		if err != nil {
			t.Fatalf("open a second pool: %v", err)
		}
		closed.Close()
		n := &Notifier{Pool: closed}

		// A real member id, so only the failed lookup can withhold this push.
		if !n.shouldWithholdChatPush(ctx, member, "chat_message") {
			t.Fatalf("a chat push was allowed while users.is_guest could not be read")
		}
		for _, nonChat := range []string{"support_ticket_replied", "admin_announcement", "new_campaign"} {
			if n.shouldWithholdChatPush(ctx, member, nonChat) {
				t.Fatalf("a %q push was withheld during a lookup failure; only chat types fail closed", nonChat)
			}
		}
	})
}
