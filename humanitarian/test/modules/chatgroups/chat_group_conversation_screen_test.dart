// Pins ChatGroupConversationScreen — the one conversation screen for masked
// and team group chats, OPOS #25284 Phase 5 Task 3.
//
// WHAT IS PINNED
//   1. Masking: a message shows the label the server resolved and its body —
//      nothing that could carry a member's identity. (The plan's version of
//      this test only inspected the model, never the screen.) The server's own
//      generated words are drawn in the reader's language, so "Donor 1" reads
//      "Grantor 1" in English (OPOS #26419; the mapping is pinned in
//      chat_group_sender_label_test.dart).
//   2. The states a transcript can be in: a skeleton while loading; a designed
//      empty state (which does not invite a first message into a chat staff
//      have closed); a failed first load shown as an error with Retry — never
//      as "No messages yet"; a group that is gone for this member (deleted,
//      archived, or the member removed) shown as "no longer available" with
//      no Retry and no composer — also when a poll finds out mid-chat, and
//      in Arabic; and the transcript itself.
//   3. A paused or ended chat replaces the composer with the lifecycle notice.
//   4. Sending: a sent message clears the box and appears; a refused one keeps
//      the member's typed text — including anything typed while it was in
//      flight — and says why.
//   5. Reading: a poll that brings nothing new leaves a reader who scrolled up
//      where they are, and opening the keyboard keeps the newest message in
//      view. (Both were broken in review: every 3-second poll snapped the
//      reader back to the bottom.)
//   6. Rule 5.6: dragging the transcript dismisses the keyboard.
//   7. RTL: in Arabic the member's own message sits at the reading end, on the
//      left — a hard-coded `Alignment.centerRight` puts it on the wrong side.
//   8. The same group opened twice (a notification tap over an open chat)
//      leaves the first screen working after the second is closed.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/api_status_exception.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/chat_group_conversation_screen.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_group_composer.dart';

import 'fake_chat_groups_api.dart';

const _groupId = 5;
const _sendButton = Key('chat_group_send');

/// Lets the fake API answer and the resulting frames build. Short steps, so
/// the controller's 3-second poll never fires inside a settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The screen inside the app shell every test uses.
Widget _app(FakeChatGroupsApi api, Locale locale) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: locale,
  home: ChatGroupConversationScreen(
    groupId: _groupId,
    title: 'Connection',
    api: api,
  ),
);

