// Pins that the member-facing chat-group and connect-request copy calls the
// people behind it "our team" (فريقنا), never "staff" (الفريق) — OPOS #26351.
//
// WHY
// The chat-group sections, My Connect Requests and the chat lifecycle notices
// already said "our team"; the connect-request button and sheet said "staff".
// A member read two names for the same people inside one flow, and the
// decision on OPOS #26351 is "our team" everywhere a member reads it.
//
// WHAT IS PINNED
//   1. The six connect-request strings that said "staff" / الفريق read exactly
//      as decided, in English and in Arabic. (`connect_request_explainer`
//      already said فريقنا in Arabic; it is pinned so it stays that way.)
//   2. No English chat-group or connect-request value says "staff", and no
//      Arabic one says الفريق or موظف — so a string added later cannot bring
//      the old word back unnoticed.
//
// Kurdish is not checked: these keys have no Kurdish yet and render English
// (#21431), which (1) and (2) already cover.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

/// The key prefixes that make up the member-facing chat-group and
/// connect-request copy.
const _chatGroupPrefixes = [
  'chat_group_',
  'chat_groups_',
  'connect_request_',
  'error_chat_groups_',
  'error_connect_request',
];

/// The chat lifecycle notices. They are keyed by their own English because
/// the server sends that sentence and the app translates it.
const _lifecycleKeys = [
  'This conversation has been paused by our team.',
  'This conversation has been closed by our team.',
];

/// Arabic chat-group keys whose الفريق does NOT mean staff.
///
/// `chat_groups_my_team_groups` is "My Team Groups": the name of a KIND of
/// group — a team group, as opposed to a masked connection — translating the
/// English "Team", not "staff".
const _arabicTeamIsNotStaff = {'chat_groups_my_team_groups'};

/// The exact English the connect-request copy must read.
const _english = {
  'connect_request_action': 'Ask our team to connect me',
  'connect_request_title': 'Ask our team to connect you',
  'connect_request_explainer':
      'Our team will review your request. If they approve it, they will open '
      'a supervised chat for you here in the app.',
  'connect_request_message_hint':
      'Tell our team what you would like to discuss, and why.',
  'connect_request_sent': 'Request sent. Our team will review it shortly.',
  'connect_request_sent_body':
      'Our team will review it shortly. You can follow it in My Connect '
      'Requests on the Messages tab.',
};

/// The exact Arabic the connect-request copy must read. Each one uses فريقنا
/// the way the existing chat-group strings do ("يراجع فريقنا طلبك").
const _arabic = {
  'connect_request_action': 'اطلب التواصل عبر فريقنا',
  'connect_request_title': 'طلب تواصل عبر فريقنا',
  'connect_request_explainer':
      'سيراجع فريقنا طلبك، وإذا وافق عليه فسيفتح لك محادثة خاضعة للإشراف '
      'هنا في التطبيق.',
  'connect_request_message_hint': 'أخبر فريقنا بما تود مناقشته، ولماذا.',
  'connect_request_sent': 'تم إرسال الطلب. سيراجعه فريقنا قريبًا.',
  'connect_request_sent_body':
      'سيراجعه فريقنا قريبًا. يمكنك متابعته من «طلبات التواصل الخاصة بي» '
      'في تبويب «الرسائل».',
};

/// The entries of [map] that belong to the chat-group and connect-request
/// copy.
Map<String, String> _chatGroupCopy(Map<String, String> map) => {
  for (final entry in map.entries)
    if (_chatGroupPrefixes.any(entry.key.startsWith) ||
        _lifecycleKeys.contains(entry.key))
      entry.key: entry.value,
};

void main() {
  final en = AppTranslations.englishForTest;
  final ar = AppTranslations.arabicForTest;

  group('the connect-request copy reads as decided', () {
    for (final entry in _english.entries) {
      test('English ${entry.key}', () => expect(en[entry.key], entry.value));
    }
    for (final entry in _arabic.entries) {
      test('Arabic ${entry.key}', () => expect(ar[entry.key], entry.value));
    }
  });

  group('no chat-group or connect-request string says staff', () {
    test('the scan covers the whole copy, not an empty map', () {
      // Guards against a renamed prefix silently making the scans vacuous.
      final english = _chatGroupCopy(en);
      final arabic = _chatGroupCopy(ar);
      for (final key in [..._english.keys, ..._lifecycleKeys]) {
        expect(english, contains(key));
        expect(arabic, contains(key));
      }
      expect(english.length, greaterThan(30));
      expect(arabic.length, greaterThan(30));
    });

    test('English never says "staff"', () {
      final staff = RegExp(r'\bstaff\b', caseSensitive: false);
      final offenders = [
        for (final entry in _chatGroupCopy(en).entries)
          if (staff.hasMatch(entry.value)) '${entry.key}: ${entry.value}',
      ];
      expect(offenders, isEmpty);
    });

    test('Arabic never says الفريق or موظف', () {
      final staff = RegExp('الفريق|موظف');
      final offenders = [
        for (final entry in _chatGroupCopy(ar).entries)
          if (!_arabicTeamIsNotStaff.contains(entry.key) &&
              staff.hasMatch(entry.value))
            '${entry.key}: ${entry.value}',
      ];
      expect(offenders, isEmpty);
    });
  });
}
