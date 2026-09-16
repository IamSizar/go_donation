package notify

import "testing"

func TestGroupMaskedNewMessageMsgUsesAliasNotRealName(t *testing.T) {
	msg := GroupMaskedNewMessageMsg("Donor 1", "hello there", 42)

	if msg.Type != "chat_group_message" {
		t.Fatalf("Type = %q, want %q", msg.Type, "chat_group_message")
	}
	if msg.RelatedEntityType != "chat_group_thread" || msg.RelatedEntityID != 42 {
		t.Fatalf("related entity = %s/%d, want chat_group_thread/42", msg.RelatedEntityType, msg.RelatedEntityID)
	}
	if msg.Title.En != "Message from Donor 1" {
		t.Fatalf("Title.En = %q, want it to contain the alias verbatim", msg.Title.En)
	}
	if msg.Body.En != "hello there" {
		t.Fatalf("Body.En = %q, want the preview verbatim", msg.Body.En)
	}
}

func TestGroupMaskedNewMessageMsgFallsBackWhenAliasEmpty(t *testing.T) {
	msg := GroupMaskedNewMessageMsg("", "hi", 1)
	if msg.Title.En != "Message from Member" {
		t.Fatalf("Title.En = %q, want a neutral fallback, not an empty name", msg.Title.En)
	}
}
