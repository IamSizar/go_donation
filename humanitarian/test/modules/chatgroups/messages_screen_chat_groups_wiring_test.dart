// Pins how the chat-groups block is wired into the Messages tab, OPOS #25284
// Phase 5 Task 4 and review task #26331.
//
// WHAT IS PINNED
//   1. Source order: the block comes AFTER the 1:1 threads — so a failure in it
//      can never push the bot and support doors off the top of the tab — and is
//      never built for a guest, who cannot message (the server's chat-group
//      POST routes all carry auth.RequireNotGuest).
//   2. Opening Messages registers ChatGroupsController at once, before the
//      block has ever been built, and closing Messages deletes it. GetX deletes
//      a controller together with the route that was current when it was put.
//      The block is the last child of a lazily built ListView, so a controller
//      made there could be put while another route is current and never be
//      deleted, polling every 5 seconds for the rest of the session.
//   3. A guest gets no groups controller at all.
//   4. Pull-to-refresh refreshes the groups as well as the threads.
//
// HOW MESSAGES IS PUMPED
// MessagesScreen builds a real ChatController on ModuleApi. Under testWidgets
// flutter_test answers every HTTP request with a 400 itself, so the thread list
// lands on its error state and no network is touched. Every test closes
// Messages before it ends, which cancels both controllers' 5-second polls.
import 'dart:io';

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
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_groups_controller.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_groups_section.dart';

import 'fake_chat_groups_api.dart';

const _messagesScreenPath = 'lib/modules/chat/screens/messages_screen.dart';

/// Lets requests answer, frames build and a route transition finish — in
/// short steps, so no 5-second poll fires inside a test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Starts the app on a bare home route, then pushes Messages over it the way
/// the dashboard does (Get.to). The screen is short, so the groups block — the
/// list's last child — is not built yet.
Future<void> _pushMessages(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const locale = Locale('en', 'US');
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      home: const Scaffold(body: SizedBox()),
    ),
  );
  Get.to(() => const MessagesScreen());
  await _settle(tester);
}

/// Pops Messages and lets its route dispose, which is what deletes the
/// controllers GetX tied to it.
Future<void> _popMessages(WidgetTester tester) async {
  Get.back();
  await _settle(tester);
}

void main() {
  setUp(() async {
    // isGuestMode() and the chimes read the global preferences.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  test('the block follows the 1:1 threads and is hidden from guests', () {
    final file = File(_messagesScreenPath);
    if (!file.existsSync()) {
      fail('$_messagesScreenPath is missing — this test needs updating');
    }
    final source = file.readAsStringSync();

    final bot = source.indexOf('const _BotAssistantCard()');
    final threads = source.indexOf('AppAsync<List<dynamic>>(');
    final block = source.indexOf('if (!isGuestMode()) const ChatGroupsSection()');

    expect(bot, isNot(-1));
    expect(threads, isNot(-1));
    expect(
      block,
      isNot(-1),
      reason: 'ChatGroupsSection must be rendered, and only for non-guests',
    );
    expect(block, greaterThan(threads));
    expect(bot, lessThan(block));
  });

  testWidgets(
    'opening Messages registers the groups controller before the block is '
    'built, and closing Messages deletes it',
    (tester) async {
      await _pushMessages(tester);

      expect(find.byType(MessagesScreen), findsOneWidget);
      expect(
        find.byType(ChatGroupsSection, skipOffstage: false),
        findsNothing,
        reason: 'the screen must be short enough that the block is unbuilt',
      );
      expect(Get.isRegistered<ChatGroupsController>(), isTrue);

      await _popMessages(tester);

      expect(Get.isRegistered<ChatGroupsController>(), isFalse);
      expect(Get.isRegistered<ChatController>(), isFalse);
    },
  );

  testWidgets('a guest gets no groups controller', (tester) async {
    await sharedPreferences.setBool(kGuestModePrefsKey, true);
    await _pushMessages(tester);

    expect(Get.isRegistered<ChatGroupsController>(), isFalse);
    await _popMessages(tester);
  });

  testWidgets('pull-to-refresh refreshes the groups as well', (tester) async {
    final api = FakeChatGroupsApi();
    // Registered before Messages opens, so Messages finds this one and its
    // calls can be counted. No route owns it, so the test deletes it.
    Get.put(ChatGroupsController(api: api));
    await _pushMessages(tester);
    final callsBefore = api.groupsCalls;

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    // Three seconds: long enough for the indicator to run, short of the
    // controller's 5-second poll, which would add a call of its own.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(api.groupsCalls, callsBefore + 1);
    await _popMessages(tester);
    await Get.delete<ChatGroupsController>(force: true);
  });
}
