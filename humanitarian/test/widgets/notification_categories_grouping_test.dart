// Pins the collapsible priority-tier grouping added to
// NotificationCategoriesScreen (owner request: "collapse notification in the
// settings").
//
// WHAT CHANGED AND WHY THIS FILE EXISTS SEPARATELY FROM
// notification_categories_test.dart
// The six server categories now render inside three collapsible sections
// (_tierOf mirrors backend/internal/notify/notify.go's defaultPriority tiers)
// instead of one flat column. notification_categories_test.dart already pins
// the wire contract and the fail-closed behaviour and keeps working
// unmodified because sections start EXPANDED — this file pins the new
// behaviour specifically: a section can be collapsed, an animation carries
// it (not a jump), and — the part the owner's brief called out by name — a
// collapsed section still tells the user whether anything inside it is on.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/notifications/screens/notification_categories_screen.dart';

import '../support/fake_http.dart';

/// Two categories in the same tier (urgent, payment → 'high') and one in a
/// different tier (reminder → 'low'), so the test can tell tiers apart.
String _catalogue() => jsonEncode({
  'success': true,
  'enabled': true,
  'items': [
    {
      'category': 'urgent',
      'label_key': 'Urgent',
      'display_order': 10,
      'enabled': true,
    },
    {
      'category': 'payment',
      'label_key': 'Payment',
      'display_order': 20,
      'enabled': false,
    },
    {
      'category': 'reminder',
      'label_key': 'Reminder',
      'display_order': 50,
      'enabled': true,
    },
  ],
});

Widget _screen() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const NotificationCategoriesScreen(),
);

Future<void> _open(WidgetTester tester, FakeHttpOverrides recorder) async {
  await withHttp(recorder, () async {
    await tester.pumpWidget(_screen());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  testWidgets(
    'sections start expanded, so every switch is reachable without a tap',
    (tester) async {
      await _open(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue()),
      );

      expect(find.byKey(const Key('notif_cat_urgent')), findsOneWidget);
      expect(find.byKey(const Key('notif_cat_payment')), findsOneWidget);
      expect(find.byKey(const Key('notif_cat_reminder')), findsOneWidget);
    },
  );

  testWidgets(
    'a collapsed section hides its switches but keeps its on/off summary',
    (tester) async {
      await _open(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue()),
      );

      // 'High priority' groups urgent (on) + payment (off) → "1 of 2 on".
      expect(find.text('1 of 2 on'), findsOneWidget);

      await tester.tap(find.text('High priority'));
      await tester.pump();
      // AnimatedSize needs settle time, not just one frame, to reach its
      // collapsed extent.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notif_cat_urgent')),
        findsNothing,
        reason: 'the section is collapsed, so its switches leave the tree',
      );
      expect(
        find.byKey(const Key('notif_cat_payment')),
        findsNothing,
      );
      expect(
        find.text('1 of 2 on'),
        findsOneWidget,
        reason:
            'collapsing a section must not hide whether anything inside it '
            'is switched on — that is the whole point of showing a summary',
      );
      // The other, still-expanded section is unaffected.
      expect(find.byKey(const Key('notif_cat_reminder')), findsOneWidget);
    },
  );

  testWidgets('tapping a collapsed section header re-expands it', (
    tester,
  ) async {
    await _open(
      tester,
      FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue()),
    );

    await tester.tap(find.text('High priority'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notif_cat_urgent')), findsNothing);

    await tester.tap(find.text('High priority'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notif_cat_urgent')),
      findsOneWidget,
      reason: 'the same header tap must toggle the section both ways',
    );
  });

  testWidgets('the collapse/expand transition animates, never jumps', (
    tester,
  ) async {
    await _open(
      tester,
      FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue()),
    );

    // Rule 5.4: an appear/disappear must be carried by an AnimatedSize (or
    // equivalent), not a bare conditional swap.
    expect(find.byType(AnimatedSize), findsWidgets);
  });
}
