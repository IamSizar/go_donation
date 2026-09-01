// Pins the per-category notification switches (K7).
//
// WHY THIS FILE EXISTS
// `users.notifications_enabled` was one SMALLINT and the only notification
// preference in the whole system: all alerts or none. Backend 159a3b2 plus
// migration 108 added a switch per CATEGORY and — the part that matters —
// enforced it inside `notify.Send`, so switching one off stops the push being
// composed rather than merely hiding it after it arrives.
//
// The app half was still one on/off switch in the profile menu. Two things
// therefore have to be pinned here, and neither is "does a switch render":
//
//   1. THE WIRE. The screen must read `items[].category` / `.enabled` from
//      GET /api/profile/notification-categories and post back
//      {"disabled":[…]} — the WHOLE set, not a delta, because
//      SetNotificationCategories writes every catalogue row every time and a
//      partial post is how a switch ends up disagreeing with the server about
//      its own position.
//
//   2. FAIL CLOSED. Every switch renders from `enabled`, so an unloaded list
//      would draw nothing at all, and a list defaulted to "all on" would tell
//      a user they receive alerts they may have switched off. On a failed
//      fetch the screen shows the error and no switches — the same rule
//      field_privacy_screen.dart already follows for privacy.
//
// The master switch is deliberately on this screen too (the existing
// NotificationsRow, not a second copy of the state): the server lets the
// master override every category, so a screen that hid it could show six
// switches that all silently do nothing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/notifications/screens/notification_categories_screen.dart';

import '../support/fake_http.dart';

/// One body serving both GETs the screen makes.
///
/// The fake answers every request identically, and the screen reads two
/// different endpoints: `enabled` is the master switch
/// (GET /api/profile/notifications) and `items` is the catalogue
/// (GET /api/profile/notification-categories). A superset satisfies both
/// without the fake needing per-URL routing.
String _catalogue({
  bool masterEnabled = true,
  bool paymentEnabled = true,
  List<Map<String, dynamic>>? items,
}) => jsonEncode({
  'success': true,
  'enabled': masterEnabled,
  'items':
      items ??
      [
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
          'enabled': paymentEnabled,
        },
      ],
});

/// The account hub behind the top-right avatar — where the client looked for
/// this setting, and where the single on/off switch still lives.
const _profileMenu = 'lib/modules/auth/screens/profile_menu_screen.dart';
const _controlSettings = 'lib/modules/auth/screens/control_settings_screen.dart';
const _settingsSection = 'lib/widgets/settings_section.dart';

String _readSource(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

Widget _screen() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const NotificationCategoriesScreen(),
);

