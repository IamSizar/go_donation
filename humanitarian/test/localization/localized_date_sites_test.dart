// Dates that reached the user as machine values.
//
// THE SHAPE OF THE BUG
// The volunteer's «المهام المتاحة» printed a mission's date as `2026-05-25` —
// ISO 8601, Latin digits, in a right-to-left Arabic interface — because the
// chip rendered `mission['mission_date']` verbatim. The same mistake was
// repeated on nine other surfaces, several of them with a `.substring(0, 10)`
// that made an ISO timestamp *look* deliberate, and one (the news feed's date
// pill) with no truncation at all, so a post falling back to `created_at`
// showed `2026-08-15T12:15:35Z`.
//
// The app already had the answer: `localizedDate`, which renders "18 يوليو
// 2026" under an Arabic locale. Nothing was missing except the call.
//
// WHAT IS ASSERTED
// The two helpers the fixed sites now share — `localizedDateOr`, for the
// places whose empty value has a word of its own ("Flexible"), and
// `isolatedDate`, for a date sitting inside a mixed sentence where the bidi
// algorithm would otherwise reorder it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/localization/locale_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    await AppLocaleService.syncDateFormatLocale(const Locale('en', 'US'));
  });

  tearDown(() async {
    Get.locale = const Locale('en', 'US');
    await AppLocaleService.syncDateFormatLocale(const Locale('en', 'US'));
  });

  group('localizedDateOr — a date, or the word that stands in for one', () {
    test('a real date is formatted, never echoed', () {
      final shown = localizedDateOr('2026-05-25', 'Flexible');
      expect(shown, isNot(contains('2026-05-25')));
      expect(shown, contains('2026'));
      expect(shown, contains('May'));
    });

    // The mission chip's fallback was the bare English literal 'Flexible',
    // which is a translation KEY here so an Arabic reader gets «مرن».
    test('an absent date falls back through .tr, not to English', () {
      expect(localizedDateOr('', 'Flexible'), 'Flexible');
      expect(localizedDateOr(null, 'Flexible'), 'Flexible');

      Get.locale = const Locale('ar', 'SA');
      expect(localizedDateOr('', 'Flexible'), 'مرن');
    });

    test('under Arabic the date itself carries no Latin characters', () async {
      Get.locale = const Locale('ar', 'SA');
      await AppLocaleService.syncDateFormatLocale(const Locale('ar', 'SA'));
      final shown = localizedDateOr('2026-05-25', 'Flexible');
      expect(RegExp(r'[A-Za-z]').hasMatch(shown), isFalse, reason: shown);
      expect(shown, isNot(contains('2026-05-25')));
    });

    // A Postgres timestamp arrives with a space where RFC 3339 has a T. The
    // donation history carried its own parser for exactly this, and its own
    // hardcoded English month names with it.
    test('a space-separated timestamp parses like an RFC 3339 one', () {
      expect(localizedDate('2026-05-25 12:15:35'), localizedDate('2026-05-25'));
    });

    // localizedDate returns the raw string when it will not parse, so that a
    // server sending an unknown shape is visible rather than hidden. The
    // fallback word is for an EMPTY value only, and must not swallow that.
    test('an unparseable value is shown, not replaced by the fallback', () {
      expect(
        localizedDateOr('sometime next spring', 'Flexible'),
        'sometime next spring',
      );
    });
  });

  group('isolatedDate — a date inside a mixed sentence', () {
    test('wraps the formatted date in a first-strong isolate', () {
      final wrapped = isolatedDate('2026-05-25');
      expect(wrapped.startsWith('\u2068'), isTrue); // FSI
      expect(wrapped.endsWith('\u2069'), isTrue); // PDI
      expect(wrapped, contains(localizedDate('2026-05-25')));
    });

    // An empty date must not leave a pair of invisible control characters
    // behind for a caller that tests the result with `isNotEmpty`.
    test('an empty value stays empty rather than becoming two marks', () {
      expect(isolatedDate(''), '');
      expect(isolatedDate(null), '');
    });
  });
}
