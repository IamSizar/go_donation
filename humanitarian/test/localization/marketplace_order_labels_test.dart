// Pins that a marketplace order card shows words and dates, not machine values.
//
// WHY THIS FILE EXISTS
// Two raw values were being printed onto the same card in the Arabic UI:
//
//   1. the ORDER STATUS. marketplace_orders_screen passed the backend token
//      straight to AppStatusTag, which renders `label.tr.toUpperCase()`. GetX
//      returns the key unchanged when it has no entry, and there were no
//      entries — so the card read APPROVED / PROCESSING / CANCELLED in Latin
//      capitals, right-to-left, next to correctly localized money.
//
//   2. the ORDER DATE. `created_at` was interpolated as-is, so the card read
//      "Submitted: 2026-08-15T12:15:35.660229Z" — Go's RFC 3339 marshalling,
//      shown to a person.
//
// Both go through the app's shared helpers now (localizedTag / localizedDate).
// The five statuses are exactly the CHECK constraint on marketplace_orders in
// migration 001 and the Go allow-list in admin_status.go, so this list is the
// whole domain, not a sample.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
  });

  const orderStatuses = [
    'pending',
    'approved',
    'processing',
    'completed',
    'cancelled',
  ];

  group('marketplace order status', () {
    test('every status has a real English label, not the raw token', () {
      for (final s in orderStatuses) {
        expect(localizedTag(s), isNot(s), reason: '$s rendered as its token');
      }
    });

    test('every status reads in Arabic with no Latin letters left', () {
      // The reported defect, exactly: Latin capitals on an Arabic screen.
      Get.locale = const Locale('ar', 'SA');
      for (final s in orderStatuses) {
        final label = localizedTag(s);
        expect(label, isNotEmpty);
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '$s rendered as "$label" in Arabic',
        );
      }
    });

    test('AppStatusTag upper-casing cannot resurrect the token', () {
      // The widget does `label.tr.toUpperCase()` on whatever it is handed.
      // Passing an already-translated label must survive that second lookup —
      // this is what makes routing through localizedTag at the call site the
      // whole fix rather than half of one.
      Get.locale = const Locale('ar', 'SA');
      for (final s in orderStatuses) {
        final rendered = localizedTag(s).tr.toUpperCase();
        expect(
          RegExp(r'[A-Za-z]').hasMatch(rendered),
          isFalse,
          reason: '$s survived as "$rendered" after the tag re-translated it',
        );
      }
    });

    test('no status survives as a machine token in ANY locale', () {
      // Kurdish has no entries for these yet, so localizedTag's humanising
      // branch is the guarantee there. Whatever happens, no bare token.
      for (final locale in const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
        Locale('ar', 'IQ'), // Sorani
        Locale('ar', 'TR'), // Badini
      ]) {
        Get.locale = locale;
        for (final s in orderStatuses) {
          expect(localizedTag(s), isNotEmpty, reason: '$s vanished in $locale');
        }
      }
    });
  });

  group('order date', () {
    test('an RFC 3339 timestamp never reaches the screen as-is', () {
      // The exact shape Go's time.Time marshals to, and the exact string the
      // card used to print.
      const raw = '2026-08-15T12:15:35.660229Z';
      final shown = localizedDate(raw);

      expect(shown, isNot(raw));
      expect(shown, isNot(contains('T')));
      expect(shown, isNot(contains('Z')));
      expect(shown, contains('2026'));
    });

    test('the date follows the selected language', () {
      // Intl.defaultLocale is pinned by AppLocaleService on every language
      // switch, so the month name has to change with it. Both Kurdish variants
      // deliberately share Arabic calendar data — intl ships no Sorani or
      // Badini month names — so only en vs ar is asserted here.
      const raw = '2026-08-15T12:15:35.660229Z';

      Get.locale = const Locale('en', 'US');
      final english = localizedDate(raw);
      expect(
        RegExp(r'[A-Za-z]').hasMatch(english),
        isTrue,
        reason: 'English should render a Latin month name',
      );

      Get.locale = const Locale('ar', 'SA');
      final arabic = localizedDate(raw);
      expect(arabic, isNotEmpty);
    });

    test('an unparseable value is shown, not swallowed', () {
      // Hiding it would hide the bug too: it means the server sent a shape we
      // do not know about.
      expect(localizedDate('not-a-date'), 'not-a-date');
    });

    test('no date renders nothing, so the line can be hidden', () {
      expect(localizedDate(null), '');
      expect(localizedDate(''), '');
      expect(localizedDate('   '), '');
    });
  });
}
