// Pins what the MESSAGES SCREEN does with each outcome — the two failures must
// not look the same to the user.
//
// The API-level classification is covered in support_chat_result_test.dart.
// This is the half that matters on screen: an unconfigured support chat must
// NOT raise the retryable error banner, because that banner's Retry button
// cannot work, and a genuine failure must NOT raise the "use another channel"
// notice, because trying again is exactly what would fix it.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';

ModuleApi _api(http.Response Function() respond) =>
    ModuleApi(httpClient: MockClient((_) async => respond()));

http.Response _json(Object body, int code) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);

void main() {
  setUp(() {
    supportChatError.value = null;
    supportChatUnavailable.value = false;
  });

  testWidgets('an unconfigured support chat raises the NOTICE, not the error', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );

    await openSupportChat(
      ctx,
      api: _api(
        () => _json({
          'success': false,
          'error': 'Support chat is not configured.',
        }, 503),
      ),
    );

    expect(
      supportChatUnavailable.value,
      isTrue,
      reason: 'the user should be offered the channels that work',
    );
    expect(
      supportChatError.value,
      isNull,
      reason:
          'raising the error banner too would put a Retry button on screen '
          'for a condition that no retry can change',
    );
  });

  testWidgets('a server failure raises the retryable ERROR, not the notice', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );

    await openSupportChat(
      ctx,
      api: _api(
        () => _json({'success': false, 'error': 'Database error'}, 500),
      ),
    );

    expect(
      supportChatError.value,
      'chat_support_failed',
      reason: 'a 500 is worth retrying, so it keeps the Retry affordance',
    );
    expect(
      supportChatUnavailable.value,
      isFalse,
      reason:
          'sending the user to another screen would be wrong here — trying '
          'again is what fixes a transient server error',
    );
  });

  testWidgets('a fresh attempt clears the previous outcome', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );

    // Fail first, so there is stale state to clear.
    await openSupportChat(ctx, api: _api(() => _json({'success': false}, 503)));
    expect(supportChatUnavailable.value, isTrue);

    // Then a different failure. The notice from the first attempt must not
    // still be sitting on screen beside the second attempt's error.
    await openSupportChat(
      ctx,
      api: _api(() => _json({'success': false, 'error': 'boom'}, 500)),
    );

    expect(supportChatUnavailable.value, isFalse);
    expect(supportChatError.value, 'chat_support_failed');
  });
}
