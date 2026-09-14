// Pins ChatGroupConversationScreen — the one conversation screen for masked
// and team group chats, OPOS #25284 Phase 5 Task 3.
//
// WHAT IS PINNED
//   1. Masking: a message shows the label the server resolved and its body —
//      nothing that could carry a member's identity. (The plan's version of
//      this test only inspected the model, never the screen.)
//   2. The states a transcript can be in: a designed empty state; a failed
//      first load shown as an error with Retry — never as "No messages yet",
//      which would tell a member their conversation is empty when it merely
//      failed to load; and the transcript itself.
//   3. A paused or ended chat replaces the composer with the lifecycle notice.
//   4. Sending: a sent message clears the box and appears in the transcript; a
//      refused one keeps the member's typed text and says why.
//   5. Rule 5.6: dragging the transcript dismisses the keyboard.
//   6. RTL: in Arabic the member's own message sits at the reading end, on the
//      left — a hard-coded `Alignment.centerRight` puts it on the wrong side.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/chat_group_conversation_screen.dart';

import 'fake_chat_groups_api.dart';

const _groupId = 5;
const _sendButton = Key('chat_group_send');

/// Lets the fake API answer and the resulting frames build. Short steps, so
/// the controller's 3-second poll never fires inside a test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the screen on [api] and waits for its opening load.
Future<void> _open(
  WidgetTester tester,
  FakeChatGroupsApi api, {
  Locale locale = const Locale('en', 'US'),
}) async {
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      home: ChatGroupConversationScreen(
        groupId: _groupId,
        title: 'Connection',
        api: api,
      ),
    ),
  );
  await _settle(tester);
}

/// Leaves the screen, so its controller and 3-second poll are disposed before
/// the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// The text currently in the composer.
String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  setUp(() async {
    // The incoming-message chime reads the global mute preference.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('a message shows its resolved label and body, and no member id', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..transcript = [
        messageRow(
          id: 11,
          senderLabel: 'Donor 1',
          senderMemberId: 98765,
          body: 'Hello',
        ),
      ];

    await _open(tester, api);

    expect(find.text('Donor 1'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.textContaining('98765'), findsNothing);
    await _close(tester);
  });

  testWidgets('an empty conversation shows the designed empty state', (
    tester,
  ) async {
    await _open(tester, FakeChatGroupsApi());

    expect(find.text('No messages yet. Say hello! 👋'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a failed first load is an error with Retry, not an empty chat', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..messagesError = const SocketException('no route to host');

    await _open(tester, api);

    expect(find.textContaining('Could not load this conversation.'), findsOneWidget);
    expect(find.text('No messages yet. Say hello! 👋'), findsNothing);

    api
      ..messagesError = null
      ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Welcome')];
    await tester.tap(find.text(AppTranslations.englishForTest['retry']!));
    await _settle(tester);

    expect(find.text('Welcome'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a closed chat replaces the composer with the lifecycle notice', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Welcome')]
      ..lifecycle = 'ended';

    await _open(tester, api);

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChatLifecycleNotice), findsOneWidget);
    await _close(tester);
  });

  group('sending', () {
    testWidgets('a sent message clears the box and appears in the transcript', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Welcome')];
      await _open(tester, api);

      await tester.enterText(find.byType(TextField), 'Thank you');
      await tester.tap(find.byKey(_sendButton));
      await _settle(tester);

      expect(api.sentBodies, ['Thank you']);
      expect(find.text('Thank you'), findsOneWidget);
      expect(_composerText(tester), isEmpty);
      await _close(tester);
    });

    testWidgets('a refused message keeps the typed text and says why', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Welcome')]
        ..sendError = const ApiCodedException(
          code: 'contact_details_blocked',
          developerMessage: 'Phone numbers cannot be shared in this chat.',
        );
      await _open(tester, api);

      await tester.enterText(find.byType(TextField), 'Call me on 07701234567');
      await tester.tap(find.byKey(_sendButton));
      await _settle(tester);

      expect(_composerText(tester), 'Call me on 07701234567');
      expect(find.textContaining('cannot be shared'), findsOneWidget);
      await _close(tester);
    });
  });

  testWidgets('dragging the transcript dismisses the keyboard', (tester) async {
    final api = FakeChatGroupsApi()..transcript = numberedMessages(3);
    await _open(tester, api);

    final list = tester.widget<ListView>(find.byType(ListView));

    expect(
      list.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
    await _close(tester);
  });

  testWidgets("in Arabic the member's own message sits on the left", (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..transcript = [
        messageRow(id: 11, senderLabel: 'الدعم', body: 'مرحبا'),
        messageRow(id: 12, senderLabel: 'أنت', body: 'شكرا', isMine: true),
      ];

    await _open(tester, api, locale: const Locale('ar', 'SA'));

    final theirs = tester.getCenter(find.text('مرحبا')).dx;
    final mine = tester.getCenter(find.text('شكرا')).dx;
    expect(
      mine,
      lessThan(theirs),
      reason: 'right-to-left: the reader starts on the right, so their own '
          'messages belong at the end — the left',
    );
    await _close(tester);
  });
}