/// Pumps the screen inside [recorder]'s zone and lets both loads land.
///
/// Not `pumpAndSettle`: the master switch shows a CircularProgressIndicator
/// while it loads, and an indeterminate spinner never settles.
Future<void> _open(WidgetTester tester, FakeHttpOverrides recorder) async {
  await withHttp(recorder, () async {
    await tester.pumpWidget(_screen());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

/// Every `{"disabled": […]}` write the screen made, in order.
List<List<String>> _writes(FakeHttpOverrides recorder) => recorder.requestBodies
    .map((b) {
      try {
        final decoded = jsonDecode(b);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        // Not one of ours; the filter below drops it. Nothing is hidden —
        // a malformed body simply is not a category write.
        return null;
      }
    })
    .whereType<Map<String, dynamic>>()
    .where((b) => b['disabled'] is List)
    .map((b) => (b['disabled'] as List).map((e) => e.toString()).toList())
    .toList();

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the screen renders what the server says', () {
    testWidgets('one switch per category, in the server\'s state', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _catalogue(paymentEnabled: false),
        ),
      );

      expect(find.byKey(const Key('notif_cat_urgent')), findsOneWidget);
      expect(find.byKey(const Key('notif_cat_payment')), findsOneWidget);

      final urgent = tester.widget<SwitchListTile>(
        find.byKey(const Key('notif_cat_urgent')),
      );
      final payment = tester.widget<SwitchListTile>(
        find.byKey(const Key('notif_cat_payment')),
      );
      expect(urgent.value, isTrue);
      expect(
        payment.value,
        isFalse,
        reason:
            'the server said this category is off; drawing it on would tell '
            'the user they still receive payment alerts',
      );
    });

    testWidgets('labels resolve, never a bare key', (tester) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue()));

      // `label_key` is server data, so it goes through localizedTag rather
      // than `.tr` — which would silently print the key back.
      expect(find.text('Urgent'.tr), findsOneWidget);
      expect(find.text('Payment'.tr), findsOneWidget);
    });

    testWidgets('an unknown label key degrades, never to snake_case', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _catalogue(
            items: [
              {
                'category': 'brand_new',
                'label_key': 'brand_new_thing',
                'display_order': 10,
                'enabled': true,
              },
            ],
          ),
        ),
      );

      expect(find.text('brand_new_thing'), findsNothing);
      expect(find.text('Brand new thing'), findsOneWidget);
    });
  });

  group('a switch writes the whole picture', () {
    testWidgets('switching one off posts every disabled category', (
      tester,
    ) async {
      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _catalogue(paymentEnabled: false),
      );
      await _open(tester, recorder);

      await withHttp(recorder, () async {
        await tester.tap(find.byKey(const Key('notif_cat_urgent')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      final writes = _writes(recorder);
      expect(writes, hasLength(1));
      expect(
        writes.single..sort(),
        ['payment', 'urgent'],
        reason:
            'SetNotificationCategories rewrites every catalogue row from this '
            'list, so sending only the one just tapped would switch the other '
            'back on',
      );
    });
  });

  group('a failed load says so instead of guessing', () {
    testWidgets('no switches are drawn, and there is a way back', (
      tester,
    ) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.serverError));

      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.byType(AppErrorState),
        findsOneWidget,
        reason: 'error is checked before empty, so this is not "no categories"',
      );
      expect(find.text('retry'.tr), findsOneWidget);
    });

    testWidgets('an empty catalogue is an empty state, not an error', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue(items: [])),
      );

      expect(find.byType(AppEmpty), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    });
  });

  group('the master switch is not hidden from the categories', () {
    testWidgets('when it is off, the screen says the categories are moot', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _catalogue(masterEnabled: false),
        ),
      );

      expect(
        find.text('notif_cat_master_off'.tr),
        findsOneWidget,
        reason:
            'users.notifications_enabled wins over every category server-side '
            '(pinned by a Go test), so six switches with no explanation would '
            'be six controls that do nothing',
      );
    });

    testWidgets('when it is on, that note is absent', (tester) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.ok, body: _catalogue()));

      expect(find.text('notif_cat_master_off'.tr), findsNothing);
    });
  });

  // A SOURCE test for the same reason profile_menu_doors_test.dart uses one:
  // the defect K7 describes is not what a screen renders, it is that the
  // client looked in the profile menu and found one on/off switch. A widget
  // test can only inspect the screen it was pointed at, and "nothing points at
  // it" is precisely the failure mode.
  group('the screen is reachable from where the client looked', () {
    // The door moved one screen deeper when the loose preference rows were
    // gathered into Settings & Preferences, so the reachable-ness is now a
    // CHAIN: profile menu → control settings → categories. Both links are
    // asserted, because either one breaking strands the screen exactly as K7
    // described. The label moved too — it is drawn by the nested line inside
    // NotificationsRow rather than by a menu entry of its own.
    test('the settings hub opens it, and the profile menu opens the hub', () {
      expect(
        _readSource(_profileMenu).contains('ControlSettingsScreen'),
        isTrue,
        reason: 'the profile menu is still where the client looks first',
      );
      expect(
        _readSource(_controlSettings).contains('NotificationCategoriesScreen'),
        isTrue,
        reason:
            'the categories screen with no door is the same defect as no '
            'categories screen at all',
      );
      expect(
        _readSource(_settingsSection).contains("'Alert categories'"),
        isTrue,
        reason: 'and the door needs a label that resolves in all four locales',
      );
    });
  });
}