/// Opens the screen on [api] and waits for its opening load.
Future<void> _open(
  WidgetTester tester,
  FakeChatGroupsApi api, {
  Locale locale = const Locale('en', 'US'),
}) async {
  Get.locale = locale;
  await tester.pumpWidget(_app(api, locale));
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

/// The transcript's scroll position.
ScrollPosition _transcriptPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

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

    // The server's generated alias, in the app's English role noun.
    expect(find.text('Grantor 1'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.textContaining('98765'), findsNothing);
    await _close(tester);
  });

  group('transcript states', () {
    testWidgets('the skeleton shows while the conversation is loading', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Hi')]
        ..messagesGate = Completer<void>();

      await _open(tester, api);

      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.text('Hi'), findsNothing);
      await _close(tester);
    });

    testWidgets('an empty conversation shows the designed empty state', (
      tester,
    ) async {
      await _open(tester, FakeChatGroupsApi());

      expect(find.text('No messages yet. Say hello! 👋'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('an empty chat staff have closed does not invite a message', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()..lifecycle = 'ended';

      await _open(tester, api);

      expect(find.byType(ChatLifecycleNotice), findsOneWidget);
      expect(find.textContaining('Send the first message'), findsNothing);
      expect(find.text('No messages yet. Say hello! 👋'), findsNothing);
      await _close(tester);
    });

    testWidgets('a failed first load is an error with Retry, not an empty chat', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..messagesError = const SocketException('no route to host');

      await _open(tester, api);

      expect(
        find.textContaining('Could not load this conversation.'),
        findsOneWidget,
      );
      expect(find.text('No messages yet. Say hello! 👋'), findsNothing);

      api
        ..messagesError = null
        ..transcript = [
          messageRow(id: 11, senderLabel: 'Support', body: 'Welcome'),
        ];
      await tester.tap(find.text(AppTranslations.englishForTest['retry']!));
      await _settle(tester);

      expect(find.text('Welcome'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('a group that is gone says so, with no Retry and no composer', (
      tester,
    ) async {
      // Staff deleted the group: the server answers 404 however often asked.
      final api = FakeChatGroupsApi()
        ..messagesError = const ApiStatusException(404);

      await _open(tester, api);

      expect(
        find.text('This conversation is no longer available'),
        findsOneWidget,
      );
      expect(
        find.text(AppTranslations.englishForTest['retry']!),
        findsNothing,
        reason: 'retrying a group that no longer exists can never succeed',
      );
      expect(find.byType(ChatGroupComposer), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await _close(tester);
    });

    testWidgets('a member removed mid-chat loses the transcript and composer', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Hi')];
      await _open(tester, api);
      expect(find.text('Hi'), findsOneWidget);

      api.messagesError = const ApiStatusException(403);
      await tester.pump(const Duration(seconds: 3)); // one background poll
      await _settle(tester);

      expect(
        find.text('This conversation is no longer available'),
        findsOneWidget,
      );
      expect(find.text('Hi'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await _close(tester);
    });

    testWidgets('a group that is gone says so in Arabic', (tester) async {
      final api = FakeChatGroupsApi()
        ..messagesError = const ApiStatusException(403);

      await _open(tester, api, locale: const Locale('ar', 'SA'));

      expect(find.text('هذه المحادثة لم تعد متاحة'), findsOneWidget);
      expect(find.text(AppTranslations.arabicForTest['retry']!), findsNothing);
      await _close(tester);
    });
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
        ..transcript = [
          messageRow(id: 11, senderLabel: 'Support', body: 'Welcome'),
        ];
      await _open(tester, api);

      await tester.enterText(find.byType(TextField), 'Thank you');
      // The send button enables on the frame after text arrives, as it would
      // between a person typing and tapping.
      await tester.pump();
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
        ..transcript = [
          messageRow(id: 11, senderLabel: 'Support', body: 'Welcome'),
        ]
        ..sendError = const ApiCodedException(
          code: 'contact_details_blocked',
          developerMessage: 'Phone numbers cannot be shared in this chat.',
        );
      await _open(tester, api);

      await tester.enterText(find.byType(TextField), 'Call me on 07701234567');
      // The send button enables on the frame after text arrives, as it would
      // between a person typing and tapping.
      await tester.pump();
      await tester.tap(find.byKey(_sendButton));
      await _settle(tester);

      expect(_composerText(tester), 'Call me on 07701234567');
      expect(find.textContaining('cannot be shared'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('a failed send keeps what was typed while it was in flight', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()
        ..transcript = [
          messageRow(id: 11, senderLabel: 'Support', body: 'Welcome'),
        ]
        ..sendGate = Completer<void>()
        ..sendError = Exception('Request timed out.');
      await _open(tester, api);

      await tester.enterText(find.byType(TextField), 'first message');
      // The send button enables on the frame after text arrives, as it would
      // between a person typing and tapping.
      await tester.pump();
      await tester.tap(find.byKey(_sendButton));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'second thought');
      api.sendGate!.complete();
      await _settle(tester);

      expect(
        _composerText(tester),
        allOf(contains('first message'), contains('second thought')),
        reason: 'neither the failed message nor the new draft may be lost',
      );
      await _close(tester);
    });
  });

  group('reading', () {
    testWidgets('a poll with nothing new leaves a reader where they scrolled', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()..transcript = numberedMessages(60);
      await _open(tester, api);

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await _settle(tester);
      final scrolledTo = _transcriptPosition(tester).pixels;

      await tester.pump(const Duration(seconds: 3)); // one background poll
      await _settle(tester);

      expect(
        _transcriptPosition(tester).pixels,
        scrolledTo,
        reason: 'a reader of older messages must not be pulled back to the '
            'bottom every three seconds',
      );
      await _close(tester);
    });

    testWidgets('opening the keyboard keeps the newest message in view', (
      tester,
    ) async {
      final api = FakeChatGroupsApi()..transcript = numberedMessages(40);
      await _open(tester, api);
      expect(find.text('Message 40'), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await _settle(tester);

      final visible = tester.getRect(find.byType(ListView));
      final newest = tester.getRect(find.text('Message 40'));
      expect(
        visible.contains(newest.center),
        isTrue,
        reason: 'a member tapping the box to reply must still see the message '
            'they are answering',
      );
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

  testWidgets('the same group opened twice keeps the first screen working', (
    tester,
  ) async {
    final api = FakeChatGroupsApi()
      ..transcript = [messageRow(id: 11, senderLabel: 'Support', body: 'Hello')];
    await _open(tester, api);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatGroupConversationScreen(
            groupId: _groupId,
            title: 'Connection',
            api: api,
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await _settle(tester);
    }
    navigator.pop();
    for (var i = 0; i < 3; i++) {
      await _settle(tester);
    }

    api.transcript = [
      ...api.transcript,
      messageRow(id: 12, senderLabel: 'Support', body: 'Still here'),
    ];
    await tester.pump(const Duration(seconds: 3)); // the first screen's poll
    await _settle(tester);

    expect(
      find.text('Still here'),
      findsOneWidget,
      reason: 'closing the second screen must not stop the first one polling',
    );
    await _close(tester);
  });
}
