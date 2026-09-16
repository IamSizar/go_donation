// Pins the Messages tab when a thread refresh fails while threads are already
// on screen — OPOS #26349.
//
// WHAT IS PINNED
//   The threads stay readable under the "could not load" banner, and the tab's
//   layout does not break. The thread list's AppAsync sits directly inside the
//   tab's ListView; when a visible refresh (pull-to-refresh, or opening the tab
//   with threads already held) failed, AppErrorState wrapped the loaded threads
//   in an Expanded, which asserts inside an unbounded scroll view.
//
// HOW MESSAGES IS PUMPED
// As in messages_screen_chat_groups_wiring_test.dart: MessagesScreen builds a
// real ChatController on ModuleApi, and under testWidgets flutter_test answers
// every HTTP request with a 400 itself, so the thread load lands on its error
// state without touching the network. The test then puts a thread into the
// controller — threads held, error showing — and closes Messages before it
// ends, which cancels the controllers' 5-second polls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';

/// Lets requests answer, frames build and a route transition finish — in
/// short steps, so no 5-second poll fires inside the test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// An accepted donor ↔ owner thread, as the chats list would return it.
ChatThread _activeThread() => const ChatThread(
  id: 7,
  status: 'active',
  campaignId: 3,
  campaignTitle: 'Winter appeal',
  initiatedBy: 1,
  myRole: 'donor',
  incomingPending: false,
  otherUserId: 2,
  otherName: 'Campaign owner',
  otherPhone: null,
  lastMessage: 'Thank you for your support',
  lastMessageAt: null,
  unreadCount: 0,
  assignedStaffName: null,
);

void main() {
  setUp(() async {
    // isGuestMode() and the chimes read the global preferences.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('a failed refresh keeps the threads readable and the tab intact', (
    tester,
  ) async {
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

    // The load failed (flutter_test's 400); now threads are held as well.
    final ctrl = Get.find<ChatController>();
    expect(ctrl.errorMessage.value, isNotNull);
    ctrl.threads.assignAll([_activeThread()]);
    await _settle(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'the stale threads must not break the tab layout',
    );
    expect(find.text('Campaign owner'), findsOneWidget);
    expect(find.text(ctrl.errorMessage.value!), findsOneWidget);

    Get.back();
    await _settle(tester);
  });
}
