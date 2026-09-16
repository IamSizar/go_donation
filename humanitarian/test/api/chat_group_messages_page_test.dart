// Pins the paging a chat-group transcript request asks for.
//
// WHY
// GET /api/chat-groups/:id/messages returns only messages with an id above
// `after_id`, oldest first, at most `limit` of them (default 50, maximum 100)
// — backend chatgroups/chatgroups_reads.go ListMessagesForMember. The first
// client asked with neither parameter, so it only ever received the first 50
// messages of a group: message 51 and everything after it never appeared.
// The controller now pages through the history and polls from the newest id
// it has; this pins that the request really carries those two numbers.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';

void main() {
  setUp(() async {
    // GETs attach the session from the sharedPreferences global.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  test('a transcript page request names where to start and how many', () async {
    Uri? requested;
    final api = ModuleApi(
      httpClient: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'success': true,
            'items': <Object>[],
            'lifecycle': 'open',
            'lifecycle_reason': '',
            'is_archived': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.chatGroupMessages(7, afterId: 120, limit: 100);

    expect(requested, isNotNull, reason: 'no request reached the server');
    expect(requested!.path, endsWith('/chat-groups/7/messages'));
    expect(requested!.queryParameters['after_id'], '120');
    expect(requested!.queryParameters['limit'], '100');
  });
}
