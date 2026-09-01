// Pins that Messages offers BOTH a route to a human (live chat) and a route
// to a tracked request (the support form), as standing entries — not one
// gated behind the other's failure.
//
// WHY THIS FILE EXISTS
// `_SupportChatUnavailableNotice` already sends the user to
// `TechnicalSupportScreen`, but only when `supportChatUnavailable` is true —
// which in production is the common case, since no support staff account is
// configured and the chat endpoint returns 503. Before this change, a user
// whose chat WAS working had no way to reach the ticket form at all: it only
// appeared behind a failure they might never hit organically. The fix adds a
// second, permanent SectionTile beneath `chat_support` so the form is always
// one tap away, independent of chat's health.
//
// WHY A SOURCE TEST
// `MessagesScreen` stands up a live `ChatController`/`ModuleApi` against a
// real network on build (see support_chat_screen_state_test.dart, which tests
// the notifier logic rather than pumping the full screen for exactly this
// reason). The question this test answers — "does the screen's source wire up
// both doors, distinctly" — is a property of the source, matching the
// pattern in partners_doors_test.dart and profile_menu_doors_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _messagesScreenPath =
    'lib/modules/chat/screens/messages_screen.dart';

String _readMessagesScreen() {
  final file = File(_messagesScreenPath);
  if (!file.existsSync()) {
    fail('$_messagesScreenPath is missing — this test needs updating');
  }
  return file.readAsStringSync();
}

void main() {
  group('Messages offers both a chat door and a form door', () {
    test('a standing SectionTile opens live support chat', () {
      final source = _readMessagesScreen();

      expect(
        source.contains("title: 'chat_support'.tr") &&
            source.contains('onTap: () => openSupportChat(context)'),
        isTrue,
        reason:
            'the live-chat tile (a human, in real time) must stay a standing '
            'entry, not only reachable via the unavailable-notice fallback',
      );
    });

    test('a standing SectionTile opens the support request form', () {
      final source = _readMessagesScreen();

      expect(
        source.contains("title: 'support_request_form'.tr"),
        isTrue,
        reason:
            'the ticket form needs a permanent door too — today the only '
            'other reachable door is _SupportChatUnavailableNotice, which is '
            'gated behind chat being misconfigured',
      );
      final titleIndex = source.indexOf("support_request_form'.tr");
      final nearbyWindow = titleIndex == -1
          ? ''
          : source.substring(
              titleIndex,
              (titleIndex + 300).clamp(0, source.length),
            );
      expect(
        nearbyWindow.contains('TechnicalSupportScreen'),
        isTrue,
        reason:
            'the new tile must actually navigate to TechnicalSupportScreen, '
            'the ticket-form screen with history — not just carry the title',
      );
    });

    test('the two tiles use distinct icons and copy keys', () {
      final source = _readMessagesScreen();

      expect(
        source.contains('Icons.support_agent_rounded'),
        isTrue,
        reason: 'chat_support keeps its existing icon',
      );
      expect(
        source.contains('Icons.contact_support_outlined'),
        isTrue,
        reason:
            'the form tile uses a distinct icon so the two read as different '
            'things at a glance: one is a live conversation, the other files '
            'a tracked request',
      );
      expect(
        source.contains("'support_request_form_desc'.tr"),
        isTrue,
        reason: 'the form tile needs its own subtitle, not chat_support_desc',
      );
    });

    test('the unavailable notice is still present', () {
      // The brief is explicit: do not remove it. It stays as the guidance
      // shown specifically when chat is misconfigured.
      //
      // It lost its leading underscore when the events section's support door
      // was given the same three-way handling: both doors hit the same
      // endpoint and get the same 503, so they now share one notice, and a
      // private class cannot be shared. The requirement is untouched — this
      // screen must still show it.
      final source = _readMessagesScreen();
      expect(source.contains('SupportChatUnavailableNotice'), isTrue);
    });
  });
}
