// Shows a chat-group sender label in the reader's language (OPOS #26419).
//
// WHY THIS FILE EXISTS
// The server writes a few labels itself, and always in English:
//   * "Donor 1", "Beneficiary 2", "Volunteer 3", "Member 4" — the alias each
//     masked-group member gets at creation when staff type none (autoLabel in
//     backend/internal/chatgroups/chatgroups.go);
//   * "Support" — every staff message in a masked group (ListMessagesForMember
//     in chatgroups_reads.go);
//   * "Member" — the fallback for a sender with no label or no profile name.
// The bubble drew those verbatim, so an Arabic member read English names
// above messages in an Arabic chat.
//
// WHY IN THE APP, AND WHY EVERY LABEL
// The server could send structured fields instead, but that is an API change
// needing a backend release in step with the app. Recognising the exact
// strings the server generates needs neither. The conversation screen is
// never told the group's kind, so this runs on every label. That is safe: only
// the generated shapes match, and a staff-typed label or a team member's real
// name would have to be literally "Support" or "Donor 3" to be translated —
// which would translate a word that already meant exactly that.
//
// Anything else — every custom label and every real name — is returned
// untouched.
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

// ─── The server's words ───

/// The label the server gives every staff message in a masked group.
const _serverSupport = 'Support';

/// The label the server falls back to for a sender with no label or name.
const _serverMember = 'Member';

/// The server's auto-generated alias: one of its nouns, one space, and a
/// sequence number counted from 1 with no leading zeros. Anchored, and
/// case-sensitive, because autoLabel only ever writes exactly this shape.
final _serverAlias = RegExp(
  r'^(Donor|Beneficiary|Volunteer|Member) ([1-9][0-9]*)$',
);

/// The translation key for each noun autoLabel writes. `@n` is the number.
const _aliasKeys = {
  'Donor': 'chat_group_sender_donor_n',
  'Beneficiary': 'chat_group_sender_beneficiary_n',
  'Volunteer': 'chat_group_sender_volunteer_n',
  'Member': 'chat_group_sender_member_n',
};

/// The translation key for each whole label the server writes.
const _fixedKeys = {
  _serverSupport: 'chat_group_sender_support',
  _serverMember: 'chat_group_sender_member',
};

// ─── Mapping ───

/// [label] as the reader should see it.
///
/// A label the server generated comes back in the current language, with its
/// number formatted for that language. Every other label — and any label whose
/// translation is missing — comes back exactly as sent.
String localizedSenderLabel(String label) {
  final fixedKey = _fixedKeys[label];
  if (fixedKey != null) return _translated(fixedKey) ?? label;

  final match = _serverAlias.firstMatch(label);
  if (match == null) return label;
  // A number too large for an int is not one the server wrote; show it as is.
  final number = int.tryParse(match.group(2)!);
  if (number == null) return label;

  final template = _translated(_aliasKeys[match.group(1)!]!);
  if (template == null) return label;
  return template.replaceAll('@n', _formatNumber(number));
}

/// [key]'s translation, or null when the current language has none.
///
/// GetX echoes the key back on a miss; showing the server's English label is
/// better than showing a key name.
String? _translated(String key) {
  final value = key.tr;
  return value == key ? null : value;
}

/// [number] in the digits of the current language, without grouping.
///
/// The locale comes from [AppLocaleService.dateFormatLocale] — the one the app
/// pins as `Intl.defaultLocale` — so the number matches the digits of the time
/// printed under the same bubble. Under intl 0.20.2 that is ASCII digits for
/// Arabic too, as on every other number and date in the app. Grouping is off
/// because an alias number is a name, not a quantity.
String _formatNumber(int number) {
  final locale = AppLocaleService.dateFormatLocale(Get.locale);
  final format = NumberFormat.decimalPattern(locale)..turnOffGrouping();
  return format.format(number);
}
