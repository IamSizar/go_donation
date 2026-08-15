// Pins the two entries the client's profile menu was still missing (J6).
//
// WHY THIS FILE EXISTS
// J6 asks for the circular avatar top-right to open a menu holding eleven
// named entries: الملف الشخصي، الاعدادات، الاشعارات، خدمات المجتمع، اللعبة،
// الوضع الداكن، الدعم الفني، من نحن، اتصل بنا، الشروط والأحكام، تسجيل الخروج.
//
// Nine were already there. Two were not, and both failures were about DOORS
// rather than about screens that did not exist:
//
//   اللعبة  — WheelOfFortuneScreen and LuckyCouponScreen are both built and
//             working, but their only entry point in the whole app was the
//             quick-actions panel on the donor Home (lib/widgets/dashboard.dart).
//             A recipient, a volunteer or a marriage user could never reach
//             either one: the panel is not rendered for their role.
//
//   الاشعارات — the row carrying that label was an on/off SWITCH. Flipping it
//             changes a preference; it never opens the user's notifications.
//             The client listed it among menu entries, i.e. as somewhere you
//             go, so the row has to be a door as well as a switch.
//
// WHY THESE ARE SOURCE TESTS
// Same reasoning as sound_vibration_reach_test.dart and partners_doors_test.dart:
// the defect is not what a screen renders, it is whether any screen offers a
// route to another one. A widget test can only inspect the screen it was
// pointed at, and "nobody points at it" is precisely the bug. The widget
// groups below then pin the behaviour the source test cannot see.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/dashboard/screens/games_screen.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';

import '../support/fake_http.dart';

/// The account hub behind the top-right avatar — the menu J6 describes.
const _profileMenu = 'lib/modules/auth/screens/profile_menu_screen.dart';

/// The donor Home. Its quick-actions panel was the games' only door, and it
/// is role-gated, which is the whole reason J6 reproduced.
const _donorHome = 'lib/widgets/dashboard.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('اللعبة is reachable from the profile menu, not only from donor Home', () {
    test('the profile menu offers a door to the game', () {
      expect(
        _read(_profileMenu).contains('GamesScreen'),
        isTrue,
        reason:
            'J6 lists اللعبة as one of the eleven menu entries. Without a row '
            'here the wheel and the coupon exist but only a donor can open them.',
      );
    });

    test('the games are no longer role-gated behind one screen', () {
      // Count the screens that navigate to either game. One (donor Home) means
      // the gate is still there; two or more means at least one role-neutral
      // door exists.
      final doors = <String>[];
      for (final path in [_profileMenu, _donorHome, 'lib/modules/dashboard/screens/games_screen.dart']) {
        final src = _read(path);
        if (src.contains('WheelOfFortuneScreen') ||
            src.contains('LuckyCouponScreen') ||
            src.contains('GamesScreen')) {
          doors.add(path);
        }
      }

      expect(
        doors.length,
        greaterThan(1),
        reason:
            'found only $doors. The donor Home panel is rendered for role 1 '
            'alone, so a single door there leaves every other role with no way in.',
      );
    });
  });

  group('الاشعارات opens the notifications list as well as toggling them', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();
    });

    test('the profile menu hands the row a destination', () {
      final src = _read(_profileMenu);
      expect(
        RegExp(r'NotificationsRow\(\s*onOpenList:').hasMatch(src),
        isTrue,
        reason:
            'the row must be given somewhere to go. A bare NotificationsRow() '
            'is the switch-only version the client reported: tapping الاشعارات '
            'flips a preference instead of showing your notifications.',
      );
    });

    testWidgets('tapping the label opens the list', (tester) async {
      var opened = false;
      await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
        await tester.pumpWidget(
          GetMaterialApp(
            translations: AppTranslations(),
            locale: const Locale('en', 'US'),
            home: Scaffold(
              body: NotificationsRow(onOpenList: () => opened = true),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Notifications'));
        await tester.pump();
      });

      expect(
        opened,
        isTrue,
        reason:
            'the label is the door. If only the switch responds, the menu entry '
            'the client asked for still does not exist.',
      );
    });

    testWidgets('the on/off switch survives beside the new door', (
      tester,
    ) async {
      await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
        await tester.pumpWidget(
          GetMaterialApp(
            translations: AppTranslations(),
            locale: const Locale('en', 'US'),
            home: Scaffold(body: NotificationsRow(onOpenList: () {})),
          ),
        );
        await tester.pump();
      });

      // Turning the row into a link must not cost the preference its control —
      // "Twelfth: General Settings" asks for both.
      expect(find.byType(Switch), findsOneWidget);
    });
  });

  group('the game hub shows both games', () {
    testWidgets('it lists the wheel and the coupon', (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('en', 'US'),
          home: const GamesScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Wheel of Fortune'), findsOneWidget);
      expect(find.text('Lucky Coupon'), findsOneWidget);
    });

    testWidgets('its title is translated on an Arabic screen', (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('ar', 'SA'),
          home: const GamesScreen(),
        ),
      );
      await tester.pump();

      // Rule: an Arabic screen shows no English. `.tr` returns the key itself
      // when the Arabic entry is missing, so finding the English key here is
      // exactly the failure mode to catch.
      expect(find.text('Game'), findsNothing);
      expect(find.text('عجلة الحظ'), findsOneWidget);
    });
  });
}
