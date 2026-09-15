// Pins what a GUEST sees on the Messages tab, OPOS #26423.
//
// WHY THIS FILE EXISTS
// The server gives a guest session an empty GET /api/chats and GET
// /api/marriage/chats, and answers thread messages with 403 guest_restricted
// (OPOS #26354). The app still built a ChatController for a guest, which
// fetched /chats when Messages opened and polled it every 5 seconds, and it
// drew the donor-chat thread list. So a guest got an "empty" or "could not
// load" state for something that is simply not available to them.
//
// WHAT IS PINNED
//   1. A guest opening Messages gets no ChatController and sends no request to
//      any chat endpoint, even after a whole poll interval.
//   2. The thread list's slot holds a sign-in prompt instead: an icon, a
//      heading, one explanatory line and a "Sign in" button. There is no
//      thread-list error and no "no conversations" empty state.
//   3. The button leaves guest mode and lands on the real sign-in route, the
//      same way the guest Home and Account tabs do (guest_sections.dart).
//   4. The support doors stay: the assistant card, live support chat and the
//      support form are all still on the tab for a guest.
//   5. The prompt reads in Arabic, right to left, with no layout error.
//   6. A signed-in member is unchanged: ChatController, a /chats request, pull
//      to refresh, and no prompt.
//
// HOW MESSAGES IS PUMPED
// As in messages_screen_chat_groups_wiring_test.dart: a bare home route, with
// Messages pushed over it by Get.to. HTTP goes through FakeHttpOverrides
// (test/support/fake_http.dart), so every URL the screen asks for is recorded.
// Every test closes Messages before it ends, which deletes a member's
// controllers and cancels their 5-second polls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';
import 'package:flutter_application_1/routes/app_routes.dart';

import '../support/fake_http.dart';

// ─── Fixtures ───

const _english = Locale('en', 'US');
const _arabic = Locale('ar', 'SA');

/// A successful, empty list: what the server now gives a guest for /chats.
const _emptyList = '{"success": true, "items": []}';

/// What the stub sign-in route renders, so a landing on it can be seen.
const _signInStub = 'sign-in-route-stub';

/// The prompt's copy, written out rather than looked up, so the words
/// themselves are pinned and a missing key cannot pass as "the key rendered".
const _promptTitleEn = 'Sign in to use Messages';
const _promptBodyEn =
    'Your conversations will appear here once you have a full account.';
const _promptTitleAr = 'سجّل الدخول لاستخدام الرسائل';
const _promptBodyAr = 'ستظهر محادثاتك هنا عندما يصبح لديك حساب كامل.';

/// Every route that gives a guest nothing or refuses them (OPOS #26354).
final _guestRefusedPath = RegExp(
  r'/api/(chats|marriage/chats|chat-groups)(/|$)',
);

// ─── Helpers ───

/// The recorded requests that went to a guest-refused chat route.
List<Uri> _chatRequests(FakeHttpOverrides http) =>
    http.requestUrls.where((u) => _guestRefusedPath.hasMatch(u.path)).toList();

/// Lets requests answer, frames build and a route transition finish, in short
/// steps, so no 5-second poll fires unless a test asks for one.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Starts the app on a bare home route, then pushes Messages over it the way
/// the dashboard's top bar does (Get.to).
///
/// The surface is tall so the whole tab, prompt included, is laid out: the
/// list builds lazily, and an off-screen prompt would not be found.
Future<void> _openMessages(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: _english,
      getPages: [
        GetPage(
          name: AppRoutes.authLogin,
          page: () => const Scaffold(body: Text(_signInStub)),
        ),
      ],
      home: const Scaffold(body: SizedBox()),
    ),
  );
  Get.to(() => const MessagesScreen());
  await _settle(tester);
}

/// Pops Messages and lets its route dispose, which deletes any controller
/// GetX tied to it.
Future<void> _closeMessages(WidgetTester tester) async {
  Get.back();
  await _settle(tester);
}

