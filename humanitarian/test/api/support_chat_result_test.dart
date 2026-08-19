// Pins that the three ways POST /chats/support can answer stay three
// DIFFERENT things to the app.
//
// THE BUG
// The call returned `int?`. "Opened", "no support account is configured" and
// "the network dropped" therefore had two states between them, so the screen
// showed the same retryable error for all of them. For the configuration case
// that Retry button could never work: the server answers 503 and keeps
// answering 503 until a staff account is nominated in the dashboard. A user
// pressing it repeatedly is being told the fault is theirs.
//
// This was live in production — SUPPORT_USER_ID unset, no app_settings row —
// and it is why «التواصل مع الدعم» appeared to do nothing at all.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/support_chat_result.dart';

/// A ModuleApi whose every request gets [respond].
ModuleApi _api(http.Response Function(http.Request request) respond) =>
    ModuleApi(httpClient: MockClient((request) async => respond(request)));

void main() {
  test('a 503 is UNAVAILABLE, not a retryable failure', () async {
    // The exact production shape: the server names the cause in English.
    final api = _api(
      (_) => http.Response(
        jsonEncode({
          'success': false,
          'error': 'Support chat is not configured.',
        }),
        503,
        headers: {'content-type': 'application/json'},
      ),
    );

    final result = await api.openSupportThread();

    expect(
      result,
      isA<SupportChatUnavailable>(),
      reason:
          'a 503 means no support account is configured. Classifying it as a '
          'failure puts a Retry button on a condition no retry can change.',
    );
  });

  test('a 200 with a thread id is OPENED, carrying the id', () async {
    final api = _api(
      (_) => http.Response(
        jsonEncode({'success': true, 'thread_id': 4321, 'status': 'pending'}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    final result = await api.openSupportThread();

    expect(result, isA<SupportChatOpened>());
    expect((result as SupportChatOpened).threadId, 4321);
  });

  test('a 200 with NO thread id is a failure, not a silent success', () async {
    // The original defect in this call: it returned null here and the screen
    // returned early without a word, which is what "the button does nothing"
    // actually looked like.
    final api = _api(
      (_) => http.Response(
        jsonEncode({'success': true}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    expect(await api.openSupportThread(), isA<SupportChatFailed>());
  });

  test('a 500 is a retryable failure, NOT unavailable', () async {
    // The distinction matters in both directions: treating a server error as
    // "not configured" would send the user off to another screen when simply
    // trying again would have worked.
    final api = _api(
      (_) => http.Response(
        jsonEncode({'success': false, 'error': 'Database error'}),
        500,
        headers: {'content-type': 'application/json'},
      ),
    );

    final result = await api.openSupportThread();

    expect(result, isA<SupportChatFailed>());
    expect(
      (result as SupportChatFailed).detail,
      contains('500'),
      reason: 'the log needs the status to be diagnosable',
    );
  });

  test('a dropped connection is a retryable failure', () async {
    final api = _api((_) => throw http.ClientException('Connection closed'));

    expect(await api.openSupportThread(), isA<SupportChatFailed>());
  });

  test('an HTML error page does not crash the call', () async {
    // A proxy in front of the API answers with HTML, which the JSON decode
    // throws on. That must become a failure, not an unhandled exception on the
    // one screen a user opens BECAUSE something is already wrong.
    final api = _api(
      (_) => http.Response(
        '<html><body>502 Bad Gateway</body></html>',
        502,
        headers: {'content-type': 'text/html'},
      ),
    );

    expect(await api.openSupportThread(), isA<SupportChatFailed>());
  });

  test('the server sentence never becomes the user-facing text', () async {
    // The English sentence is for the log. It reached an Arabic screen once
    // already; the type keeps it in a field named for developers.
    final api = _api(
      (_) => http.Response(
        jsonEncode({'success': false, 'error': 'Support chat is not configured.'}),
        503,
        headers: {'content-type': 'application/json'},
      ),
    );

    final result = await api.openSupportThread();

    // SupportChatUnavailable carries NO message at all, which is the point:
    // there is nothing for a caller to accidentally render.
    expect(result, isA<SupportChatUnavailable>());
  });
}
