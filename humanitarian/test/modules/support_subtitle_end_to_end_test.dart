// The whole subtitle line, not its ingredients.
//
// WHY THIS FILE EXISTS SEPARATELY FROM application_subtitle_l10n_test.dart
// That file pins the PARTS: that `'submitted'.tr` returns Arabic, that
// `localizedScheduleSummary` turns a day key into «إثن». Every one of those
// assertions passed while the owner was still looking at
// "submitted - duhok - Mon 09:00-17:00" on an Arabic screen, because the
// defect was never in a part — it was in the line that JOINS them, which no
// test could reach while both builders were private to the screen file.
//
// So this file asserts the finished string. It is the level the owner is
// actually reporting from, and the level at which "every ingredient is
// translated" stops being a proxy for "the card is in Arabic".
//
// WHAT IT FOUND
// `applicationSubtitle` interpolated `application['city']` raw while
// `missionSubtitle`, forty lines above it, had already been fixed to call
// `.tr` on the same field. One card said «أربيل» and the other said "Erbil".
//
// WHAT IT DELIBERATELY DOES NOT CLAIM
// Two Latin leaks survive here BY DESIGN, and both are pinned below as
// expected behaviour rather than quietly hidden:
//
//   * A city the volunteer TYPED — "duhok", lower case — is not a key in
//     iraq_governorates.dart, so `.tr` returns it unchanged. Mangling free
//     text would be worse than leaving it; the fix belongs at data entry.
//   * An application saved BEFORE the structured `availability_schedule`
//     column existed has only the free-text `availability` summary, which the
//     form built with English day names. The English is in the data. No
//     display-time call can repair that row.
//
// Anyone re-reading the owner's report against this file should expect those
// two, and should treat a translated status or a 24-hour time as a real bug.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';

/// Both locale settings at once — `.tr` reads GetX's, the times read `intl`'s.
/// See the note in application_subtitle_l10n_test.dart for why no binding is
/// initialised here.
Future<void> useLocale(Locale locale) async {
  Get.updateLocale(locale);
  await AppLocaleService.syncDateFormatLocale(locale);
}

/// A row shaped the way the backend returns one for a CURRENT application:
/// a status token, a governorate that IS a key, and the structured schedule.
const _application = {
  'status': 'submitted',
  'city': 'Erbil',
  'availability': 'Mon 09:00-17:00, Sun 09:00-17:00',
  'availability_schedule': [
    {'day': 'mon', 'from': '09:00', 'to': '17:00'},
    {'day': 'sun', 'from': '09:00', 'to': '17:00'},
  ],
};

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  group('the volunteer application card', () {
    test('carries no Latin letters at all in Arabic', () async {
      await useLocale(const Locale('ar', 'SA'));
      final line = applicationSubtitle(_application);

      // The single assertion the owner's report reduces to.
      expect(
        RegExp(r'[A-Za-z]').hasMatch(line),
        isFalse,
        reason: 'the finished card line still contains English: "$line"',
      );
      // And the three specific words that were in it, named so a future
      // failure says which half regressed.
      expect(line.contains('submitted'), isFalse, reason: 'status');
      expect(line.contains('Erbil'), isFalse, reason: 'city');
      expect(line.contains('Mon'), isFalse, reason: 'day name');
      expect(line.contains('09:00'), isFalse, reason: '24-hour wire time');
    });

    test('says what it should say, not merely "nothing English"', () async {
      // A line that lost its city entirely would also pass the test above.
      await useLocale(const Locale('ar', 'SA'));
      final line = applicationSubtitle(_application);

      expect(line, contains('أربيل'));
      expect(line, contains('إثن'));
      expect(line, contains('9:00 ص'));
      expect(line, contains('5:00 م'));
    });

    test('reads correctly in English too', () async {
      await useLocale(const Locale('en', 'US'));
      final line = applicationSubtitle(_application);

      expect(line, contains('Erbil'));
      expect(line, contains('Mon'));
      // 12-hour on both sides — this is a display preference, not a
      // translation, so English changed exactly as Arabic did.
      expect(line.contains('09:00-17:00'), isFalse);
      expect(line, contains('AM'));
    });

    test('a legacy row with no structured schedule keeps its English, and '
        'that is the documented limit of this fix', () async {
      await useLocale(const Locale('ar', 'SA'));
      final line = applicationSubtitle(const {
        'status': 'approved',
        'city': 'Erbil',
        // Saved before the structured column existed: English, in the data.
        'availability': 'Mon 09:00-17:00',
      });

      // The parts that CAN be fixed still are.
      expect(line, contains('أربيل'));
      expect(line.contains('approved'), isFalse);
      // The part that cannot is preserved rather than dropped — showing the
      // volunteer's own words in the wrong language beats showing nothing.
      expect(line, contains('Mon 09:00-17:00'));
    });

    test('a governorate is translated whatever case it was typed in', () async {
      await useLocale(const Locale('ar', 'SA'));
      final line = applicationSubtitle(const {
        'status': 'submitted',
        'city': 'duhok', // lower case — what a volunteer actually types
      });
      // This test used to assert the opposite, on the reasoning that `.tr`
      // must not invent a translation for text someone typed. That reasoning
      // is still right, and the conclusion was still wrong: the governorate
      // keys are capitalised because they double as the English labels, so
      // `duhok` failed to match a name it plainly IS. Matching case-
      // insensitively against a closed list of eighteen is a normalisation,
      // not an invention — see localized_city_test.dart.
      expect(line, contains('دهوك'));
      expect(line.contains('duhok'), isFalse);
    });

    test('a place that is NOT a governorate survives exactly as written', () {
      // The half that must not regress. A village, a district or a typo is the
      // person's own words about where they live, and a looser match would
      // start rewriting them.
      for (final typed in ['Sumel', 'حي الجامعة', 'Duhok District']) {
        final line = applicationSubtitle({
          'status': 'submitted',
          'city': typed,
        });
        expect(line, contains(typed), reason: typed);
      }
    });

    test('missing fields collapse rather than leaving empty separators', () {
      final line = applicationSubtitle(const {'status': 'submitted'});
      expect(line.contains(' -  - '), isFalse);
      expect(line.trim(), isNotEmpty);
    });
  });

  group('the missions card', () {
    test('carries no Latin letters in Arabic', () async {
      await useLocale(const Locale('ar', 'SA'));
      final line = missionSubtitle(const {
        'city': 'Duhok',
        'mission_date': '2026-05-25T08:00:00Z',
        'signup_status': 'pending',
      });

      expect(
        RegExp(r'[A-Za-z]').hasMatch(line),
        isFalse,
        reason: 'the finished missions line still contains English: "$line"',
      );
      // "pending" and "Erbil" were the two reported words; "May" is the date
      // path, fixed earlier and worth keeping under the same guard.
      expect(line.contains('pending'), isFalse);
      expect(line.contains('May'), isFalse);
      expect(line, contains('دهوك'));
    });

    test(
      'a mission with no date says the translated word, not "Flexible"',
      () async {
        await useLocale(const Locale('ar', 'SA'));
        final line = missionSubtitle(const {'city': 'Duhok'});
        expect(line.contains('Flexible'), isFalse);
        expect(RegExp(r'[A-Za-z]').hasMatch(line), isFalse);
      },
    );
  });
}
