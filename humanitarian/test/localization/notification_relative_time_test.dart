// Pins that the notification list's timestamp is readable in Arabic.
//
// WHY THIS FILE EXISTS
// Found by walking the running app: a notification in an otherwise fully
// Arabic list was stamped «5h». `_relativeTime` in notification_tile.dart
// built "5m" / "3h" / "2d" from bare Latin letters, under a comment arguing
// they are "language-neutral short units so it works in every locale without
// extra translation keys".
//
// The two lines around them already disprove the premise. The same function
// returns `'now'.tr` — which has an entry in all four locales — and falls
// back to `DateFormat('MMM d')`, which resolves to ARABIC month names,
// because AppLocaleService.syncDateFormatLocale pins Intl.defaultLocale to
// 'ar' for Arabic and both Kurdish variants. So the function was already
// locale-aware at both ends and the m/h/d were the only English left in it.
//
// m/h/d are not neutral, either: they are abbreviations of English words.
// Arabic has no convention in which a bare Latin "h" means ساعة, so the
// reader has to know English to read the timestamp — which is what the
// project's rule about English on Arabic screens exists to prevent.
//
// The last test here is the one that pins the fallback rather than assuming
// it, since the argument above rests on it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
// `intl` exports a TextDirection of its own, which shadows the dart:ui enum
// Directionality takes — the same hide the app's own files apply.
import 'package:intl/intl.dart' hide TextDirection;

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';
import 'package:flutter_application_1/modules/notifications/widgets/notification_tile.dart';

/// A notification created [ago] before now, so the tile renders the relative
/// branch under test.
AppNotificationModel _aged(Duration ago) {
  return AppNotificationModel(
    id: '1',
    title: 'Support request',
    titleAr: 'طلب دعم',
    titleSorani: '',
    titleBadini: '',
    message: 'A message',
    messageAr: 'رسالة',
    messageSorani: '',
    messageBadini: '',
    notificationType: 'support_request_submitted',
    notificationCategory: 'urgent',
    priority: 0,
    isRead: true,
    createdAt: DateTime.now().subtract(ago),
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: <ThemeExtension<dynamic>>[AppColors.light]),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}

/// Every Text in the pumped tile, so the timestamp can be found without
/// knowing what it says.
List<String> _texts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
}

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('ar', 'SA');
    Get.fallbackLocale = const Locale('en', 'US');
  });

  group('the notification timestamp in Arabic', () {
    // Minutes, hours and days — the three branches that carried a Latin unit.
    for (final (label, ago) in const [
      ('minutes', Duration(minutes: 5)),
      ('hours', Duration(hours: 5)),
      ('days', Duration(days: 3)),
    ]) {
      testWidgets('a $label-old notification carries no Latin unit', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(NotificationTile(notification: _aged(ago))),
        );

        // The card's own copy is Arabic, so ANY Latin letter on the tile is
        // the timestamp leaking — which is exactly how this was spotted.
        for (final text in _texts(tester)) {
          expect(
            RegExp(r'[A-Za-z]').hasMatch(text),
            isFalse,
            reason: 'Latin text "$text" reached an Arabic notification card',
          );
        }
      });
    }

    testWidgets('"now" was already translated, and stays that way', (
      tester,
    ) async {
      // The counter-example inside the same function: the author localized
      // this branch and not the next three.
      await tester.pumpWidget(
        _host(
          NotificationTile(notification: _aged(const Duration(seconds: 5))),
        ),
      );
      expect(find.text('الآن'), findsOneWidget);
    });
  });

  test('the absolute fallback resolves to Arabic, not English', () async {
    // Verified rather than assumed: AppLocaleService.dateFormatLocale maps
    // ar/ckb/kmr to 'ar', syncDateFormatLocale pins it on Intl.defaultLocale
    // at startup and on every language switch, and DateFormat with no locale
    // argument reads that. So the >7-day branch was never English.
    await initializeDateFormatting('ar');
    Intl.defaultLocale = 'ar';
    final formatted = DateFormat('MMM d').format(DateTime(2026, 5, 25));
    expect(
      RegExp(r'[A-Za-z]').hasMatch(formatted),
      isFalse,
      reason: 'the date fallback rendered English month names',
    );
  });
}
