// Pins that marking a chat group read actually moves the member's read cursor.
//
// THE BUG
// POST /api/chat-groups/:id/read binds {"last_read_msg_id": N} and stores
// GREATEST(existing, N) (backend handlers/chat_group.go and
// chatgroups/chatgroups_reads.go); a group's unread count is every message
// with an id above that cursor. The client shipped in PR #81 posted `{}`. The
// field is not required, so the server bound it as 0, kept the old cursor and
// still answered success — the unread badge on every group could never clear,
// and nothing anywhere reported a failure.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';

void main() {
  setUp(() async {
    // postJson attaches the session from the sharedPreferences global.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  test('marking a group read sends the newest message id the member saw', () async {
    http.Request? sent;
    final api = ModuleApi(
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.markChatGroupRead(7, lastReadMessageId: 42);

    expect(sent, isNotNull, reason: 'no request reached the server');
    expect(sent!.method, 'POST');
    expect(sent!.url.path, endsWith('/chat-groups/7/read'));
    expect(
      jsonDecode(sent!.body),
      {'last_read_msg_id': 42},
      reason:
          'without last_read_msg_id the server records 0 and the unread '
          'count never goes down',
    );
  });
}
