// Pins how ChatGroupConversationController LOADS one staff-mediated group
// chat — masked or team alike — OPOS #25284 Phase 5. Sending is pinned in
// chat_group_conversation_send_test.dart.
//
// WHAT IS PINNED
//   1. A load shows the transcript with each sender's server-resolved label,
//      plus the staff-controlled lifecycle and its reason.
//   2. Long conversations. The server pages oldest-first, 100 at most per
//      request. Opening loads EVERY page; a poll asks only for messages after
//      the newest one shown and appends them. (The first version replaced the
//      list with page one, so a group past 50 messages stopped updating.)
//   3. One load at a time. Requests can take 12 seconds on the connections
//      this app is used on; overlapping loads applied out of order hid
//      just-sent messages and double-chimed.
//   4. Nothing happens once the screen has closed.
//   5. The read cursor: the newest message shown is marked read on open and
//      whenever a poll brings newer messages — never re-sent for an unchanged
//      poll, never sent for an empty chat, retried after a failure. Why the id
//      matters: test/api/chat_group_mark_read_test.dart.
//   6. The chime: someone else's new message chimes; the opening load and the
//      member's own message do not.
//   7. The 3-second poll really runs, and really stops once closed.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_group_conversation_controller.dart';

import 'fake_chat_groups_api.dart';

const _groupId = 5;

