// chat_types_test.go pins which notification types count as "chat" for the
// guest filter (OPOS #26424). Guests must not read chats, so List and the
// dashboard hide these types from a guest account.
//
// The list of types is explicit, not a prefix match, so these tests are
// what keeps it honest. They build every conversation template the backend
// sends and require its Type to be listed. They also build the templates a
// guest legitimately receives and require those to stay off the list. A new
// chat template that nobody adds to the list fails here, not in production.
//
// Pure unit tests: no database.
package notify

import (
	"slices"
	"testing"
)

// conversationTemplates is every template the backend sends about a
// conversation: donor↔owner and support chat, chat groups (masked and team),
// the staff-mediated marriage chat and its meeting-request outcome, and the
// internal staff chat.
func conversationTemplates() map[string]LocalizedMessage {
	return map[string]LocalizedMessage{
		"ChatRequestMsg":             ChatRequestMsg("Donor", "Winter Relief", 1),
		"ChatAcceptedMsg":            ChatAcceptedMsg("Owner", 1),
		"ChatNewMessageMsg":          ChatNewMessageMsg("Donor", "preview", 1),
		"GroupMaskedNewMessageMsg":   GroupMaskedNewMessageMsg("Donor 1", "preview", 1),
		"GroupTeamNewMessageMsg":     GroupTeamNewMessageMsg("Volunteer", "preview", 1),
		"MarriageChatRequestMsg":     MarriageChatRequestMsg(1),
		"MarriageChatAcceptedMsg":    MarriageChatAcceptedMsg(1),
		"MarriageChatNewMessageMsg":  MarriageChatNewMessageMsg(1),
		"MarriageMeetingDeclinedMsg": MarriageMeetingDeclinedMsg(),
		"StaffChatNewMessageMsg":     StaffChatNewMessageMsg("Colleague", "preview", 1),
	}
}

// guestVisibleTemplates is a sample of the templates a guest account receives
// today and must keep seeing: the all-user broadcasts, and the support TICKET
// round trip. GET /api/support/mine stays open to guests, so its notifications
// do too. They never quote the reply; they only say one arrived.
func guestVisibleTemplates() map[string]LocalizedMessage {
	return map[string]LocalizedMessage{
		"NewCampaignMsg":         NewCampaignMsg("Winter Relief", 1),
		"NewMediaPostMsg":        NewMediaPostMsg("News", 1),
		"NewPartnerMsg":          NewPartnerMsg("Partner", 1),
		"NewVolunteerMissionMsg": NewVolunteerMissionMsg("Mission", "Erbil", "Friday", 1),
		"SupportSubmittedMsg":    SupportSubmittedMsg("Card payment", 1),
		"SupportRepliedMsg":      SupportRepliedMsg("Card payment", 1),
		"SupportTicketStatusMsg": SupportTicketStatusMsg("Card payment", "resolved", 1),
	}
}

func TestChatNotificationTypes_CoverEveryConversationTemplate(t *testing.T) {
	chatTypes := ChatNotificationTypes()
	for name, msg := range conversationTemplates() {
		if !slices.Contains(chatTypes, msg.Type) {
			t.Errorf("%s writes type %q, which is not in ChatNotificationTypes — a guest would see it",
				name, msg.Type)
		}
	}
}

func TestChatNotificationTypes_LeaveGuestVisibleTypesAlone(t *testing.T) {
	chatTypes := ChatNotificationTypes()
	for name, msg := range guestVisibleTemplates() {
		if slices.Contains(chatTypes, msg.Type) {
			t.Errorf("%s writes type %q, which ChatNotificationTypes hides from guests — it must stay visible",
				name, msg.Type)
		}
	}
	// admin_announcement is built inline in handlers/push.go, not by a template.
	if slices.Contains(chatTypes, "admin_announcement") {
		t.Errorf("admin_announcement is hidden from guests — it is an all-user broadcast")
	}
}

// TestChatNotificationTypes_ReturnsACopy pins that a caller cannot edit the
// one shared list by writing into the slice it was handed.
func TestChatNotificationTypes_ReturnsACopy(t *testing.T) {
	first := ChatNotificationTypes()
	first[0] = "tampered"
	if ChatNotificationTypes()[0] == "tampered" {
		t.Fatalf("ChatNotificationTypes returned the shared slice; writes leak into the filter")
	}
}
