// Guards the "literal handed to a widget that translates it" failure.
//
// THE SHAPE OF THE BUG
// Some widgets take a plain String and apply `.tr` themselves — AppEmpty
// documents "Translated via `.tr`" on its title and message, and
// authInputDecoration runs both `label.tr` and `hintText.tr`. So their call
// sites correctly pass a bare literal:
//
//     AppEmpty(title: 'No places in this sector', message: '...')
//     authInputDecoration(context, label: 'Username'.tr, hintText: 'guest_name')
//
// which reads as already-handled and is invisible to a grep for missing `.tr`.
// If that literal is not a key, GetX returns it unchanged: English text lands
// in the Arabic UI, and a developer-shaped string lands in every UI.
//
// Both shipped. `hintText: 'guest_name'` was in neither map, so the guest
// sign-in box showed the literal placeholder "guest_name" to every user in
// every language. And the City Guide's sub-category empty state passed two
// English sentences that existed nowhere, one level below a sector empty state
// whose equivalents were translated properly.
//
// WHY IT IS SCOPED TO THESE TWO
// The check needs to know which parameters get `.tr` applied downstream, and
// that is a property of each widget, not something inferable from a call site.
// These are the two proven ones. Add to `_translatingProps` when another
// widget documents the same contract — the scan is generic, only the list is
// hand-maintained.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

/// widget-constructor → the parameters whose literal it will run through `.tr`.
const Map<String, List<String>> _translatingProps = {
  'AppEmpty': ['title', 'message', 'actionLabel'],
  'authInputDecoration': ['label', 'hintText'],
};

/// A literal argument written directly at a call site, e.g. `title: 'Foo'`.
/// Interpolated values are skipped — the cross-product of those is pinned by
/// interpolated_keys_test.dart instead.
final RegExp _literalArg = RegExp(r"""(\w+)\s*:\s*'((?:[^'\\\n]|\\.)*)'""");

void main() {
  final translations = AppTranslations().keys;
  final en = translations['en_US']!;
  final ar = translations['ar_SA']!;

  test(
    'literals passed to translating widgets resolve in English and Arabic',
    () {
      final failures = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('app_translations.dart')) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

          for (final entry in _translatingProps.entries) {
            // Only look at lines near a call to that constructor: the argument
            // and the constructor are usually on separate lines, so scan a small
            // window after each occurrence.
            if (!lines
                .skip(i > 12 ? i - 12 : 0)
                .take(13)
                .any((l) => l.contains('${entry.key}('))) {
              continue;
            }
            for (final match in _literalArg.allMatches(line)) {
              final prop = match.group(1)!;
              final value = match.group(2)!;
              if (!entry.value.contains(prop)) continue;
              // A literal already carrying .tr at the call site is fine, and so
              // is one with no letters (an icon glyph, a separator).
              if (line.contains("'.tr")) continue;
              if (!RegExp(r'[A-Za-z]{3}').hasMatch(value)) continue;

              final where = '${entity.path}:${i + 1}';
              if (!en.containsKey(value)) {
                failures.add('$where  $prop: "$value" — no English entry');
              } else if (!ar.containsKey(value)) {
                failures.add('$where  $prop: "$value" — no Arabic entry');
              }
            }
          }
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'These strings are handed to a widget that applies .tr, but have no '
            'entry behind them. GetX returns the key unchanged, so each one '
            'renders verbatim on screen:\n  ${failures.join('\n  ')}',
      );
    },
  );

  // The guest sign-up sheet used to be pinned here too — it had a username
  // hint that rendered as its own key. Entering as a guest is a single tap
  // now: no sheet, no fields, no hints, so there is nothing left to pin.

  test('the City Guide sub-category empty state is translated', () {
    const title = 'No places in this sub-category';
    const message =
        'Nothing here has been tagged with this sub-category yet. '
        'Clear it to see the whole sector.';
    for (final key in [title, message]) {
      expect(en.containsKey(key), isTrue, reason: 'missing English: $key');
      expect(ar.containsKey(key), isTrue, reason: 'missing Arabic: $key');
      expect(
        ar[key],
        isNot(en[key]),
        reason: 'the Arabic entry for "$key" is still the English sentence',
      );
    }
  });
}
