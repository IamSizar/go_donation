// Pins the support button at the top of the app (J9).
//
// WHY THIS FILE EXISTS
// J9 is one sentence — "إضافة زر الدعم في أعلى التطبيق", add a support button
// at the top of the app. There had been one; it was removed during the Note #41
// restructure, and the removal is documented in widgets/dashboard.dart on the
// reasoning that "support is reachable from Settings". It is: الملف الشخصي →
// الدعم الفني, and the Services hub. Both are two taps into the app, which is
// exactly what "at the top" was asking not to be — when something is going
// wrong, the way to ask for help should not itself need navigating to.
//
// The top bar is the only chrome shown above every tab, so it is the only
// place in the app where "at the top" is true everywhere.
//
// WHY BOTH A SOURCE TEST AND A RENDER TEST
// The defect is a missing DOOR, and "is there a route to support in the bar" is
// a source question — the same shape as sound_vibration_reach_test.dart and
// partners_doors_test.dart. The scoping matters: `TechnicalSupportScreen` was
// already in this file's import graph via other widgets, so a naive whole-file
// `contains` would have passed before the fix. The assertion is narrowed to the
// body of the top bar class.
//
// The render group exists because a sixth control in a fixed-height row is a
// layout risk, and arithmetic in a comment is not evidence. It builds the real
// bar at 320dp — the narrowest screen Android still ships — with both GetX
// controllers stood up against a dead network.
//
// `DashboardTopBar` lost its underscore for that second group; nothing else
// about it changed. A private class cannot be pumped from a test, and the
// alternative was to leave the riskiest part of J9 unexecuted.
//
// WHAT CHANGED, AND WHAT THIS FILE NOW PINS
// The owner later asked for the bar's six controls to collapse behind a single
// button, because six tap targets and two badges above every tab is more
// chrome than content. That is a direct instruction and it wins — but it costs
// exactly the thing J9 bought: support is now ONE TAP away rather than zero.
//
// So this file no longer claims "no tap". It pins the strongest guarantee the
// two requirements can both have:
//   * the route to support lives in the TOP BAR's own code, not in Settings —
//     which is the half of J9 that the client was actually complaining about
//     (الملف الشخصي → الدعم الفني is *two* taps and a menu to read);
//   * it is reachable from every tab in one tap, with no navigation;
//   * and the expanded row still fits on a 320dp screen.
// If a future change buries support behind a second tap, or moves it out of
// the bar, these tests fail — which is the line worth holding.
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

  // The trailing controls moved into _TopBarActions when the row was collapsed
  // behind one button. They are still the top bar — same file, same widget
  // subtree, rendered by the same bar — so the scope follows them. Scoping to
  // DashboardTopBar alone would now report "support left the bar" for a change
  // that only moved it one class down, which is a false alarm, and scoping to
  // the whole file is what this helper exists to avoid.
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
  group('the top bar carries a support button', () {
    test('it opens technical support', () {
      expect(
        _topBarBody().contains('TechnicalSupportScreen'),
        isTrue,
        reason:
            'J9 asks for a support button at the top of the app. Support being '
            'reachable from the profile menu is what the client was reporting '
            'as not enough.',
      );
    });

    test('it sits beside the other controls, in the bar, not in Settings', () {
      final body = _topBarBody();
      // The five below share the collapsed cluster with support. What matters
      // is that they are all in the BAR: if support were pushed back into a
      // menu while these stayed, that is J9 regressing, and this list is how
      // that shows up.
      for (final sibling in const [
        'AssistantHintButton',
        'GlobalSearchScreen',
        'NotificationsScreen',
        'MessagesScreen',
        '_TopBarProfileAvatar',
      ]) {
        expect(
          body.contains(sibling),
          isTrue,
          reason:
              '$sibling left the top bar — the support button was meant to '
              'join that row, not replace part of it',
        );
      }
    });

    test('its label is not new vocabulary', () {
      // Rule: never invent Kurdish. The button reuses the label the profile
      // menu already uses for the same destination, which exists in all four
      // locales — so nothing here lands in TRANSLATION_REQUEST.md.
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
    // ships (320dp), because the sixth control is the change most likely to
    // break something and arithmetic in a comment is not evidence.
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

    testWidgets('the six controls open in one tap and fit a 320dp screen', (
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

      // Collapsed, the bar shows one button. This is the tap J9 now costs, and
      // it is the whole reason the assertions below are still worth making:
      // one tap, no navigation, from whichever tab the user is standing on.
      expect(
        find.byIcon(Icons.more_horiz_rounded),
        findsOneWidget,
        reason: 'the collapsed cluster should offer exactly one control',
      );
      expect(
        find.byIcon(Icons.support_agent_rounded),
        findsNothing,
        reason: 'collapsed means collapsed — nothing else should be drawn yet',
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
      // The support glyph, plus the four that were already there. The avatar
      // is an image widget, not an Icon, so it is not in this list.
      expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
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
      expect(find.byIcon(Icons.support_agent_rounded), findsNothing);

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
      // rather than overflowing — adding a sixth control can cost the title
      // width but can never produce a layout error. That property is what
      // this test pins: drop the Expanded or the ellipsis and a long Arabic
      // dashboard title starts overflowing the bar instead of truncating.
      expect(
        body.contains('Expanded(child: _TopBarTitle('),
        isTrue,
        reason:
            'the title must stay Expanded, or the six trailing controls have '
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
