// fcm_payload_test.go pins the SHAPE of the FCM HTTP v1 body this backend
// sends, because the shape is the behaviour.
//
// THE BUG THESE TESTS GUARD
// The client's phones showed nothing while FCM answered 200 for every send.
// A push that is malformed for a platform is not an error FCM reports: it is
// accepted, forwarded, and silently dropped by the device. So "the call was
// made" proves nothing, and neither does "FCM said OK". The only thing worth
// asserting is the JSON that leaves this process.
//
// WHAT MUST BE TRUE, AND WHY
//   - a `notification` block — a data-only message draws no UI by itself, so a
//     backgrounded Android app would show nothing at all;
//   - android.priority "high" — otherwise a dozing device batches the message;
//   - android.notification.channel_id naming a channel the app created with
//     IMPORTANCE_HIGH — Android 8+ posts every notification to a channel, and
//     an unnamed one lands in FCM's fallback channel with no heads-up banner;
//   - apns-priority 10 + apns-push-type alert + aps.alert — without the
//     explicit APNs block FCM forwards a stripped payload that iOS drops;
//   - data alongside (never instead of) the notification block, all values
//     strings, so a tap can be routed.
//
// These run with no database and no network: buildSendPayload is pure.
package notify

import (
	"encoding/json"
	"testing"
)

// decodedPayload is buildSendPayload's result round-tripped through JSON, so
// the assertions see exactly what the wire sees (not the Go map).
func decodedPayload(t *testing.T, token, title, body, imageURL string,
	data map[string]string) map[string]any {
	t.Helper()
	raw, err := json.Marshal(buildSendPayload(token, title, body, imageURL, data))
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	return out
}

// child fetches a nested object, failing the test with the path if it is
// missing or not an object — a clearer failure than a nil map panic.
func child(t *testing.T, m map[string]any, path ...string) map[string]any {
	t.Helper()
	cur := m
	walked := ""
	for _, key := range path {
		walked += "." + key
		next, ok := cur[key].(map[string]any)
		if !ok {
			t.Fatalf("payload%s is missing or not an object (got %#v)", walked, cur[key])
		}
		cur = next
	}
	return cur
}

// sampleData is a routing payload like the one routingData builds.
var sampleData = map[string]string{
	"notification_type":   "chat_message",
	"related_entity_type": "chat_thread",
	"related_entity_id":   "42",
	"action_url":          "/chat/42",
}

func TestBuildSendPayload_CarriesANotificationBlock(t *testing.T) {
	p := decodedPayload(t, "tok", "Title", "Body", "", sampleData)
	msg := child(t, p, "message")
	if msg["token"] != "tok" {
		t.Fatalf("token = %#v, want %q", msg["token"], "tok")
	}
	notif := child(t, msg, "notification")
	if notif["title"] != "Title" || notif["body"] != "Body" {
		t.Fatalf("notification = %#v, want title/body Title/Body", notif)
	}
	if _, hasImage := notif["image"]; hasImage {
		t.Fatalf("no image URL was given but notification.image is set: %#v", notif)
	}
}

func TestBuildSendPayload_AndroidIsHighPriorityOnTheAppsChannel(t *testing.T) {
	p := decodedPayload(t, "tok", "Title", "Body", "", sampleData)
	android := child(t, p, "message", "android")
	if android["priority"] != "high" {
		t.Fatalf("android.priority = %#v, want %q", android["priority"], "high")
	}
	an := child(t, android, "notification")
	if an["channel_id"] != AndroidChannelID {
		t.Fatalf("android.notification.channel_id = %#v, want %q — a channel the "+
			"app did not create means no heads-up banner", an["channel_id"], AndroidChannelID)
	}
	if an["sound"] != "default" {
		t.Fatalf("android.notification.sound = %#v, want %q", an["sound"], "default")
	}
}

func TestBuildSendPayload_APNsHeadersAndAlertArePresent(t *testing.T) {
	p := decodedPayload(t, "tok", "Title", "Body", "", sampleData)
	apns := child(t, p, "message", "apns")
	headers := child(t, apns, "headers")
	if headers["apns-priority"] != "10" {
		t.Fatalf("apns-priority = %#v, want %q", headers["apns-priority"], "10")
	}
	if headers["apns-push-type"] != "alert" {
		t.Fatalf("apns-push-type = %#v, want %q", headers["apns-push-type"], "alert")
	}
	aps := child(t, apns, "payload", "aps")
	alert := child(t, aps, "alert")
	if alert["title"] != "Title" || alert["body"] != "Body" {
		t.Fatalf("aps.alert = %#v, want title/body Title/Body", alert)
	}
	if aps["sound"] != "default" {
		t.Fatalf("aps.sound = %#v, want %q", aps["sound"], "default")
	}
}

func TestBuildSendPayload_DataRidesAlongsideTheNotification(t *testing.T) {
	p := decodedPayload(t, "tok", "Title", "Body", "", sampleData)
	msg := child(t, p, "message")
	if _, ok := msg["notification"]; !ok {
		t.Fatal("data replaced the notification block; the OS would draw nothing")
	}
	data := child(t, msg, "data")
	for k, want := range sampleData {
		got, ok := data[k].(string)
		if !ok {
			t.Fatalf("data[%q] = %#v, want the string %q (FCM rejects non-strings in data)", k, data[k], want)
		}
		if got != want {
			t.Fatalf("data[%q] = %q, want %q", k, got, want)
		}
	}
}

func TestBuildSendPayload_EmptyDataValuesAreDropped(t *testing.T) {
	p := decodedPayload(t, "tok", "Title", "Body", "", map[string]string{
		"notification_type": "broadcast",
		"action_url":        "",
	})
	data := child(t, p, "message", "data")
	if _, present := data["action_url"]; present {
		t.Fatalf("empty action_url was sent anyway: %#v", data)
	}
	if data["notification_type"] != "broadcast" {
		t.Fatalf("data = %#v, want notification_type broadcast", data)
	}
}

func TestBuildSendPayload_NoDataMeansNoDataKey(t *testing.T) {
	p := decodedPayload(t, "tok", "Title", "Body", "", nil)
	msg := child(t, p, "message")
	if _, present := msg["data"]; present {
		t.Fatalf("an empty data block was sent: %#v", msg["data"])
	}
}

func TestBuildSendPayload_ImageGoesToBothPlatforms(t *testing.T) {
	const img = "https://example.test/banner.png"
	p := decodedPayload(t, "tok", "Title", "Body", img, nil)
	notif := child(t, p, "message", "notification")
	if notif["image"] != img {
		t.Fatalf("notification.image = %#v, want %q", notif["image"], img)
	}
	// iOS needs it on apns.fcm_options; the Notification Service Extension
	// downloads and attaches it from there.
	opts := child(t, p, "message", "apns", "fcm_options")
	if opts["image"] != img {
		t.Fatalf("apns.fcm_options.image = %#v, want %q", opts["image"], img)
	}
}

func TestRoutingData_MapsTheMessageFields(t *testing.T) {
	d := routingData(LocalizedMessage{
		Type:              "chat_message",
		RelatedEntityType: "chat_thread",
		RelatedEntityID:   42,
		ActionURL:         "/chat/42",
	})
	for k, want := range sampleData {
		if d[k] != want {
			t.Fatalf("routingData()[%q] = %q, want %q", k, d[k], want)
		}
	}
}

func TestRoutingData_OmitsAnUnsetEntityID(t *testing.T) {
	d := routingData(LocalizedMessage{Type: "broadcast"})
	if _, present := d["related_entity_id"]; present {
		t.Fatalf("related_entity_id present for a message with none: %#v", d)
	}
}
