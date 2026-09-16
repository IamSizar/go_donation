// Pins that a chat_request notification tile never starts a chat poller for a
// GUEST, OPOS #26448, and still does for a signed-in member.
//
// WHY THIS FILE EXISTS
// #100 (OPOS #26423) stopped the dashboard and the Messages tab from
// registering ChatController for a guest. The notification tile was the door
// left open. Its inline Accept/Decline reads the thread's status through an
// Obx over ChatController.threads, and falls back to Get.put(ChatController())
// when none is registered. ChatController fetches GET /api/chats in onInit and
// polls it every 5 seconds, so merely RENDERING a chat_request tile started
// that poll for a guest, for a list the server always leaves empty
// (GuestGetsEmptyList, #97). Nothing had to be tapped.
//
// WHAT A GUEST GETS: NO ACTIONS, NOT A SIGN-IN PROMPT
// The two app patterns were a sign-in gate on tap (requireSignIn) or no
// action at all. The tile hides the actions, because:
//   * That is how the app treats a guest's chat affordances elsewhere.
//     ConnectRequestButton renders nothing for a guest
//     (connect_request_button.dart), the events group leaves its chat tiles
//     out with `if (!guest)`, and Messages replaces the thread list, where a
//     member answers incoming requests, with a prompt (#100).
//   * A gate on tap would not fix the poller. The buttons live inside the Obx
//     that creates the controller, so drawing them at all starts the poll.
//   * A sign-in prompt would promise something false. requireSignIn leaves
//     guest mode and signs in to a DIFFERENT account, which the invite is not
//     addressed to, and the server refuses a guest's accept and decline
//     outright (RequireNotGuest on POST /api/chats/:id/accept and /decline).
// The notification itself still shows and is still tappable, so the guest is
// told what happened; only the answer buttons are gone.
//
// WHAT IS PINNED
//   1. A guest's chat_request tile shows its notification and passes its tap to
//      the host, yet registers no ChatController and asks for no chat route,
//      even past a poll interval.
//   2. A guest's tile offers no Accept and no Decline.
//   3. A member's tile, with no ChatController registered, still registers one
//      through the fallback, which loads /api/chats, polls it, and draws both
//      buttons.
//   4. A member's Decline still posts the answer for that thread.
//
// HARNESS NOTES (as in test/widgets/messages_guest_prompt_test.dart)
//   * HTTP goes through FakeHttpOverrides, so every URL asked for is recorded.
//   * Every test captures its observations, then unmounts the tile and deletes
//     any ChatController before its body returns. That cancels the 5-second
//     poll, so the binding's pending-timer check holds even when an assertion
//     fails, and the tile cannot re-put a controller while unmounting.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';
import 'package:flutter_application_1/modules/notifications/widgets/notification_tile.dart';

import '../support/fake_http.dart';

// ─── Fixtures ───

const _english = Locale('en', 'US');

/// The chat thread the request is about. Any id that parses as an int makes
/// the tile draw its inline actions for a member.
const _threadId = 42;

/// A successful, empty answer. It serves as the /api/chats list and as the
/// decline response, both of which only check `success`.
const _emptyList = '{"success": true, "items": []}';

/// Every route that gives a guest nothing or refuses them (OPOS #26354).
final _guestRefusedPath = RegExp(
  r'/api/(chats|marriage/chats|chat-groups)(/|$)',
);

/// A fresh, unread `chat_request` notification about [_threadId].
AppNotificationModel _chatRequest() => AppNotificationModel(
  id: '9',
  title: 'New chat request',
  titleAr: 'طلب محادثة جديد',
  titleSorani: '',
  titleBadini: '',
  message: 'Someone would like to chat with you.',
  messageAr: 'يرغب شخص في التحدث معك.',
  messageSorani: '',
  messageBadini: '',
  notificationType: 'chat_request',
  notificationCategory: 'general',
  priority: 0,
  isRead: false,
  createdAt: DateTime.now(),
  relatedEntityType: 'chat_thread',
  relatedEntityId: '$_threadId',
);

// ─── Helpers ───

/// The recorded requests that went to a guest-refused chat route.
List<Uri> _chatRequests(FakeHttpOverrides http) =>
    http.requestUrls.where((u) => _guestRefusedPath.hasMatch(u.path)).toList();

/// How many times the donor-chat thread list itself was requested.
int _threadListRequests(FakeHttpOverrides http) =>
    http.requestUrls.where((u) => u.path.endsWith('/api/chats')).length;

/// How many Accept (filled) and Decline (outlined) buttons the tile draws. The
/// tile has no other buttons, so this counts exactly its chat actions.
int _actionButtons() =>
    find.byType(FilledButton).evaluate().length +
    find.byType(OutlinedButton).evaluate().length;

