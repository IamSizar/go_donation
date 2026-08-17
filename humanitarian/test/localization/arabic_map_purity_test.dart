// Guards the whole Arabic map at once, rather than one vocabulary at a time.
//
// WHY THIS FILE EXISTS
// The other files in this folder each pin ONE list — notification types,
// marketplace order statuses, case-review labels, interpolated key families.
// Every one of them was written after a client reported English on an Arabic
// screen. They work, but they only cover the vocabulary someone thought to
// enumerate, so the next leak lands in whatever nobody listed.
//
// This file takes the opposite approach and asserts a property of the MAP:
// whatever is in `_en`, its Arabic counterpart must actually be Arabic. That
// holds for the 2112 entries present today and for every entry added later,
// without anyone remembering to extend a list.
//
// THE SHAPE OF THE BUG IT CATCHES
// Adding a key means touching two `static const` maps. The tempting shortcut
// when the Arabic is not to hand is to paste the English into `_ar` as a
// placeholder and "fix it later". Nothing then fails: the key exists, key
// parity counts match, `.tr` returns a value, and the screen renders English
// to an Arabic reader — exactly what B21 reported and exactly what a
// map-coverage count cannot see. Group B of the client's notes is largely one
// long list of that mistake.
//
// WHEN THIS TEST FAILS
// A key was added to `_en` with no `_ar` entry, or with an `_ar` entry that is
// still English. Write the Arabic. If the value genuinely has no Arabic form —
// a brand, a bare interpolation format — add it to the allowlist below WITH a
// reason, so the exception is a decision on the record rather than a hole.
//
// Kurdish is deliberately NOT checked here. `_sorani`/`_badini` are allowed to
// be incomplete and fall back to English by design (see locale_routing_test),
// and inventing Kurdish to satisfy a test would be worse than the gap. The
// outstanding keys live in TRANSLATION_REQUEST.md.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

/// Values that are correct in Arabic *while containing Latin characters*.
///
/// Each is a proper noun or a technical token that is not translated anywhere
/// in the product, so a Latin substring in the Arabic string is intended.
/// Keep this list short and justified — it is the escape hatch, and a long
/// escape hatch is the same as no test.
const latinIsIntended = <String>[
  'Google', // brand — the sign-in button says "المتابعة باستخدام Google"
  'Firebase', // brand — infrastructure name shown in a diagnostic screen
  'Firestore', // brand — as above
  'FIB', // First Iraqi Bank, the payment provider's own Latin initialism
  'IQD', // ISO 4217 currency code, printed beside the Arabic د.ع
  'GPS', // used as an initialism in Arabic too
  'VIP', // marriage subscription tier, kept as the Latin initialism
  'Sign-In', // part of the Google Sign-In product name
  'name@example.com', // an email FORMAT example, not prose
  'zaid_ahmed', // a username FORMAT example — usernames are Latin, like the above
];

/// Entries whose Arabic is legitimately identical to the English.
///
/// Three only, and each is checked by hand rather than assumed:
///   • a format string made entirely of interpolation slots — there is no word
///     in it to translate;
///   • an email example;
///   • a bank's Latin initialism.
const arabicMayEqualEnglish = <String>[
  '@raised / @goal@suffix',
  'name@example.com',
  'FIB',
];

/// Strips everything that is allowed to be Latin, leaving only what would be
/// untranslated English if any letters remain.
///
/// Order matters, and it was got wrong on the first run: the allowlisted
/// literals must go FIRST. Stripping interpolation slots first ate the
/// `@example` out of `name@example.com` and then reported the `name` and `com`
/// left behind as untranslated English — a false positive manufactured by the
/// test's own cleanup.
String _stripPermittedLatin(String value) {
  var out = value;
  // Whole allowlisted tokens first, while they are still intact.
  for (final brand in latinIsIntended) {
    out = out.replaceAll(brand, '');
  }
  // GetX interpolation — `@name`, `@count`, `@amount`. Without this every
  // interpolated Arabic sentence would fail on its own placeholder.
  out = out.replaceAll(RegExp(r'@\w+'), '');
  // Dart interpolation that survives into the map as a literal — `$amount`.
  out = out.replaceAll(RegExp(r'\$\w+'), '');
  // Escape sequences written into the literal (`\n`, `\t`) — the escape LETTER
  // is not text the user ever sees.
  out = out.replaceAll(RegExp(r'\\[a-z]'), '');
  return out;
}

void main() {
  // `keys` is the only public door onto the private maps. 'en_US' is `_en` and
  // 'ar_SA' is `_ar` — the two Kurdish locales ride on 'ar_IQ'/'ar_TR' and are
  // deliberately out of scope here.
  final translations = AppTranslations().keys;
  final en = translations['en_US']!;
  final ar = translations['ar_SA']!;

  group('the Arabic map contains Arabic', () {
    test('every English key has an Arabic entry', () {
      final missing = en.keys.where((k) => !ar.containsKey(k)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'These keys exist in _en with no _ar entry, so `.tr` returns the '
            'ENGLISH KEY ITSELF on an Arabic screen — silently:\n'
            '${missing.join('\n')}',
      );
    });

    test('no Arabic value is still the English string', () {
      final untranslated =
          en.keys
              .where(
                (k) => ar[k] == en[k] && !arabicMayEqualEnglish.contains(k),
              )
              .toList()
            ..sort();
      expect(
        untranslated,
        isEmpty,
        reason:
            'The Arabic value is byte-identical to the English one, which means '
            'the English was pasted in as a placeholder. An Arabic reader sees '
            'English here:\n${untranslated.join('\n')}',
      );
    });

    test('no Latin letters survive into an Arabic value', () {
      // The assertion the client would actually make, mechanised: read the
      // Arabic UI and find a Latin character in it.
      final leaks = <String>[];
      for (final entry in ar.entries) {
        final residue = _stripPermittedLatin(entry.value);
        if (RegExp(r'[A-Za-z]').hasMatch(residue)) {
          leaks.add('${entry.key}  ->  ${entry.value}');
        }
      }
      leaks.sort();
      expect(
        leaks,
        isEmpty,
        reason:
            'Latin letters reached an Arabic label. If the word is a brand or a '
            'technical token, add it to `latinIsIntended` with a reason; '
            'otherwise translate it:\n${leaks.join('\n')}',
      );
    });
  });
}