void main() {
  setUp(() async {
    // isGuestMode() reads the global preferences.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  group('a guest on Messages', () {
    setUp(() async {
      // The real key, 'is_guest'. The wrong key makes every test here pass
      // vacuously, because the screen would simply render the member path.
      await sharedPreferences.setBool(kGuestModePrefsKey, true);
    });

    testWidgets('gets no ChatController and asks for no chats, even after a '
        'poll interval', (tester) async {
      final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);
      var registered = false;
      await withHttp(http, () async {
        await _openMessages(tester, _english);
        // Past ChatController's 5-second poll, so a poll would have fired.
        await tester.pump(const Duration(seconds: 6));
        registered = Get.isRegistered<ChatController>();
        await _closeMessages(tester);
      });

      expect(
        registered,
        isFalse,
        reason:
            'a guest has no chats to list; a ChatController polls /chats '
            'every 5 seconds for an answer that is always empty',
      );
      expect(
        _chatRequests(http),
        isEmpty,
        reason: 'the server gives a guest nothing on these routes',
      );
    });

    testWidgets('sees a sign-in prompt where the thread list was, and no '
        'thread-list error or empty state', (tester) async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList),
        () async {
          await _openMessages(tester, _english);

          expect(find.text(_promptTitleEn), findsOneWidget);
          expect(find.text(_promptBodyEn), findsOneWidget);
          expect(
            find.widgetWithText(ElevatedButton, 'Sign in'),
            findsOneWidget,
          );
          expect(
            find.byIcon(Icons.forum_outlined),
            findsOneWidget,
            reason: 'the prompt carries the same mark as the Messages door',
          );

          expect(find.text('Unable to load your chats.'.tr), findsNothing);
          expect(find.text('No conversations yet'.tr), findsNothing);
          expect(
            find.byType(RefreshIndicator),
            findsNothing,
            reason: 'a guest has nothing to refresh',
          );

          await _closeMessages(tester);
        },
      );
    });

    testWidgets('keeps the assistant and both support doors', (tester) async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList),
        () async {
          await _openMessages(tester, _english);

          expect(find.text('Support Assistant'.tr), findsOneWidget);
          expect(find.text('chat_support'.tr), findsOneWidget);
          expect(find.text('support_request_form'.tr), findsOneWidget);

          await _closeMessages(tester);
        },
      );
    });

    testWidgets('Sign in leaves guest mode and opens the sign-in route', (
      tester,
    ) async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList),
        () async {
          await _openMessages(tester, _english);

          await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
          await _settle(tester);

          expect(Get.currentRoute, AppRoutes.authLogin);
          expect(find.text(_signInStub), findsOneWidget);
          expect(isGuestMode(), isFalse);
        },
      );
    });

    testWidgets('reads in Arabic, right to left, with no layout error', (
      tester,
    ) async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList),
        () async {
          await _openMessages(tester, _arabic);

          expect(tester.takeException(), isNull);
          expect(find.text(_promptTitleAr), findsOneWidget);
          expect(find.text(_promptBodyAr), findsOneWidget);
          expect(
            find.widgetWithText(ElevatedButton, 'تسجيل الدخول'),
            findsOneWidget,
          );
          expect(
            Directionality.of(tester.element(find.text(_promptTitleAr))),
            TextDirection.rtl,
          );

          await _closeMessages(tester);
        },
      );
    });
  });

  group('a signed-in member on Messages', () {
    testWidgets('still gets ChatController, the /chats request and pull to '
        'refresh, and no prompt', (tester) async {
      final http = FakeHttpOverrides(HttpBehaviour.ok, body: _emptyList);
      var registered = false;
      await withHttp(http, () async {
        await _openMessages(tester, _english);
        registered = Get.isRegistered<ChatController>();

        expect(find.text(_promptTitleEn), findsNothing);
        expect(find.byType(RefreshIndicator), findsOneWidget);
        expect(find.text('No conversations yet'.tr), findsOneWidget);

        await _closeMessages(tester);
      });

      expect(registered, isTrue);
      expect(
        http.requestUrls.where((u) => u.path.endsWith('/api/chats')),
        isNotEmpty,
        reason: 'a member still loads the thread list',
      );
    });
  });
}
