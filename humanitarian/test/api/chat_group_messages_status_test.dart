// Pins that a refused chat-group transcript request tells its caller WHICH
// status the server answered with.
//
// WHY
// Staff can delete a chat group (chatlifecycle moves it to trash), archive it,
// or remove a member from it. The member's app can still open that
// conversation — from My Connect Requests or a stale tile — and
// GET /api/chat-groups/:id/messages then answers 404 (group gone or archived)
// or 403 (no longer a member), with an English sentence and no machine code
// (backend handlers/chat_group.go Messages, chat_lifecycle_gate.go).
//
// `getObject` used to throw `Exception('Request failed (404)')` for every
// non-2xx, so the conversation screen could not tell "gone for good" from
// "try again" and offered a Retry that could never succeed. The status now
// travels as a number on ApiStatusException — never parsed back out of a
// message, which is the pattern this codebase rejects (see history_api.dart).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/api_status_exception.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';

/// A ModuleApi whose every request is answered with [status] and [body].
ModuleApi _apiAnswering(int status, Map<String, Object?> body) => ModuleApi(
  httpClient: MockClient(
    (request) async => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    ),
  ),
);

void main() {
  setUp(() async {
    // GETs attach the session from the sharedPreferences global.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  test(
    'a refused transcript request carries the status the server sent',
    () async {
      // 404: the group was deleted or archived. 403: the member was removed.
      const refusals = {
        404: 'Group not found.',
        403: 'You are not a member of this group.',
      };
      for (final MapEntry(key: status, value: sentence) in refusals.entries) {
        final api = _apiAnswering(status, {
          'success': false,
          'error': sentence,
        });

        await expectLater(
          api.chatGroupMessages(7),
          throwsA(
            isA<ApiStatusException>().having(
              (e) => e.statusCode,
              'statusCode',
              status,
            ),
          ),
          reason: 'a $status must reach the caller as a number it can act on',
        );
      }
    },
  );

  test('the exception still prints exactly as the plain Exception did', () {
    // Logs, debugPrints and crash reports keep reading the same line.
    expect(
      const ApiStatusException(404).toString(),
      'Exception: Request failed (404)',
    );
  });

  test('a successful transcript request still returns the body', () async {
    final api = _apiAnswering(200, {
      'success': true,
      'items': <Object>[],
      'lifecycle': 'open',
      'lifecycle_reason': '',
      'is_archived': false,
    });

    final body = await api.chatGroupMessages(7);

    expect(body['success'], isTrue);
    expect(body['items'], isEmpty);
    expect(body['lifecycle'], 'open');
  });
}
