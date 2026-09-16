// chat_group_push_message_test.go pins groupMessageFor, the pure choice of
// push template that notifyGroupMembers makes for each chat-group message
// (OPOS #26411).
//
// Why this exists: the team branch used to send the donor-chat template
// ChatNewMessageMsg, which labels the chat-GROUP id as a "chat_thread", a
// different table whose ids overlap by accident. Every stored notification row
// for a team-group message therefore pointed at the wrong conversation. This
// table keeps both kinds on the chat-group vocabulary, and keeps a masked group
// on its own template, fed the alias the caller resolved and nothing else.
// Pure: no database needed, unlike chat_group_test.go next to it.
package handlers

import (
	"reflect"
	"strings"
	"testing"

	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/notify"
)

func TestGroupMessageForPicksTheTemplateByKind(t *testing.T) {
	const (
		groupID = int64(42)
		preview = "see you at the depot"
	)
	for _, tc := range []struct {
		name  string
		kind  chatgroups.Kind
		label string
		want  notify.LocalizedMessage
	}{
		{
			name:  "masked group sends the masked template with the alias",
			kind:  chatgroups.KindMasked,
			label: "Donor 1",
			want:  notify.GroupMaskedNewMessageMsg("Donor 1", preview, groupID),
		},
		{
			name:  "team group sends the team template with the real name",
			kind:  chatgroups.KindTeam,
			label: "Sara Ahmed",
			want:  notify.GroupTeamNewMessageMsg("Sara Ahmed", preview, groupID),
		},
		{
			// Unreachable today (migration 120 CHECKs kind IN ('masked','team')),
			// but if a new kind ever appears it must fail closed onto the masked
			// template, the same way groupSenderLabel treats every non-team kind.
			name:  "unknown kind fails closed onto the masked template",
			kind:  chatgroups.Kind("broadcast"),
			label: "Support",
			want:  notify.GroupMaskedNewMessageMsg("Support", preview, groupID),
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := groupMessageFor(tc.kind, tc.label, preview, groupID)

			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("groupMessageFor(%q) = %+v, want %+v", tc.kind, got, tc.want)
			}
			// Spelled out as well, so a regression reads as the bug it is
			// rather than as a struct diff.
			if got.Type != "chat_group_message" {
				t.Errorf("Type = %q, want %q", got.Type, "chat_group_message")
			}
			if got.RelatedEntityType != "chat_group_thread" || got.RelatedEntityID != groupID {
				t.Errorf("related entity = %s/%d, want chat_group_thread/%d",
					got.RelatedEntityType, got.RelatedEntityID, groupID)
			}
			if !strings.Contains(got.Title.En, tc.label) {
				t.Errorf("Title.En = %q, want it to carry the resolved label %q", got.Title.En, tc.label)
			}
		})
	}
}

// TestGroupMessageForMaskedUsesOnlyTheGivenAlias pins the privacy half: for a
// masked group the title is built from the alias the caller passed, so the
// sender's real name can only leak if a caller passes it in, which
// groupSenderLabel never does for a masked group.
func TestGroupMessageForMaskedUsesOnlyTheGivenAlias(t *testing.T) {
	got := groupMessageFor(chatgroups.KindMasked, "Beneficiary 2", "hello", 7)

	if got.Title.En != "Message from Beneficiary 2" {
		t.Fatalf("Title.En = %q, want exactly the alias", got.Title.En)
	}
}
