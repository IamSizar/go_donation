// Pins that the dashboard stops polling donor chats for a GUEST, OPOS #26423,
// and keeps polling them for a signed-in member.
//
// WHY THIS FILE EXISTS
// DashboardScreen registered ChatController for every session, because the
// top bar's Messages button carries an unread badge. For a guest that meant a
// GET /api/chats on start and another every 5 seconds for the whole session.
// The server gives a guest an empty list there (OPOS #26354), so every one of
// those requests was wasted, and the badge could never show anything.
//
// WHAT IS PINNED
//   1. A guest's real DashboardScreen registers no ChatController and sends no
//      request to a chat route, even after a poll interval.
//   2. The top bar survives a guest with no ChatController: it builds, opens,
//      shows the Messages button with no badge, and that button still opens
//      Messages, where support is reached from.
//   3. A member's real DashboardScreen still registers ChatController, which
//      fetches /chats on start and polls it again 5 seconds later.
//
// HARNESS NOTES (borrowed from dashboard_screen_keyboard_test.dart)
//   * `withHttp` fakes every request and records its URL.
//   * The flutter_secure_storage channel has no VM implementation, so it is
//     mocked.
//   * `pumpAndSettle` is not used on the dashboard: several controllers poll
//     every 5 seconds, so the tree never settles. Every polling controller is
//     stopped or deleted before a test body returns, and the observations are
//     captured first, so a failing assertion cannot leave a timer behind.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/dashboard/screens/dashboard_screen.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';

import '../support/fake_http.dart';

// ─── Fixtures ───

/// A successful, empty list. Every consumer on the dashboard accepts it.
const _emptyList = '{"success": true, "items": []}';

/// Every route that gives a guest nothing or refuses them (OPOS #26354).
final _guestRefusedPath = RegExp(
  r'/api/(chats|marriage/chats|chat-groups)(/|$)',
);

/// See test/api/guest_entry_test.dart: the session token write goes through
/// this platform channel, which has no VM implementation and throws unmocked.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

// ─── Helpers ───

/// The recorded requests that went to a guest-refused chat route.
List<Uri> _chatRequests(FakeHttpOverrides http) =>
    http.requestUrls.where((u) => _guestRefusedPath.hasMatch(u.path)).toList();

/// How many times the donor-chat thread list itself was requested.
int _threadListRequests(FakeHttpOverrides http) =>
    http.requestUrls.where((u) => u.path.endsWith('/api/chats')).length;

/// Starts preferences for a guest or a signed-in donor.
Future<void> _startSession({required bool guest}) async {
  SharedPreferences.setMockInitialValues({
    'id_user': '7',
    if (guest) kGuestModePrefsKey: true else 'role_id': '1',
  });
  sharedPreferences = await SharedPreferences.getInstance();
}

/// Cancels every polling timer the dashboard may have started, so the test
/// binding's "no pending timers" check holds. Same set, and same reasoning, as
/// `_stopAllDashboardPolling` in dashboard_screen_keyboard_test.dart.
void _stopAllDashboardPolling() {
  if (Get.isRegistered<FeaturedCampaignsController>()) {
    Get.find<FeaturedCampaignsController>().stopPolling();
  }
  if (Get.isRegistered<RoleDashboardController>()) {
    Get.find<RoleDashboardController>().stopPolling();
  }
  if (Get.isRegistered<MarketplaceController>()) {
    Get.find<MarketplaceController>().stopPolling();
  }
  if (Get.isRegistered<NotificationsController>()) {
    Get.delete<NotificationsController>(force: true);
  }
  if (Get.isRegistered<ChatController>()) {
    Get.delete<ChatController>(force: true);
  }
}

/// Pumps the real DashboardScreen on a phone-sized surface and lets its start-up
/// requests answer. Short of the 5-second poll, which each test advances to on
/// its own.
Future<void> _pumpDashboard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GetMaterialApp(home: DashboardScreen()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    Get.reset();
  });

  testWidgets('a guest dashboard registers no ChatController and never '
      'requests a chat route', (tester) async {
    await _startSession(guest: true);
    final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);

    var registered = false;
    await withHttp(http, () async {
      await _pumpDashboard(tester);
      await tester.pump(const Duration(seconds: 5));
      registered = Get.isRegistered<ChatController>();
      _stopAllDashboardPolling();
      await tester.pump();
    });

    expect(
      registered,
      isFalse,
      reason:
          'a guest ChatController fetches /chats on start and polls it every '
          '5 seconds, for a list the server always leaves empty',
    );
    expect(_chatRequests(http), isEmpty);
  });

  testWidgets('the top bar builds for a guest with no ChatController, shows '
      'no chat badge, and still opens Messages', (tester) async {
    await _startSession(guest: true);
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);

    Object? buildError;
    Object? openError;
    var badgeTexts = -1;
    var messagesOpened = false;
    var registeredAfterOpen = true;
    await withHttp(http, () async {
      Get.put(NotificationsController());
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('en', 'US'),
          home: const Scaffold(
            body: Column(children: [DashboardTopBar(tabIndex: 1)]),
          ),
        ),
      );
      await tester.pump();
      buildError = tester.takeException();

      if (buildError == null) {
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        openError = tester.takeException();

        final messagesButton = find.ancestor(
          of: find.byIcon(Icons.forum_outlined),
          matching: find.byType(Stack),
        );
        badgeTexts = find
            .descendant(of: messagesButton.first, matching: find.byType(Text))
            .evaluate()
            .length;

        await tester.tap(find.byIcon(Icons.forum_outlined));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        messagesOpened = find
            .text('Sign in to use Messages')
            .evaluate()
            .isNotEmpty;
        registeredAfterOpen = Get.isRegistered<ChatController>();
        Get.back();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      _stopAllDashboardPolling();
      await tester.pump();
    });

    expect(
      buildError,
      isNull,
      reason: 'the top bar must not look up a ChatController a guest lacks',
    );
    expect(openError, isNull);
    expect(badgeTexts, 0, reason: 'a guest has no unread chats to count');
    expect(
      messagesOpened,
      isTrue,
      reason: 'Messages is still where a guest reaches support from',
    );
    expect(registeredAfterOpen, isFalse);
    expect(_chatRequests(http), isEmpty);
  });

  testWidgets('a member dashboard still registers ChatController, which '
      'fetches /chats on start and polls it', (tester) async {
    await _startSession(guest: false);
    final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);

    var registered = false;
    var onStart = 0;
    var afterPoll = 0;
    await withHttp(http, () async {
      await _pumpDashboard(tester);
      registered = Get.isRegistered<ChatController>();
      onStart = _threadListRequests(http);
      await tester.pump(const Duration(seconds: 5));
      afterPoll = _threadListRequests(http);
      _stopAllDashboardPolling();
      await tester.pump();
    });

    expect(registered, isTrue);
    expect(onStart, 1, reason: 'one thread-list load when the dashboard opens');
    expect(
      afterPoll,
      greaterThan(onStart),
      reason: 'the 5-second poll still runs for a member',
    );
  });
}
