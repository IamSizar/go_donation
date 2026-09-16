// templates_group_alias_test.go pins how a masked chat-group push names its
// sender in each language (OPOS #26434).
//
// Why this exists: the server generates some masked-group labels itself, and
// always in English — "Donor 1", "Beneficiary 2", "Volunteer 3", "Member 4"
// (chatgroups.autoLabel), "Support" for staff and "Member" as the fallback
// (handlers.groupSenderLabel). GroupMaskedNewMessageMsg used to drop those
// verbatim into every language's title, so an Arabic member's push, and the
// Arabic title stored for the in-app notification list, read
// "رسالة من Donor 1". These tests pin the title per language, pin that a
// label outside the generated shapes is never touched, and pin that the
// real-name TEAM template is left exactly as it was. Pure: no database needed.
//
// The words, as the owner decided them on 2026-09-15:
//   - English keeps the server's own words. The app's chat bubbles show the
//     same English, so pushes, the in-app list and the bubbles all match.
//   - Arabic uses the app's role nouns (مانح، مستحق، متطوع، عضو). Staff sign
//     as فريق الدعم, not الدعم, which is already the app's word for Kafala
//     (TERMINOLOGY.md T10).
//   - Sorani (ckb) and Badini (kmr) reuse, character for character, the
//     translations the app already ships for its 'Donor', 'Beneficiary' and
//     'Volunteer' keys. "Member" has no Kurdish translation, and "Support" has
//     none meaning the support team, so both stay English there until a native
//     speaker supplies one (#21431: invented Kurdish is worse than a visible
//     English fallback).
package notify

import (
	"strings"
	"testing"
)

// localizedTitles flattens a message's title into a locale-keyed map so one
// table row can state all four expected languages side by side.
func localizedTitles(msg LocalizedMessage) map[string]string {
	return map[string]string{
		"en":  msg.Title.En,
		"ar":  msg.Title.Ar,
		"ckb": msg.Title.Ckb,
		"kmr": msg.Title.Kmr,
	}
}

// TestGroupMaskedNewMessageMsgLocalizesServerAliases pins the title for every
// label shape the server generates, in all four languages.
func TestGroupMaskedNewMessageMsgLocalizesServerAliases(t *testing.T) {
	for _, tc := range []struct {
		alias string
		want  map[string]string
	}{
		{
			alias: "Donor 1",
			want: map[string]string{
				"en":  "Message from Donor 1",
				"ar":  "رسالة من مانح 1",
				"ckb": "نامە لە بەخشەر 1",
				"kmr": "Peyam ji بەخشەر 1",
			},
		},
		{
			alias: "Beneficiary 2",
			want: map[string]string{
				"en":  "Message from Beneficiary 2",
				"ar":  "رسالة من مستحق 2",
				"ckb": "نامە لە وەرگری شایستە 2",
				"kmr": "Peyam ji وەرگرێ شایستە 2",
			},
		},
		{
			alias: "Volunteer 3",
			want: map[string]string{
				"en":  "Message from Volunteer 3",
				"ar":  "رسالة من متطوع 3",
				"ckb": "نامە لە خۆبەخش 3",
				"kmr": "Peyam ji خۆبەخش 3",
			},
		},
		{
			// No Kurdish word for "Member" exists: English stays in ckb/kmr.
			alias: "Member 4",
			want: map[string]string{
				"en":  "Message from Member 4",
				"ar":  "رسالة من عضو 4",
				"ckb": "نامە لە Member 4",
				"kmr": "Peyam ji Member 4",
			},
		},
		{
			// A multi-digit sequence number is carried over whole.
			alias: "Donor 12",
			want: map[string]string{
				"en":  "Message from Donor 12",
				"ar":  "رسالة من مانح 12",
				"ckb": "نامە لە بەخشەر 12",
				"kmr": "Peyam ji بەخشەر 12",
			},
		},
		{
			// Every staff message in a masked group is signed "Support". No
			// Kurdish word for the support team exists: English stays there.
			alias: "Support",
			want: map[string]string{
				"en":  "Message from Support",
				"ar":  "رسالة من فريق الدعم",
				"ckb": "نامە لە Support",
				"kmr": "Peyam ji Support",
			},
		},
		{
			alias: "Member",
			want: map[string]string{
				"en":  "Message from Member",
				"ar":  "رسالة من عضو",
				"ckb": "نامە لە Member",
				"kmr": "Peyam ji Member",
			},
		},
		{
			// An empty alias falls back to "Member", which is then localized.
			alias: "",
			want: map[string]string{
				"en":  "Message from Member",
				"ar":  "رسالة من عضو",
				"ckb": "نامە لە Member",
				"kmr": "Peyam ji Member",
			},
		},
	} {
		t.Run(tc.alias, func(t *testing.T) {
			got := localizedTitles(GroupMaskedNewMessageMsg(tc.alias, "hello there", 42))

			for locale, want := range tc.want {
				if got[locale] != want {
					t.Errorf("Title[%s] = %q, want %q", locale, got[locale], want)
				}
			}
		})
	}
}

