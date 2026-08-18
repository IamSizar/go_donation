// Pins that the الفعاليات module never calls itself الزواج to a user.
//
// THE BUG
// The module was rebranded from Marriage to Events at the tab and hub level
// only. Tapping «منشورات الفعاليات» opened a screen headed «منشورات الزواج»,
// so one journey showed the user two different names for the same section.
//
// WHY THIS TEST IS SHAPED THIS WAY
// The fix was to the VALUES in app_translations, never the keys: the ar/ckb
// /kmr maps are keyed by the English sentence the server sends, so renaming a
// key would stop the server's string matching and fall back to English. This
// test therefore asserts on what a reader SEES (values), and separately that
// the server-facing keys still exist.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

void main() {
  final keys = AppTranslations().keys;

  test('no Arabic string shows the old الزواج wording', () {
    final ar = keys['ar_SA'] ?? const {};
    final offenders = ar.entries
        .where((e) => e.value.contains('الزواج'))
        .map((e) => '${e.key} -> ${e.value}')
        .toList();
    expect(offenders, isEmpty,
        reason: 'these strings still say الزواج inside the الفعاليات module');
  });

  test('no English string shows the old Marriage wording', () {
    final en = keys['en_US'] ?? const {};
    final offenders = en.entries
        .where((e) => e.value.toLowerCase().contains('marriage'))
        .map((e) => '${e.key} -> ${e.value}')
        .toList();
    expect(offenders, isEmpty,
        reason: 'these strings still say Marriage inside the Events module');
  });

  test('server-sent English keys still resolve, and resolve to Events wording',
      () {
    // The rename must not have orphaned the keys the backend sends. If these
    // disappeared, an Arabic reader would silently get English back.
    const serverSent = [
      'Marriage posts',
      'Marriage section',
      'Search marriage profiles by name or gender',
      'News and stories from the marriage section',
    ];
    final ar = keys['ar_SA'] ?? const {};
    for (final key in serverSent) {
      expect(ar.containsKey(key), isTrue,
          reason: '$key is sent by the backend and must still translate');
      expect(ar[key]!.contains('الفعاليات'), isTrue,
          reason: '$key must now resolve to the Events wording');
    }
  });
}