/// Lets requests answer and frames build in short steps, so no 5-second poll
/// fires unless a test asks for one.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps a single chat_request tile, the way the notification list hosts it.
Future<void> _pumpTile(WidgetTester tester, {VoidCallback? onTap}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: _english,
      fallbackLocale: _english,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: NotificationTile(notification: _chatRequest(), onTap: onTap),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Unmounts the tile, THEN deletes any ChatController, which cancels its poll.
///
/// Unmounting first matters: a mounted tile rebuilding after the delete would
/// find no controller and put a new one, with a new timer.
Future<void> _unmountAndStopPolling(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  if (Get.isRegistered<ChatController>()) {
    Get.delete<ChatController>(force: true);
  }
  await tester.pump();
}

void main() {
  setUp(() async {
    // isGuestMode() reads the global preferences.
    SharedPreferences.setMockInitialValues({'id_user': '7'});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
    Get.locale = _english;
  });

  tearDown(Get.reset);

  group('a guest with a chat_request notification', () {
    setUp(() async {
      // The real key, 'is_guest'. The wrong key makes every guest test here
      // pass vacuously, because the tile would simply render the member path.
      await sharedPreferences.setBool(kGuestModePrefsKey, true);
    });

    testWidgets('sees it and can tap it, but no ChatController is registered '
        'and no chat route is asked for, even after a poll interval', (
      tester,
    ) async {
      final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);
      var titleShown = false;
      var taps = 0;
      var registered = true;
      await withHttp(http, () async {
        await _pumpTile(tester, onTap: () => taps++);
        final title = find.text(_chatRequest().localizedTitle);
        titleShown = title.evaluate().isNotEmpty;
        if (titleShown) {
          await tester.tap(title);
          await _settle(tester);
        }
        // Past ChatController's 5-second poll, so a poll would have fired.
        await tester.pump(const Duration(seconds: 6));
        registered = Get.isRegistered<ChatController>();
        await _unmountAndStopPolling(tester);
      });

      expect(
        titleShown,
        isTrue,
        reason: 'hiding the actions must not hide the notification itself',
      );
      expect(taps, 1, reason: "the tile's own tap still reaches its host");
      expect(
        registered,
        isFalse,
        reason:
            'a guest ChatController fetches /chats at once and polls it every '
            '5 seconds, for a list the server always leaves empty',
      );
      expect(
        _chatRequests(http),
        isEmpty,
        reason: 'the server gives a guest nothing on these routes',
      );
    });

    testWidgets('is offered no Accept and no Decline', (tester) async {
      final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);
      var buttons = -1;
      await withHttp(http, () async {
        await _pumpTile(tester);
        buttons = _actionButtons();
        await _unmountAndStopPolling(tester);
      });

      expect(
        buttons,
        0,
        reason:
            'the server refuses a guest answer (RequireNotGuest), and signing '
            'in lands on a different account the invite is not addressed to',
      );
    });
  });

  group('a signed-in member with a chat_request notification', () {
    setUp(() async {
      await sharedPreferences.setString('role_id', '1');
    });

    testWidgets('with no ChatController yet, the tile registers one, which '
        'loads /api/chats and polls it, and draws both actions', (
      tester,
    ) async {
      expect(
        Get.isRegistered<ChatController>(),
        isFalse,
        reason: 'precondition: this pins the fallback, not a reuse',
      );
      final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);
      var registered = false;
      var buttons = -1;
      var onOpen = 0;
      var afterPoll = 0;
      await withHttp(http, () async {
        await _pumpTile(tester);
        registered = Get.isRegistered<ChatController>();
        buttons = _actionButtons();
        onOpen = _threadListRequests(http);
        await tester.pump(const Duration(seconds: 5));
        afterPoll = _threadListRequests(http);
        await _unmountAndStopPolling(tester);
      });

      expect(registered, isTrue);
      expect(buttons, 2, reason: 'Accept and Decline, as before');
      expect(onOpen, 1, reason: 'one thread-list load when the tile builds');
      expect(
        afterPoll,
        greaterThan(onOpen),
        reason: 'the 5-second poll still runs for a member',
      );
    });

    testWidgets('Decline still posts the answer for that thread', (
      tester,
    ) async {
      final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);
      var declinedShown = false;
      await withHttp(http, () async {
        await _pumpTile(tester);
        final decline = find.byType(OutlinedButton);
        if (decline.evaluate().isNotEmpty) {
          await tester.tap(decline);
          await _settle(tester);
        }
        declinedShown = find.text('Declined'.tr).evaluate().isNotEmpty;
        await _unmountAndStopPolling(tester);
      });

      expect(
        http.requestSignatures,
        contains('POST /api/chats/$_threadId/decline'),
      );
      expect(declinedShown, isTrue);
    });
  });
}
