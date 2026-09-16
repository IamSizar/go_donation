// group_alias.go — the Arabic and Kurdish words for the sender labels the
// server itself generates in masked chat groups (OPOS #26434).
//
// WHY THIS FILE EXISTS
// A masked chat group never shows a member's real name. Each member carries a
// label instead, and when staff type none the server writes one, in English:
//   - "Donor 1", "Beneficiary 2", "Volunteer 3", "Member 4" (chatgroups.autoLabel)
//   - "Support" for every staff sender (handlers.groupSenderLabel)
//   - "Member" when no label was resolved (GroupMaskedNewMessageMsg)
//
// GroupMaskedNewMessageMsg puts that label into the push title of each
// language, and the same titles are stored for the in-app notification list.
// Without this lookup an Arabic member read "رسالة من Donor 1".
//
// THE WORDS, AS THE OWNER DECIDED THEM (2026-09-15)
//   - English keeps the server's own words, exactly. The app's chat bubbles
//     show the same English, so pushes, the in-app list and the bubbles match.
//     That is why no row below has an "en" entry.
//   - Arabic uses the app's role nouns: مانح (TERMINOLOGY.md T12), مستحق (T4),
//     متطوع (T15) and عضو. A staff sender is فريق الدعم, the support team: the
//     bare الدعم is already the app's word for Kafala, and T10 settles that the
//     two must differ.
//   - Sorani (ckb) and Badini (kmr) are copied character for character from the
//     app's shipped translations of its 'Donor', 'Beneficiary' and 'Volunteer'
//     keys (_sorani and _badini in
//     humanitarian/lib/localization/app_translations.dart).
//   - "Member" has no Kurdish translation anywhere in the project. "Support"
//     has none that means the support team: the app's Kurdish for its bare
//     'Support' key is also its word for financial support. Both stay English
//     in ckb and kmr until a native speaker supplies them (#21431: invented
//     Kurdish is worse than a visible English fallback).
//
// Only the exact shapes the server writes are translated; any other label staff
// typed passes through untouched, in every language. A label staff happened to
// type in exactly one of those shapes ("Donor 5", "Support") is stored the same
// way as a generated one (MemberInput.Label in chatgroups.insertMembers and
// AddMember), so nothing can tell them apart and it is translated too — the
// same trade-off the app's chat bubbles make.
package notify

import "regexp"

// ─── The server's words ───

// groupMemberLabel is the neutral label the server uses when it has no better
// one: the empty-label fallback of both chat-group push templates.
const groupMemberLabel = "Member"

// supportSenderLabel is the server's English word for the support team. It
// signs staff in masked chat groups and names staff in the 1:1 donor-chat
// reply push (ChatSupportReplyMsg, OPOS #26483).
const supportSenderLabel = "Support"

// serverAliasPattern matches the label chatgroups.autoLabel writes: one of its
// four nouns, one space, and a sequence number counted from 1 with no leading
// zero. It is anchored and case-sensitive because autoLabel only ever writes
// exactly this shape; anything looser would also translate labels staff typed
// in other shapes.
// Go's `$` matches only at the very end of the text, so a trailing newline
// does not match either. The app gates its chat bubbles on the same pattern.
var serverAliasPattern = regexp.MustCompile(`^(Donor|Beneficiary|Volunteer|Member) ([1-9][0-9]*)$`)

// ─── Their words per language ───

// memberWords is "Member" per language code. English is absent because it
// keeps the server's word; Kurdish is absent because no translation exists.
var memberWords = map[string]string{"ar": "عضو"}

// groupAliasNouns maps each autoLabel noun to its word per language code. A
// language missing from a noun's row keeps the server's whole label as is.
var groupAliasNouns = map[string]map[string]string{
	"Donor":       {"ar": "مانح", "ckb": "بەخشەر", "kmr": "بەخشەر"},
	"Beneficiary": {"ar": "مستحق", "ckb": "وەرگری شایستە", "kmr": "وەرگرێ شایستە"},
	"Volunteer":   {"ar": "متطوع", "ckb": "خۆبەخش", "kmr": "خۆبەخش"},
	"Member":      memberWords,
}

// groupFixedLabels maps each whole label the server writes without a number,
// per language code, with the same fallback as groupAliasNouns.
var groupFixedLabels = map[string]map[string]string{
	supportSenderLabel: {"ar": "فريق الدعم"},
	groupMemberLabel:   memberWords,
}

// ─── Lookup ───

// localizedGroupAlias returns label as a masked chat-group push shows it in
// lang, one of the codes pickLocalizedText switches on ("en", "ar", "ckb",
// "kmr").
//
// A label the server generated comes back in lang's word, with its sequence
// number carried over exactly as written ("Donor 1" in "ar" is "مانح 1"). Any
// other label comes back unchanged, and so does a generated label with no
// word in lang: every label in "en", which keeps the server's words by
// decision, and every label in an unknown lang. It cannot fail, and it never
// turns a non-empty label into an empty one.
//
// Only for labels the server writes, never for real names: a team group's
// sender name must reach every language untouched even when it reads like an
// alias. Callers are the masked-group template and ChatSupportReplyMsg, which
// passes the fixed supportSenderLabel (OPOS #26483).
func localizedGroupAlias(label, lang string) string {
	if word, ok := groupFixedLabels[label][lang]; ok {
		return word
	}
	match := serverAliasPattern.FindStringSubmatch(label)
	if match == nil {
		return label
	}
	noun, number := match[1], match[2]
	word, ok := groupAliasNouns[noun][lang]
	if !ok {
		return label
	}
	return word + " " + number
}
