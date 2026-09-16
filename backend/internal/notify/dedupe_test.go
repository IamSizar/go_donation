// dedupe_test.go pins the rule that decides whether Send writes a second
// notification, and therefore whether a second push ever leaves the server
// (OPOS #26481).
//
// THE GAP
// Send used to suppress any notification whose (user, EN title, EN body, type)
// matched a row that already existed — with no time limit and no reference to
// which entity the notification was about. Conversation templates repeat their
// text by design: MarriageChatNewMessageMsg is the fixed sentence "You have a
// new message in your Marriage chat." every single time, and a chat group
// carries the message preview, which repeats the moment somebody answers "ok"
// twice. So the FIRST message of a conversation pushed and every later one was
// silently dropped — for the rest of that user's life. That is exactly what the
// client saw: several staff replies in a marriage chat, no push on either
// phone.
//
// WHAT THE DEDUPE WAS FOR
// The comment it carried says it mirrors module_notify_user() in the PHP API:
// "re-running an admin action doesn't double-fire". That is a burst — an
// operator double-clicking Approve, or a retried request — seconds apart, about
// the same record. It is not a licence to mute a conversation forever.
//
// THE DECISION (see Send)
//   - Conversation types are exempt. Every one of them is written once per row
//     that was just inserted in its own table, so a repeat is a real second
//     message, never a retry artefact.
//   - Everything else is still deduped, now scoped to the same related entity
//     and to dedupeWindow, so the double-click is still swallowed and two
//     genuinely separate events are not.
//
// These tests need a throwaway Postgres and are skipped unless
// TEST_DATABASE_URL is set:
//
//	createdb godonation_dedupe
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_dedupe?sslmode=disable' \
//	  go test ./internal/notify/ -run Dedupe -v
package notify

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────

// waitForPushes polls the recorder until it has seen want pushes or the
// deadline passes, then returns everything it saw. Send fires its push in a
// goroutine, so a test cannot read the recorder straight after Send; polling
// keeps a passing run fast and still gives a failing one a definite answer.
func waitForPushes(t *testing.T, rec *fcmRecorder, want int) []recordedPush {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		pushes, unexpected := rec.snapshot()
		if len(unexpected) > 0 {
			t.Fatalf("unexpected HTTP requests: %v", unexpected)
		}
		if len(pushes) >= want || time.Now().After(deadline) {
			return pushes
		}
		time.Sleep(25 * time.Millisecond)
	}
}

// sendOrFail runs one Send and returns the id it wrote (0 = suppressed).
func sendOrFail(t *testing.T, n *Notifier, userID int64, m LocalizedMessage) int64 {
	t.Helper()
	id, err := n.Send(context.Background(), userID, m)
	if err != nil {
		t.Fatalf("Send(type=%s): %v", m.Type, err)
	}
	return id
}

// backdateNotifications pushes every stored notification of a user further
// into the past than the dedupe window, so the next Send sees an old row
// rather than a fresh one.
func backdateNotifications(t *testing.T, pool *pgxpool.Pool, userID int64) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`UPDATE app_notifications
		    SET created_at = created_at - make_interval(secs => $2)
		  WHERE user_id = $1`,
		userID, dedupeWindow.Seconds()*2); err != nil {
		t.Fatalf("backdate notifications: %v", err)
	}
}

// ─── The client's case: a conversation keeps pushing ─────────────────────

// TestDedupeMarriageChatSecondMessageStillPushes is the reported bug, at its
// smallest: the marriage-chat template has no sender, no preview and no
// varying word, so two messages in the same thread produce byte-identical
// notifications. Both must be stored and both must reach the phone.
func TestDedupeMarriageChatSecondMessageStillPushes(t *testing.T) {
	pool := newCategoryTestPool(t)
	uid := makeNotifyUser(t, pool)
	token := registerTestDevice(t, pool, uid)
	n, rec := newRecordingNotifier(pool)

	const threadID = int64(4771)
	first := sendOrFail(t, n, uid, MarriageChatNewMessageMsg(threadID))
	second := sendOrFail(t, n, uid, MarriageChatNewMessageMsg(threadID))

	if first == 0 || second == 0 || first == second {
		t.Fatalf("stored ids = %d, %d — both marriage-chat messages must be written as separate rows", first, second)
	}
	if got := countNotifications(t, pool, uid); got != 2 {
		t.Fatalf("notifications = %d, want 2 — the second message in a marriage chat was swallowed", got)
	}
	pushes := waitForPushes(t, rec, 2)
	if len(pushes) != 2 {
		t.Fatalf("pushes = %d, want 2 — the client's case: every message in a conversation pushes: %+v", len(pushes), pushes)
	}
	for _, p := range pushes {
		if p.Token != token {
			t.Fatalf("push went to %q, want the user's device %q", p.Token, token)
		}
	}
}

// TestDedupeChatGroupRepeatedTextStillPushes is the same bug in a chat group,
// where the body IS the message preview: answering "ok" twice used to push
// once. The alias and preview are deliberately identical in both sends.
func TestDedupeChatGroupRepeatedTextStillPushes(t *testing.T) {
	pool := newCategoryTestPool(t)
	uid := makeNotifyUser(t, pool)
	registerTestDevice(t, pool, uid)
	n, rec := newRecordingNotifier(pool)

	const groupID = int64(912)
	m := GroupMaskedNewMessageMsg("Donor 1", "ok", groupID)
	if id := sendOrFail(t, n, uid, m); id == 0 {
		t.Fatalf("the first chat-group message was not stored")
	}
	if id := sendOrFail(t, n, uid, m); id == 0 {
		t.Fatalf("the second identical chat-group message was suppressed as a duplicate")
	}
	if got := countNotifications(t, pool, uid); got != 2 {
		t.Fatalf("notifications = %d, want 2", got)
	}
	if pushes := waitForPushes(t, rec, 2); len(pushes) != 2 {
		t.Fatalf("pushes = %d, want 2 — repeating yourself in a group is still two messages: %+v", len(pushes), pushes)
	}
}