/// Lets every pending future and microtask run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() async {
    // The real chime reads the global mute preference.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
  });

  tearDown(Get.reset);

  final twoMessages = [
    messageRow(id: 11, senderLabel: 'Donor 1', body: 'Hello'),
    messageRow(id: 12, senderLabel: 'Support', body: 'Welcome'),
  ];

  group('loading the transcript', () {
    test('shows each message with the label the server resolved', () async {
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(ctrl.messages.map((m) => m.senderLabel), ['Donor 1', 'Support']);
      expect(ctrl.messages.map((m) => m.body), ['Hello', 'Welcome']);
      expect(ctrl.lifecycle.value, 'open');
      expect(ctrl.isLoading.value, isFalse);
      expect(ctrl.errorMessage.value, isNull);
    });

    test('a paused group exposes the lifecycle and the staff reason', () async {
      final api = FakeChatGroupsApi()
        ..transcript = twoMessages
        ..lifecycle = 'paused'
        ..lifecycleReason = '  Staff are reviewing this chat.  ';
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(ctrl.lifecycle.value, 'paused');
      expect(ctrl.lifecycleReason.value, 'Staff are reviewing this chat.');
    });

    test('a blank staff reason is no reason at all', () async {
      final api = FakeChatGroupsApi()
        ..transcript = twoMessages
        ..lifecycle = 'ended'
        ..lifecycleReason = '   ';
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(ctrl.lifecycle.value, 'ended');
      expect(ctrl.lifecycleReason.value, isNull);
    });

    test('a failed first load says what failed and what to do next', () async {
      final api = FakeChatGroupsApi()
        ..messagesError = const SocketException('no route to host');
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(ctrl.messages, isEmpty);
      expect(ctrl.isLoading.value, isFalse);
      expect(
        ctrl.errorMessage.value,
        allOf(
          contains('Could not load this conversation.'),
          contains('Check your connection'),
        ),
      );
    });

    test('a failed silent poll keeps the transcript and shows no error', () async {
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(_groupId, api: api);
      await ctrl.fetchMessages();

      api.messagesError = Exception('Database error.');
      await ctrl.fetchMessages(silent: true);

      expect(ctrl.messages.map((m) => m.id), [11, 12]);
      expect(ctrl.errorMessage.value, isNull);
    });

    test('a poll that succeeds after a failed first load clears the error', () async {
      final api = FakeChatGroupsApi()
        ..messagesError = Exception('Request timed out.');
      final ctrl = ChatGroupConversationController(_groupId, api: api);
      await ctrl.fetchMessages();
      expect(ctrl.errorMessage.value, isNotNull);

      api
        ..messagesError = null
        ..transcript = twoMessages;
      await ctrl.fetchMessages(silent: true);

      expect(ctrl.messages.map((m) => m.id), [11, 12]);
      expect(
        ctrl.errorMessage.value,
        isNull,
        reason:
            'the conversation has loaded; a "could not load" banner left over '
            'from the first attempt would contradict what is on screen',
      );
    });

    test('a poll that brings nothing new does not notify the transcript', () async {
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(_groupId, api: api);
      await ctrl.fetchMessages();
      var notified = 0;
      final worker = ever(ctrl.messages, (_) => notified++);
      addTearDown(worker.dispose);

      await ctrl.fetchMessages(silent: true);

      expect(
        notified,
        0,
        reason:
            'every listener would otherwise fire every three seconds — review '
            'caught the screen scrolling a reader back to the bottom this way',
      );
    });
  });

  group('long conversations', () {
    test('opening loads every page of the history, not just the first', () async {
      final api = FakeChatGroupsApi()..transcript = numberedMessages(120);
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(ctrl.messages.length, 120);
      expect(ctrl.messages.first.id, 1);
      expect(ctrl.messages.last.id, 120);
      expect(api.messageRequests, [
        (afterId: 0, limit: 100),
        (afterId: 100, limit: 100),
      ]);
    });

    test('a poll asks only for messages after the newest shown, and appends them', () async {
      final api = FakeChatGroupsApi()..transcript = numberedMessages(120);
      final ctrl = ChatGroupConversationController(_groupId, api: api);
      await ctrl.fetchMessages();

      api.transcript = numberedMessages(121);
      await ctrl.fetchMessages(silent: true);

      expect(api.messageRequests.last, (afterId: 120, limit: 100));
      expect(ctrl.messages.length, 121);
      expect(ctrl.messages.last.id, 121);
      expect(api.markedRead.last.lastReadMessageId, 121);
    });
  });

  group('one load at a time', () {
    test('a poll tick while a load is in flight sends no second request', () async {
      final api = FakeChatGroupsApi()
        ..transcript = twoMessages
        ..messagesGate = Completer<void>();
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      final opening = ctrl.fetchMessages();
      unawaited(ctrl.fetchMessages(silent: true));
      await _settle();
      expect(api.messagesCalls, 1);

      api.messagesGate!.complete();
      await opening;
      await _settle();
      expect(ctrl.messages.map((m) => m.id), [11, 12]);
      expect(
        api.messagesCalls,
        1,
        reason:
            'the skipped tick must not run later either: on a slow connection '
            'queued ticks would pile up behind every request',
      );
    });

    test('the refresh after a send waits for the load already in flight', () async {
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(_groupId, api: api);
      await ctrl.fetchMessages();

      final gate = Completer<void>();
      api.messagesGate = gate;
      final poll = ctrl.fetchMessages(silent: true);
      final sending = ctrl.send('Thank you');
      await _settle();
      api.messagesGate = null;
      gate.complete();
      await poll;

      expect(await sending, isTrue);
      expect(ctrl.messages.map((m) => m.id), [11, 12, 13]);
      expect(api.maxConcurrentMessageRequests, 1);
    });
  });

  test('a load that finishes after the screen closed changes nothing', () async {
    var chimes = 0;
    final api = FakeChatGroupsApi()
      ..transcript = twoMessages
      ..messagesGate = Completer<void>();
    final ctrl = Get.put(
      ChatGroupConversationController(
        _groupId,
        api: api,
        onIncomingMessage: () => chimes++,
      ),
    );
    await _settle(); // onInit's opening load is now held at the gate

    Get.delete<ChatGroupConversationController>();
    await _settle();
    api.messagesGate!.complete();
    await _settle();

    expect(ctrl.messages, isEmpty);
    expect(api.markedRead, isEmpty);
    expect(chimes, 0);
  });

  group('the read cursor', () {
    test('opening the conversation marks the newest message read', () async {
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(api.markedRead, [(groupId: _groupId, lastReadMessageId: 12)]);
    });

    test('a poll marks newer messages read; an unchanged poll sends nothing', () async {
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(_groupId, api: api);
      await ctrl.fetchMessages();

      await ctrl.fetchMessages(silent: true);
      api.transcript = [
        ...twoMessages,
        messageRow(id: 13, senderLabel: 'Volunteer 1', body: 'On my way'),
      ];
      await ctrl.fetchMessages(silent: true);

      expect(api.markedRead.map((r) => r.lastReadMessageId), [12, 13]);
    });

    test('an empty conversation marks nothing read', () async {
      final api = FakeChatGroupsApi();
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();

      expect(api.markedRead, isEmpty);
    });

    test('a failed mark-read stays silent and is retried on the next poll', () async {
      final api = FakeChatGroupsApi()
        ..transcript = twoMessages
        ..markReadError = Exception('Database error.');
      final ctrl = ChatGroupConversationController(_groupId, api: api);

      await ctrl.fetchMessages();
      expect(ctrl.messages.map((m) => m.id), [11, 12]);
      expect(ctrl.errorMessage.value, isNull);

      api.markReadError = null;
      await ctrl.fetchMessages(silent: true);

      expect(api.markedRead.map((r) => r.lastReadMessageId), [12]);
    });
  });

  group('the incoming-message chime', () {
    test('the opening load stays quiet', () async {
      var chimes = 0;
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(
        _groupId,
        api: api,
        onIncomingMessage: () => chimes++,
      );

      await ctrl.fetchMessages();

      expect(chimes, 0);
    });

    test("someone else's new message chimes once", () async {
      var chimes = 0;
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(
        _groupId,
        api: api,
        onIncomingMessage: () => chimes++,
      );
      await ctrl.fetchMessages();

      api.transcript = [
        ...twoMessages,
        messageRow(id: 13, senderLabel: 'Volunteer 1', body: 'On my way'),
      ];
      await ctrl.fetchMessages(silent: true);
      await ctrl.fetchMessages(silent: true);

      expect(chimes, 1);
    });

    test('the first message in an empty group chimes', () async {
      var chimes = 0;
      final api = FakeChatGroupsApi();
      final ctrl = ChatGroupConversationController(
        _groupId,
        api: api,
        onIncomingMessage: () => chimes++,
      );
      await ctrl.fetchMessages();

      api.transcript = [messageRow(id: 1, senderLabel: 'Support', body: 'Hi')];
      await ctrl.fetchMessages(silent: true);

      expect(chimes, 1);
    });

    test("the member's own message coming back after a send stays quiet", () async {
      var chimes = 0;
      final api = FakeChatGroupsApi()..transcript = twoMessages;
      final ctrl = ChatGroupConversationController(
        _groupId,
        api: api,
        onIncomingMessage: () => chimes++,
      );
      await ctrl.fetchMessages();

      await ctrl.send('Thank you');

      expect(ctrl.messages.last.body, 'Thank you');
      expect(chimes, 0);
    });
  });

  testWidgets('polls every 3 seconds and stops once closed', (tester) async {
    final api = FakeChatGroupsApi()..transcript = twoMessages;
    Get.put(ChatGroupConversationController(_groupId, api: api));
    await tester.pump();
    expect(api.messagesCalls, 1, reason: 'opening the conversation loads once');

    await tester.pump(const Duration(seconds: 3));
    expect(api.messagesCalls, 2, reason: 'one background poll after 3s');

    Get.delete<ChatGroupConversationController>();
    await tester.pump(const Duration(seconds: 9));
    expect(api.messagesCalls, 2, reason: 'no polling after the controller closes');
  });
}
