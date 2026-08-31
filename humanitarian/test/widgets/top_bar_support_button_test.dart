// Pinned the support button at the top of the app (J9). Now pins its
// opposite, because the owner reversed the decision this file used to guard.
//
// HISTORY
// J9 was one sentence — "إضافة زر الدعم في أعلى التطبيق", add a support
// button at the top of the app. There had been one; it was removed during the
// Note #41 restructure on the reasoning that support is reachable from
// Settings, which cost two taps through a menu instead of the zero taps "at
// the top" was asking for. A support button was added back to the collapsed
// top-bar cluster to close that gap, and this file pinned it: the route to
// support had to live in the top bar's own code, one tap from every tab, and
// the expanded six-control row still had to fit a 320dp screen.
//
// UPDATED (d33b2d7)
// The owner has since asked for both the AI icon (K28) and this support
// button to come off the top bar entirely and be reached from الرسائل
// instead — a direct instruction, and it wins over J9's "at the top" framing.
// الرسائل already carried the assistant card and the support-chat tile, and
// now also opens TechnicalSupportScreen directly (see
// lib/modules/chat/screens/messages_screen.dart). The top-bar cluster that
// used to expand to six controls is back down to four: search, notifications,
// messages, profile avatar.
//
// So this file no longer pins "support opens from the top bar in one tap".
// It pins the inverse — the same move partners_doors_test.dart made when the
// Home partners strip came off (commit 01e1342): a future accidental re-add
// of either control into this bar is what would now be the regression, so
// that is the guard worth holding. The 320dp fit check is kept, narrowed to
// the four controls the bar actually has today — a real layout risk (a
// RenderFlex overflow) does not stop being one just because the control count
// changed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/dashboard/screens/dashboard_screen.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';

import '../support/fake_http.dart';

const _dashboardScreen = 'lib/modules/dashboard/screens/dashboard_screen.dart';
const _messagesScreen = 'lib/modules/chat/screens/messages_screen.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// The source of `DashboardTopBar` alone, so "somewhere in this 700-line
/// file" cannot pass for "in the persistent top bar".
String _topBarBody() {
  final src = _read(_dashboardScreen);
  final start = src.indexOf('class DashboardTopBar');
  if (start < 0) {
    fail(
      'class DashboardTopBar is gone from $_dashboardScreen — the top bar '
      'was renamed or moved, and this test needs following, not deleting',
    );
  }
  // Through the State class too: the bar became stateful when the cluster
  // learned to collapse, so `class DashboardTopBar` is now just the widget
  // shell and `_DashboardTopBarState` holds the build method with the title.
  // Stopping at the first `\nclass ` would scope this test to the shell and
  // report the title as missing when it had only moved.
  final afterState = src.indexOf('class _DashboardTopBarState');
  final searchFrom = afterState < 0 ? start : afterState;
  final next = src.indexOf('\nclass ', searchFrom + 1);
  final bar = next < 0 ? src.substring(start) : src.substring(start, next);

  // The trailing controls live in _TopBarActions, the collapsed action
  // cluster — same file, same widget subtree, rendered by the same bar — so
  // the scope follows them there rather than stopping at DashboardTopBar.
  final actionsStart = src.indexOf('class _TopBarActions');
  if (actionsStart < 0) {
    fail(
      'class _TopBarActions is gone from $_dashboardScreen — the collapsed '
      'action cluster was renamed or moved, and this test needs following',
    );
  }
  final actionsEnd = src.indexOf('\nclass ', actionsStart + 1);
  final actions = actionsEnd < 0
      ? src.substring(actionsStart)
      : src.substring(actionsStart, actionsEnd);
  return '$bar\n$actions';
}

