// templates_group_test.go pins GroupTeamNewMessageMsg, the push template for a
// message posted in a real-name TEAM chat group (OPOS #26411). Its masked-group
// twin, GroupMaskedNewMessageMsg, is pinned in templates_chat_groups_test.go.
//
// Why this exists: team-group pushes used to reuse the donor-chat template
// ChatNewMessageMsg, which stamps RelatedEntityType "chat_thread" onto a
// chat-GROUP id. Group ids and donor thread ids are separate id spaces, so
// every stored notification row pointed at the wrong entity. These tests keep
// the team template on the chat-group vocabulary. Pure: no database needed.
package notify

import "testing"

// TestGroupTeamNewMessageMsgPointsAtTheChatGroup pins the notification type and
// the related entity: a team-group push must reference the chat group, never a
// donor chat_thread row that merely happens to share the same numeric id.
func TestGroupTeamNewMessageMsgPointsAtTheChatGroup(t *testing.T) {
	msg := GroupTeamNewMessageMsg("Sara Ahmed", "see you at the depot", 42)

	if msg.Type != "chat_group_message" {
		t.Fatalf("Type = %q, want %q", msg.Type, "chat_group_message")
	}
	if msg.RelatedEntityType != "chat_group_thread" {
		t.Fatalf("RelatedEntityType = %q, want %q", msg.RelatedEntityType, "chat_group_thread")
	}
	if msg.RelatedEntityID != 42 {
		t.Fatalf("RelatedEntityID = %d, want the group id 42", msg.RelatedEntityID)
	}
}

// TestGroupTeamNewMessageMsgCarriesSenderNameAndPreview pins the copy: a team
// group is real-name by design, so the title names the actual sender in every
// locale and the body is the message preview verbatim.
func TestGroupTeamNewMessageMsgCarriesSenderNameAndPreview(t *testing.T) {
	msg := GroupTeamNewMessageMsg("Sara Ahmed", "see you at the depot", 42)

	if msg.Title.En != "Message from Sara Ahmed" {
		t.Fatalf("Title.En = %q, want the real sender name verbatim", msg.Title.En)
	}
	if msg.Title.Ar != "رسالة من Sara Ahmed" {
		t.Fatalf("Title.Ar = %q, want the Arabic title with the real sender name", msg.Title.Ar)
	}
	for locale, body := range map[string]string{
		"en": msg.Body.En, "ar": msg.Body.Ar, "ckb": msg.Body.Ckb, "kmr": msg.Body.Kmr,
	} {
		if body != "see you at the depot" {
			t.Errorf("Body[%s] = %q, want the preview verbatim", locale, body)
		}
	}
}

// TestGroupTeamNewMessageMsgFallsBackWhenNameEmpty mirrors the masked twin's
// fallback test: an empty name must never produce "Message from ".
func TestGroupTeamNewMessageMsgFallsBackWhenNameEmpty(t *testing.T) {
	msg := GroupTeamNewMessageMsg("", "hi", 1)

	if msg.Title.En != "Message from Member" {
		t.Fatalf("Title.En = %q, want a neutral fallback, not an empty name", msg.Title.En)
	}
}
