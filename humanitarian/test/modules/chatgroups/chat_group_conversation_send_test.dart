// Pins how ChatGroupConversationController SENDS into a staff-mediated group
// chat, OPOS #25284 Phase 5. Loading is pinned in
// chat_group_conversation_controller_test.dart.
//
// WHAT IS PINNED
//   1. A send trims the text, posts it, and shows the stored message.
//   2. A blank message never reaches the server.
//   3. A failure is reported through the controller's OWN send error: the
//      transcript and the load error are left alone, and `false` tells the
//      screen to keep the member's typed text.
//   4. A refusal the server NAMES is explained, not met with "try again":
//      contact details in a supervised chat (422 contact_details_blocked) can
//      never be sent, and a chat staff have paused or ended
//      (409 chat_lifecycle_closed) is refreshed so its closed notice replaces
//      the composer. Both sentences exist in Arabic.
//   5. One send at a time, and the send stays "in progress" until the sent
//      message is actually on screen — so a screen that disables its button on
//      isSending cannot double-send.
//   6. A send that was stored still counts as sent when the refresh after it
//      fails; the next poll will show it.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
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

  /// A conversation that has finished its opening load of [twoMessages].
  Future<ChatGroupConversationController> openConversation(
    FakeChatGroupsApi api,
  ) async {
    api.transcript = twoMessages;
    final ctrl = ChatGroupConversationController(_groupId, api: api);
    await ctrl.fetchMessages();
    return ctrl;
  }

  test('trims the text, posts it and shows the stored message', () async {
    final api = FakeChatGroupsApi();
    final ctrl = await openConversation(api);

    final sent = await ctrl.send('  Thank you  ');

    expect(sent, isTrue);
    expect(api.sentBodies, ['Thank you']);
    expect(ctrl.messages.last.body, 'Thank you');
    expect(ctrl.isSending.value, isFalse);
    expect(ctrl.sendError.value, isNull);
  });

  test('a blank message is never sent', () async {
    final api = FakeChatGroupsApi();
    final ctrl = await openConversation(api);

    final sent = await ctrl.send('   ');

    expect(sent, isFalse);
    expect(api.sentBodies, isEmpty);
  });

  test('a failed send reports its own error and leaves the transcript alone', () async {
    final api = FakeChatGroupsApi();
    final ctrl = await openConversation(api);

    api.sendError = Exception('Database error.');
    final sent = await ctrl.send('Thank you');

    expect(sent, isFalse);
    expect(ctrl.sendError.value, contains('Could not send your message.'));
    expect(ctrl.errorMessage.value, isNull, reason: 'not a load failure');
    expect(ctrl.messages.map((m) => m.id), [11, 12]);
    expect(ctrl.isSending.value, isFalse);
  });

  group('a refusal the server names', () {
    test('contact details are explained, not met with "try again"', () async {
      final api = FakeChatGroupsApi();
      final ctrl = await openConversation(api);

      api.sendError = const ApiCodedException(
        code: 'contact_details_blocked',
        developerMessage: 'Phone numbers cannot be shared in this chat.',
      );
      final sent = await ctrl.send('Call me on 07701234567');

      expect(sent, isFalse);
      expect(
        ctrl.sendError.value,
        allOf(
          contains('cannot be shared'),
          isNot(contains('Could not send your message.')),
          isNot(contains('chat_group_')),
        ),
      );
    });

    test('a closed chat is refreshed so its notice replaces the composer', () async {
      final api = FakeChatGroupsApi();
      final ctrl = await openConversation(api);

      api
        ..lifecycle = 'ended'
        ..sendError = const ApiCodedException(
          code: 'chat_lifecycle_closed',
          developerMessage: 'This conversation has been closed by our team.',
        );
      final sent = await ctrl.send('Thank you');

      expect(sent, isFalse);
      expect(ctrl.lifecycle.value, 'ended');
      expect(
        ctrl.sendError.value,
        allOf(
          isNotNull,
          isNot(contains('Could not send your message.')),
          isNot(contains('chat_group_')),
        ),
      );
    });

    test('both explanations are written in Arabic', () async {
      Get.locale = const Locale('ar', 'SA');
      for (final code in ['contact_details_blocked', 'chat_lifecycle_closed']) {
        final api = FakeChatGroupsApi();
        final ctrl = await openConversation(api);
        api.sendError = ApiCodedException(code: code, developerMessage: 'x');

        await ctrl.send('Thank you');

        final sentence = ctrl.sendError.value ?? '';
        expect(sentence, isNotEmpty, reason: code);
        expect(RegExp(r'[A-Za-z]').hasMatch(sentence), isFalse, reason: '$code: $sentence');
      }
    });
  });

  group('one send at a time', () {
    test('a second send while one is in flight is refused', () async {
      final api = FakeChatGroupsApi();
      final ctrl = await openConversation(api);

      final gate = Completer<void>();
      api.sendGate = gate;
      final first = ctrl.send('One');
      await _settle();
      final second = await ctrl.send('Two');
      api.sendGate = null;
      gate.complete();

      expect(second, isFalse);
      expect(await first, isTrue);
      expect(api.sentBodies, ['One']);
    });

    test('the send stays in progress until the sent message is on screen', () async {
      final api = FakeChatGroupsApi();
      final ctrl = await openConversation(api);

      final gate = Completer<void>();
      api.messagesGate = gate;
      final sending = ctrl.send('Thank you');
      await _settle(); // stored on the server; the refresh is held at the gate

      expect(api.sentBodies, ['Thank you']);
      expect(ctrl.isSending.value, isTrue);

      api.messagesGate = null;
      gate.complete();
      expect(await sending, isTrue);
      expect(ctrl.isSending.value, isFalse);
      expect(ctrl.messages.last.body, 'Thank you');
    });
  });

  test('a stored message counts as sent even when the refresh after it fails', () async {
    final api = FakeChatGroupsApi();
    final ctrl = await openConversation(api);

    api.messagesError = Exception('Request timed out.');
    final sent = await ctrl.send('Thank you');

    expect(sent, isTrue);
    expect(api.sentBodies, ['Thank you']);
    expect(ctrl.sendError.value, isNull);
  });
}