void main() {
  group('the top bar no longer carries a support button', () {
    test('it does not open technical support from the bar', () {
      expect(
        _topBarBody().contains('TechnicalSupportScreen'),
        isFalse,
        reason:
            'support was moved out of the top bar and into الرسائل; its '
            'reappearance here would mean the move was accidentally '
            'reverted',
      );
    });

    test('it does not carry the per-section AI icon either', () {
      // K28's icon left the bar in the same change (d33b2d7) — see
      // assistant_hint_button_test.dart for that guard in full. Checked here
      // too because both controls shared the same collapsed cluster, and a
      // regression that brought one back without the other is still worth
      // catching from this side.
      // As a constructor call, not a bare name — see
      // assistant_hint_button_test.dart for why: the removal comment in
      // _TopBarActions still says "AssistantHintButton" in prose.
      expect(_topBarBody().contains('AssistantHintButton('), isFalse);
    });

    test('الرسائل is where support is reached from instead', () {
      expect(
        _read(_messagesScreen).contains('TechnicalSupportScreen'),
        isTrue,
        reason:
            'this is the door J9 now relies on; if it closes there is no '
            'route to support left at all',
      );
    });

    test('its label is not new vocabulary', () {
      // Rule: never invent Kurdish. The Messages-side entry reuses the label
      // the profile menu already used for the same destination, which exists
      // in all four locales — so nothing here lands in TRANSLATION_REQUEST.md.
      final keys = AppTranslations().keys;
      for (final locale in const ['en_US', 'ar_SA', 'ar_IQ', 'ar_TR']) {
        final value = keys[locale]!['Technical Support'];
        expect(
          value,
          isNotNull,
          reason: 'no "Technical Support" entry for $locale',
        );
      }
      expect(
        keys['ar_SA']!['Technical Support'],
        isNot('Technical Support'),
        reason: 'an Arabic screen must not render the English label',
      );
    });
  });

  group('the trailing controls still fit', () {
    // The bar is built here for real, on the narrowest screen Android still
    // ships (320dp), because a layout risk does not stop being one just
    // because the control count dropped from six to four — arithmetic in a
    // comment is not evidence either way.
    //
    // Tab 1 (Store) rather than Home: Home's title reads RoleDashboardController
    // inside an Obx, and this group is about the trailing row, not the title's
    // data source.
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();
    });

    tearDown(() {
      // Both controllers poll on a Timer.periodic; deleting them runs onClose,
      // which cancels the timer. Without this the test ends with a pending
      // timer and fails on the next one.
      Get.delete<NotificationsController>(force: true);
      Get.delete<ChatController>(force: true);
    });

    testWidgets('the four controls open in one tap and fit a 320dp screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
        Get.put(NotificationsController());
        Get.put(ChatController());
        await tester.pumpWidget(
          GetMaterialApp(
            translations: AppTranslations(),
            locale: const Locale('ar', 'SA'),
            home: const Scaffold(
              body: Column(children: [DashboardTopBar(tabIndex: 1)]),
            ),
          ),
        );
        await tester.pump();
      });

      // Collapsed, the bar shows one button.
      expect(
        find.byIcon(Icons.more_horiz_rounded),
        findsOneWidget,
        reason: 'the collapsed cluster should offer exactly one control',
      );
      expect(
        find.byIcon(Icons.support_agent_rounded),
        findsNothing,
        reason:
            'support has no icon in this bar at all any more, collapsed or '
            'expanded',
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a RenderFlex overflow here means the expanded cluster does not '
            'fit and the bar paints the yellow-and-black stripes',
      );
      // The four controls the bar has today. The avatar is an image widget,
      // not an Icon, so it is not in this list.
      expect(find.byIcon(Icons.support_agent_rounded), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      // The title steps aside while the cluster is open, rather than being
      // ellipsised to a broken word by controls that only borrowed its width.
      expect(
        find.text('السوق'),
        findsNothing,
        reason: 'an expanded cluster should not leave a truncated heading',
      );

      // ...and comes back when the cluster closes, which is what makes the
      // collapse a toggle rather than a one-way trade of title for controls.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('السوق'), findsOneWidget);

      // Inside the body, not in tearDown: flutter_test checks for pending
      // timers as the test body returns, which is before tearDown runs. Both
      // controllers cancel their poll in onClose, and Get.delete is what calls
      // it. (tearDown keeps the same two calls as a net for a failing test.)
      Get.delete<NotificationsController>(force: true);
      Get.delete<ChatController>(force: true);
      await tester.pump();
    });

    test('the row cannot push the title off the bar', () {
      final body = _topBarBody();
      // The title is Expanded with maxLines: 1 and ellipsis, so it SHRINKS
      // rather than overflowing — adding trailing controls can cost the
      // title width but can never produce a layout error. That property is
      // what this test pins: drop the Expanded or the ellipsis and a long
      // Arabic dashboard title starts overflowing the bar instead of
      // truncating.
      expect(
        body.contains('Expanded(child: _TopBarTitle('),
        isTrue,
        reason:
            'the title must stay Expanded, or the trailing controls have '
            'nothing to take space from and the row overflows',
      );
      final titleWidget = _read(_dashboardScreen);
      final titleStart = titleWidget.indexOf('class _TopBarTitle');
      final titleBody = titleWidget.substring(titleStart);
      expect(titleBody.contains('overflow: TextOverflow.ellipsis'), isTrue);
      expect(titleBody.contains('maxLines: 1'), isTrue);
    });
  });
}
