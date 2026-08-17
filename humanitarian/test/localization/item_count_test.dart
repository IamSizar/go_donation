// Pins that a count agrees with its noun.
//
// THE BUG
// The cart bar printed `'$totalQuantity ${'items'.tr}'`. One product in the
// cart rendered "1 items" in English and "1 عناصر" in Arabic — and the Arabic
// is the worse half: عناصر is the 3–10 plural, so the commonest case of all
// got a form that is ungrammatical rather than merely clumsy.
//
// Arabic marks number in four shapes to English's two, so a `count == 1 ? :`
// at the call site cannot express it. These tests pin all four boundaries,
// because the interesting ones (2, and the flip back to singular at 11) are
// exactly the ones an English-shaped implementation gets wrong.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/item_count.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  group('Arabic agrees with the count', () {
    setUp(() => Get.updateLocale(const Locale('ar', 'SA')));

    test('one is singular, not the 3-10 plural that shipped', () {
      expect(itemCountNoun(1), 'عنصر');
      expect(
        itemCountLabel(1),
        '1 عنصر',
        reason: 'this is the case the cart showed as "1 عناصر"',
      );
    });

    test('two is the dual, a form English does not have', () {
      expect(itemCountNoun(2), 'عنصران');
    });

    test('three to ten is the few-plural', () {
      for (final n in [3, 7, 10]) {
        expect(itemCountNoun(n), 'عناصر', reason: 'count $n');
      }
    });

    test('eleven and up return to the singular', () {
      for (final n in [11, 42, 100]) {
        expect(
          itemCountNoun(n),
          'عنصرًا',
          reason: 'count $n — an English-shaped plural gets this wrong',
        );
      }
    });

    test('zero does not claim the singular', () {
      expect(itemCountNoun(0), 'عنصرًا');
    });
  });

  group('English', () {
    setUp(() => Get.updateLocale(const Locale('en', 'US')));

    test('one is singular and everything else is plural', () {
      expect(itemCountLabel(1), '1 item');
      expect(itemCountLabel(2), '2 items');
      expect(itemCountLabel(11), '11 items');
    });
  });

  group('Kurdish keeps its word rather than being invented for', () {
    // Sorani and Badini have `items` and no count-specific forms. The helper
    // must fall back to it, NOT render the raw key — "items_one" on screen is
    // the failure mode this fallback exists to prevent.
    for (final locale in const [Locale('ar', 'IQ'), Locale('ar', 'TR')]) {
      test('$locale falls back to the uncounted noun', () {
        Get.updateLocale(locale);
        for (final n in [1, 2, 5, 11]) {
          final noun = itemCountNoun(n);
          expect(
            noun,
            isNot(startsWith('items_')),
            reason: 'count $n rendered a raw translation key',
          );
          expect(noun, isNotEmpty);
        }
      });
    }
  });
}
