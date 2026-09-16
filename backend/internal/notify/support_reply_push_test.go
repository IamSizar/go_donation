// support_reply_push_test.go pins how the push for a staff reply in a 1:1
// donor chat names the sender in each language (OPOS #26483).
//
// THE BUG
// handlers.ChatHandler's admin reply sent ChatNewMessageMsg("Support", ...),
// and that template drops its sender name verbatim into every language, so an
// Arabic user's phone, and the Arabic title stored for the in-app list, read
// «رسالة من Support».
//
// THE WORDS
//   - English keeps "Support", the server's own word.
//   - Arabic is فريق الدعم, the support team: the bare الدعم already means
//     Kafala (TERMINOLOGY.md T10). Same word the masked chat groups use
//     (groupFixedLabels in group_alias.go), so the support team has one name.
//   - Sorani and Badini have no translation meaning the support team, so they
//     keep the English word, as the chat-group alias does (OPOS #26468 tracks
//     the Kurdish push terms).
//
// The push tests reuse push_guest_test.go's FCM recorder and call sendPush
// directly, for the reason given there: Send pushes from a goroutine.
package notify

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
)

// supportReplyPreview is the message body every test sends.
const supportReplyPreview = "we have received your documents"

// registerDeviceInLanguage registers one device for userID with locale lang,
// through the same RegisterDevice path POST /api/notifications/device uses.
func registerDeviceInLanguage(t *testing.T, n *Notifier, userID int64, lang string) string {
	t.Helper()
	token := fmt.Sprintf("support-reply-%05d-%d-%s", catRunTag, userID, lang)
	if err := n.RegisterDevice(context.Background(), userID, 0, token, "android", "", "", lang); err != nil {
		t.Fatalf("register %s device for user %d: %v", lang, userID, err)
	}
	return token
}

// pushTitleInLanguage sends the staff-reply push to a fresh member whose one
// device speaks lang, and returns the title that reached the phone.
func pushTitleInLanguage(t *testing.T, lang string) string {
	t.Helper()
	pool := newCategoryTestPool(t)
	n, rec := newRecordingNotifier(pool)
	user := makeNotifyUser(t, pool)
	token := registerDeviceInLanguage(t, n, user, lang)

	if err := n.sendPush(context.Background(), user, ChatSupportReplyMsg(supportReplyPreview, 9)); err != nil {
		t.Fatalf("sendPush: %v", err)
	}
	pushes, unexpected := rec.snapshot()
	if len(unexpected) > 0 {
		t.Fatalf("unexpected HTTP requests: %v", unexpected)
	}
	if len(pushes) != 1 || pushes[0].Token != token {
		t.Fatalf("pushes = %+v, want exactly one to %q", pushes, token)
	}
	if pushes[0].Body != supportReplyPreview {
		t.Errorf("body = %q, want the preview %q", pushes[0].Body, supportReplyPreview)
	}
	return pushes[0].Title
}

// ─── The push that reaches the phone ───

func TestSupportReplyPush_ArabicPhoneReadsSupportTeam(t *testing.T) {
	title := pushTitleInLanguage(t, "ar")
	if title != "رسالة من فريق الدعم" {
		t.Errorf("Arabic title = %q, want %q", title, "رسالة من فريق الدعم")
	}
	if strings.Contains(title, "Support") {
		t.Errorf("Arabic title %q still carries the English word", title)
	}
}

func TestSupportReplyPush_EnglishPhoneStillReadsSupport(t *testing.T) {
	if title := pushTitleInLanguage(t, "en"); title != "Message from Support" {
		t.Errorf("English title = %q, want %q", title, "Message from Support")
	}
}

// ─── The stored titles, all four languages ───

func TestSupportReplyPush_TitlePerLanguage(t *testing.T) {
	m := ChatSupportReplyMsg(supportReplyPreview, 9)
	want := map[string]string{
		"en":  "Message from Support",
		"ar":  "رسالة من فريق الدعم",
		"ckb": "نامە لە Support",
		"kmr": "Peyam ji Support",
	}
	for lang, got := range localizedTitles(m) {
		if got != want[lang] {
			t.Errorf("%s title = %q, want %q", lang, got, want[lang])
		}
	}
	if m.Type != "chat_message" || m.RelatedEntityType != "chat_thread" || m.RelatedEntityID != 9 {
		t.Errorf("routing = %q/%q/%d, want chat_message/chat_thread/9",
			m.Type, m.RelatedEntityType, m.RelatedEntityID)
	}
}

// ─── The handler ───
//
// A source check: the admin reply sends its pushes from goroutines with no
// seam to wait on. What matters is that it uses the localized template.
func TestSupportReplyPush_AdminReplyHandlerUsesTheTemplate(t *testing.T) {
	const path = "../handlers/chat.go"
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	source := string(raw)
	if !strings.Contains(source, "notify.ChatSupportReplyMsg(preview, id)") {
		t.Errorf("%s does not send notify.ChatSupportReplyMsg for a staff reply", path)
	}
	if strings.Contains(source, `ChatNewMessageMsg("Support"`) {
		t.Errorf("%s still hard-codes the English sender \"Support\"", path)
	}
}
