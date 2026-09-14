// Pins where the chat-groups block is wired into the Messages tab, OPOS
// #25284 Phase 5 Task 4.
//
// WHY A SOURCE TEST
// MessagesScreen builds a live ChatController against the real network, so it
// is not pumped in tests (see messages_support_doors_test.dart, which answers
// its own wiring questions the same way). What this pins is a property of the
// source: the block exists, comes AFTER the 1:1 threads — so a failure in it
// can never push the bot and support doors off the top of the tab — and is
// never built for a guest, who cannot message (the server's chat-group POST
// routes all carry auth.RequireNotGuest).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _messagesScreenPath = 'lib/modules/chat/screens/messages_screen.dart';

void main() {
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
}
