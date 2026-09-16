// Pins that a refused chat-group send keeps the reason the server named.
//
// WHY
// POST /api/chat-groups/:id/messages refuses two things by name: contact
// details in a supervised chat (422, code `contact_details_blocked`) and a chat
// staff have paused or ended (409, code `chat_lifecycle_closed`). Retrying
// cannot fix either, so ChatGroupConversationController explains them instead
// of saying "try again" — but only if the API layer hands it the code.
// `postJson` throws a bare Exception carrying the server's English sentence
// and drops the code; `_sendCodedJson` keeps it as an ApiCodedException.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';

/// A ModuleApi whose every request is answered with [status] and [body].
ModuleApi _apiAnswering(int status, Map<String, Object?> body) => ModuleApi(
  httpClient: MockClient(
    (_) async => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    ),
  ),
);

void main() {
  setUp(() async {
    // Writes attach the session from the sharedPreferences global.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  test('contact details refused with a 422 keep their code', () async {
    final api = _apiAnswering(422, {
      'success': false,
      'code': 'contact_details_blocked',
      'error': 'Phone numbers cannot be shared in this chat.',
    });

    await expectLater(
      api.sendChatGroupMessage(7, 'Call me on 07701234567'),
      throwsA(
        isA<ApiCodedException>().having(
          (e) => e.code,
          'code',
          'contact_details_blocked',
        ),
      ),
    );
  });

  test('a closed chat refused with a 409 keeps its code', () async {
    final api = _apiAnswering(409, {
      'success': false,
      'code': 'chat_lifecycle_closed',
      'lifecycle': 'ended',
      'lifecycle_reason': '',
      'error': 'This conversation has been closed by our team.',
    });

    await expectLater(
      api.sendChatGroupMessage(7, 'Thank you'),
      throwsA(
        isA<ApiCodedException>().having(
          (e) => e.code,
          'code',
          'chat_lifecycle_closed',
        ),
      ),
    );
  });

  test('a stored message returns the server response', () async {
    final api = _apiAnswering(200, {'success': true, 'message_id': 13});

    final response = await api.sendChatGroupMessage(7, 'Thank you');

    expect(response['message_id'], 13);
  });
}