// ─── What the dedupe was protecting, still protected ─────────────────────

// TestDedupeStillSwallowsARepeatedAdminAction is the case the rule exists for:
// the same approval fired twice about the same donation, seconds apart. One
// notification, one push.
func TestDedupeStillSwallowsARepeatedAdminAction(t *testing.T) {
	pool := newCategoryTestPool(t)
	uid := makeNotifyUser(t, pool)
	registerTestDevice(t, pool, uid)
	n, rec := newRecordingNotifier(pool)

	m := DonationApprovedMsg("25,000", "IQD", "Winter Relief", "100,000", "500,000", 8801)
	if id := sendOrFail(t, n, uid, m); id == 0 {
		t.Fatalf("the first approval notification was not stored")
	}
	if id := sendOrFail(t, n, uid, m); id != 0 {
		t.Fatalf("the repeated approval was stored as row %d — a double-clicked admin action must not double-fire", id)
	}
	if got := countNotifications(t, pool, uid); got != 1 {
		t.Fatalf("notifications = %d, want 1", got)
	}
	// Give the (absent) second push every chance to show up before counting.
	if pushes := waitForPushes(t, rec, 2); len(pushes) != 1 {
		t.Fatalf("pushes = %d, want 1: %+v", len(pushes), pushes)
	}
}

// TestDedupeSeparatesTwoEntitiesWithTheSameWords: two different donations that
// happen to read identically are two events, not a retry. Before the entity id
// joined the key, the second one was lost.
func TestDedupeSeparatesTwoEntitiesWithTheSameWords(t *testing.T) {
	pool := newCategoryTestPool(t)
	uid := makeNotifyUser(t, pool)
	n, _ := newRecordingNotifier(pool)

	sendOrFail(t, n, uid, DonationApprovedMsg("25,000", "IQD", "Winter Relief", "100,000", "500,000", 9001))
	if id := sendOrFail(t, n, uid, DonationApprovedMsg("25,000", "IQD", "Winter Relief", "100,000", "500,000", 9002)); id == 0 {
		t.Fatalf("a second donation with the same wording was dropped as a duplicate of the first")
	}
	if got := countNotifications(t, pool, uid); got != 2 {
		t.Fatalf("notifications = %d, want 2 — two donations are two notifications", got)
	}
}

// TestDedupeExpiresWithTheWindow: the same wording about the same entity is a
// retry within seconds and a genuine re-send an hour later (a task re-assigned,
// a status set back and forth). Past the window it must arrive.
func TestDedupeExpiresWithTheWindow(t *testing.T) {
	pool := newCategoryTestPool(t)
	uid := makeNotifyUser(t, pool)
	n, _ := newRecordingNotifier(pool)

	m := TaskAssignedMsg("Deliver winter kits")
	sendOrFail(t, n, uid, m)
	backdateNotifications(t, pool, uid)
	if id := sendOrFail(t, n, uid, m); id == 0 {
		t.Fatalf("the same notification was still suppressed long after the dedupe window closed")
	}
	if got := countNotifications(t, pool, uid); got != 2 {
		t.Fatalf("notifications = %d, want 2", got)
	}
}

// ─── The two gates that must keep blocking ───────────────────────────────

// TestDedupeGuestStillGetsNoChatPush: letting repeats through must not hand a
// guest the chat previews OPOS #26443 withholds. Both rows are still written —
// List hides them — and neither reaches a device.
func TestDedupeGuestStillGetsNoChatPush(t *testing.T) {
	pool := newCategoryTestPool(t)
	guest := makeGuestNotifyUser(t, pool)
	registerTestDevice(t, pool, guest)
	n, rec := newRecordingNotifier(pool)

	m := GroupMaskedNewMessageMsg("Donor 1", "ok", 913)
	sendOrFail(t, n, guest, m)
	sendOrFail(t, n, guest, m)

	if got := countNotifications(t, pool, guest); got != 2 {
		t.Fatalf("notifications = %d, want 2 — the in-app rows are still written for a guest", got)
	}
	if pushes := waitForPushes(t, rec, 1); len(pushes) != 0 {
		t.Fatalf("pushes = %d, want 0 — a guest must never be pushed a chat preview: %+v", len(pushes), pushes)
	}
}

// TestDedupeCategoryPreferenceStillBlocksRepeats: a user who switched a
// category off must not start receiving it again just because repeats are now
// allowed through the dedupe. The category gate runs first, for every send.
func TestDedupeCategoryPreferenceStillBlocksRepeats(t *testing.T) {
	pool := newCategoryTestPool(t)
	uid := makeNotifyUser(t, pool)
	registerTestDevice(t, pool, uid)
	n, rec := newRecordingNotifier(pool)

	// MarriageChatNewMessageMsg's type resolves to the "normal" category.
	disableCategory(t, pool, uid, resolveCategory(MarriageChatNewMessageMsg(1).Type))
	sendOrFail(t, n, uid, MarriageChatNewMessageMsg(4772))
	sendOrFail(t, n, uid, MarriageChatNewMessageMsg(4772))

	if got := countNotifications(t, pool, uid); got != 0 {
		t.Fatalf("notifications = %d, want 0 — the user switched this category off", got)
	}
	if pushes := waitForPushes(t, rec, 1); len(pushes) != 0 {
		t.Fatalf("pushes = %d, want 0 — a switched-off category must stay silent: %+v", len(pushes), pushes)
	}
}