// TestGroupMaskedNewMessageMsgEnglishKeepsServerWords pins the owner's English
// decision on its own: the English title carries the server's label exactly,
// never a renamed noun such as "Grantor" or "Eligible Recipient".
func TestGroupMaskedNewMessageMsgEnglishKeepsServerWords(t *testing.T) {
	for _, alias := range []string{"Donor 1", "Beneficiary 2", "Volunteer 3", "Member 4", "Support", "Member"} {
		t.Run(alias, func(t *testing.T) {
			msg := GroupMaskedNewMessageMsg(alias, "hi", 1)

			if msg.Title.En != "Message from "+alias {
				t.Errorf("Title.En = %q, want %q", msg.Title.En, "Message from "+alias)
			}
		})
	}
}

// TestGroupMaskedNewMessageMsgArabicCarriesNoEnglishNoun is the defect as the
// member saw it: the Arabic push for "Donor 1" named the sender in English.
// The body is the message preview, verbatim, in every language.
func TestGroupMaskedNewMessageMsgArabicCarriesNoEnglishNoun(t *testing.T) {
	msg := GroupMaskedNewMessageMsg("Donor 1", "hello there", 42)

	if !strings.Contains(msg.Title.Ar, "مانح 1") {
		t.Errorf("Title.Ar = %q, want it to contain %q", msg.Title.Ar, "مانح 1")
	}
	for _, text := range []string{msg.Title.Ar, msg.Body.Ar} {
		if strings.Contains(text, "Donor") {
			t.Errorf("Arabic text %q still contains the English noun %q", text, "Donor")
		}
	}
	for locale, body := range map[string]string{
		"en": msg.Body.En, "ar": msg.Body.Ar, "ckb": msg.Body.Ckb, "kmr": msg.Body.Kmr,
	} {
		if body != "hello there" {
			t.Errorf("Body[%s] = %q, want the preview verbatim", locale, body)
		}
	}
}

// TestGroupMaskedNewMessageMsgArabicSupportIsNotKafala pins TERMINOLOGY.md
// T10: the Arabic signature of a staff message must not be الدعم on its own,
// because the app already uses that exact word for Kafala.
func TestGroupMaskedNewMessageMsgArabicSupportIsNotKafala(t *testing.T) {
	msg := GroupMaskedNewMessageMsg("Support", "hi", 1)

	if msg.Title.Ar == "رسالة من الدعم" {
		t.Errorf("Title.Ar = %q, which names the Kafala section, not the support team", msg.Title.Ar)
	}
	if !strings.HasSuffix(msg.Title.Ar, "فريق الدعم") {
		t.Errorf("Title.Ar = %q, want it to end with %q", msg.Title.Ar, "فريق الدعم")
	}
}

// TestGroupMaskedNewMessageMsgKeepsCustomLabelsVerbatim pins that only the
// exact shapes the server writes are translated. A label staff typed in any
// other shape, including one that merely resembles a generated label, reaches
// every language as is.
func TestGroupMaskedNewMessageMsgKeepsCustomLabelsVerbatim(t *testing.T) {
	for _, alias := range []string{
		"Ahmad's family",
		"donor 1",      // case-sensitive: autoLabel capitalizes
		"Donor 0",      // sequence numbers start at 1
		"Donor 01",     // and never carry a leading zero
		"Donor",        // a noun without its number
		"Donors 1",     // not one of autoLabel's nouns
		"Donor  1",     // two spaces
		" Donor 1",     // leading space
		"Donor 1 ",     // trailing space
		"Donor 1\n",    // trailing newline
		"Donor -1",     // sign
		"Donor ١",      // Arabic-Indic digit: autoLabel writes ASCII
		"Support team", // "Support" only as the whole label
		"Staff 1",      // staff never gets a numbered label
	} {
		t.Run(alias, func(t *testing.T) {
			got := localizedTitles(GroupMaskedNewMessageMsg(alias, "hi", 1))
			want := map[string]string{
				"en":  "Message from " + alias,
				"ar":  "رسالة من " + alias,
				"ckb": "نامە لە " + alias,
				"kmr": "Peyam ji " + alias,
			}

			for locale, w := range want {
				if got[locale] != w {
					t.Errorf("Title[%s] = %q, want the label verbatim: %q", locale, got[locale], w)
				}
			}
		})
	}
}

// TestGroupTeamNewMessageMsgLeavesNamesUntouched pins the other half of the
// shared builder: a TEAM group shows real names, so nothing is translated there
// — not even a real name that happens to read like a generated alias.
func TestGroupTeamNewMessageMsgLeavesNamesUntouched(t *testing.T) {
	for _, name := range []string{"Donor 1", "Support", "Member", "Sara Ahmed"} {
		t.Run(name, func(t *testing.T) {
			got := localizedTitles(GroupTeamNewMessageMsg(name, "hi", 1))
			want := map[string]string{
				"en":  "Message from " + name,
				"ar":  "رسالة من " + name,
				"ckb": "نامە لە " + name,
				"kmr": "Peyam ji " + name,
			}

			for locale, w := range want {
				if got[locale] != w {
					t.Errorf("Title[%s] = %q, want the name verbatim: %q", locale, got[locale], w)
				}
			}
		})
	}

	// The empty-name fallback stays the English "Member" in every language,
	// exactly as it was before OPOS #26434.
	got := localizedTitles(GroupTeamNewMessageMsg("", "hi", 1))
	if got["ar"] != "رسالة من Member" {
		t.Errorf("team Title[ar] for an empty name = %q, want %q", got["ar"], "رسالة من Member")
	}
}
