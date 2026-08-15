// Pins WHICH translation map a locale resolves to, and what happens when the
// map does not have the key.
//
// WHY THIS FILE EXISTS
// The four maps are registered with GetX under `en_US`, `ar_SA`, `ar_IQ`
// (Sorani) and `ar_TR` (Badini). Reusing the `ar` language code for the two
// Kurdish variants is deliberate — Kurdish has no `GlobalMaterialLocalizations`
// data and is not in GetX's `rtlLanguages` list, so registering it as `ckb`/
// `kmr` would flip the whole Kurdish UI left-to-right and hand Material an
// unsupported locale. See the note on `AppTranslations.keys`.
//
// The cost of that choice is a trap inside GetX. When a key is missing from
// the exact `<lang>_<country>` bucket, `Trans.tr` falls back to a bucket keyed
// by language code ALONE, which it builds with
// `Get.translations.map((k, v) => MapEntry(k.split('_').first, v))`. That
// collapses `ar_SA`, `ar_IQ` and `ar_TR` onto a single `ar` entry, and the
// LAST one registered wins. So a key missing from Sorani used to resolve to
// the BADINI string rather than to English.
//
// That matters because Kurdish is deliberately incomplete: invented Kurdish is
// worse than a visible English fallback (issue #21431), and the contaminated
// Arabic values sitting in the Kurdish maps are being REMOVED so they fall back
// to English. Those removals are only safe if the fallback really is English.
// These tests pin that it is.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

void main() {
  final published = AppTranslations().keys;
  final english = AppTranslations.englishForTest;
  final arabic = AppTranslations.arabicForTest;
  final sorani = AppTranslations.soraniForTest;
  final badini = AppTranslations.badiniForTest;

  setUp(() {
    Get.clearTranslations();
    Get.addTranslations(published);
    Get.fallbackLocale = const Locale('en', 'US');
  });

  /// A key that English defines and [map] does not — i.e. one that must
  /// degrade to English rather than to another language.
  String untranslatedKeyIn(Map<String, String> map) {
    final key = english.keys.firstWhere(
      (k) => !map.containsKey(k) && english[k]!.trim().isNotEmpty,
      orElse: () => '',
    );
    expect(
      key,
      isNotEmpty,
      reason: 'Expected at least one English key with no Kurdish translation; '
          'without one this test proves nothing.',
    );
    return key;
  }

  group('an untranslated Kurdish key degrades to ENGLISH', () {
    test('Sorani falls back to English, never to Badini', () {
      final key = untranslatedKeyIn(sorani);
      Get.locale = const Locale('ar', 'IQ');

      expect(
        key.tr,
        english[key],
        reason: 'A key with no Sorani translation must show the English '
            'string. Showing Badini would be wrong-language text, which never '
            'falls back and is worse than a missing translation.',
      );
      if (badini.containsKey(key)) {
        expect(key.tr, isNot(badini[key]));
      }
      expect(key.tr, isNot(arabic[key]));
    });

    test('Badini falls back to English, never to Sorani', () {
      final key = untranslatedKeyIn(badini);
      Get.locale = const Locale('ar', 'TR');

      expect(key.tr, english[key]);
      if (sorani.containsKey(key)) {
        expect(key.tr, isNot(sorani[key]));
      }
      expect(key.tr, isNot(arabic[key]));
    });

    test(
      'REMOVING a contaminated Kurdish value yields English, not the other '
      'Kurdish map',
      () {
        // The exact shape of the contamination fix: a key translated in both
        // Kurdish maps has its Sorani value removed. Sorani users must then
        // read English — not the Badini string, which carries the same
        // untranslated Arabic word the removal was meant to eliminate.
        const key = 'Eligibles';
        expect(english.containsKey(key), isTrue);

        // Remove from the RAW Sorani map and republish it the way
        // AppTranslations does — English underneath. This is exactly what
        // deleting the entry from the source file produces.
        final rawSoraniMinusOne = Map<String, String>.from(sorani)
          ..remove(key);
        Get.clearTranslations();
        Get.addTranslations({
          'en_US': english,
          'ar_IQ': {...english, ...rawSoraniMinusOne},
          'ar_TR': {...english, ...badini},
          'ar_SA': arabic,
        });
        Get.locale = const Locale('ar', 'IQ');

        expect(key.tr, english[key]);
      },
    );
  });

  group('Arabic is never served Kurdish', () {
    test('ar_SA resolves to the Arabic map', () {
      Get.locale = const Locale('ar', 'SA');
      expect('Volunteer'.tr, arabic['Volunteer']);
    });

    test('a bare "ar" locale with no region resolves to Arabic', () {
      // No app code produces this today — AppLocaleService always attaches a
      // region — but GetX matches `<lang>_<country>` first, so a bare `ar`
      // misses every bucket and lands in the collapsed one. That collapsed
      // bucket must be Arabic. It used to be Badini.
      Get.locale = const Locale('ar');
      final shown = 'Volunteer'.tr;

      expect(shown, arabic['Volunteer']);
      expect(shown, isNot(sorani['Volunteer']));
      expect(shown, isNot(badini['Volunteer']));
    });

    test('an unregistered Arabic region (e.g. ar_EG) resolves to Arabic', () {
      Get.locale = const Locale('ar', 'EG');
      expect('Volunteer'.tr, arabic['Volunteer']);
    });
  });

  group('the registration itself', () {
    test('every locale bucket the app can select is registered', () {
      expect(published.keys, containsAll(['en_US', 'ar_SA', 'ar_IQ', 'ar_TR']));
    });

    test(
      'the collapsed language-only bucket GetX builds resolves to Arabic',
      () {
        // Reproduces GetX Trans._getSimilarLanguageTranslation exactly. If a
        // future edit reorders `keys` so a Kurdish map is registered last,
        // this fails — which is the regression that shipped Badini to Arabic
        // readers.
        final collapsed = published.map(
          (k, v) => MapEntry(k.split('_').first, v),
        );
        expect(collapsed['ar']!['Volunteer'], arabic['Volunteer']);
      },
    );
  });
}
