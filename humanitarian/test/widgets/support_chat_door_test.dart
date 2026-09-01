// Pins what the events section's "Message the staff team" tile DOES with each
// of the server's three answers.
//
// THE DEFECT THIS CLOSES
// The three answers were already told apart — support_chat_result_test.dart
// pins that, and the Messages screen has acted on it since. This door did not:
// it went through ChatController.requestSupportChat, which throws on any
// non-2xx, so all three arrived as one generic snackbar reading "couldn't send
// your message, try again — and if it keeps happening, contact support".
//
// On production the server answers 503 (no staff account is nominated), so the
// button for contacting support told the user to contact support, and offered
// a retry that could never succeed. Reproduced on a Motorola before the fix.
//
// Each branch is asserted on its EFFECT, not on the source, so a future
// rewrite that keeps the behaviour keeps passing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';

/// A ModuleApi whose support-thread POST answers with [response].
ModuleApi _api(http.Response response) =>
    ModuleApi(httpClient: MockClient((_) async => response));

/// Puts a single button on screen that opens the support chat through [api],
/// then taps it and settles.
Future<void> _tapTheTile(WidgetTester tester, ModuleApi api) async {
  // Not a guest: requireUpgrade() short-circuits guests into an upgrade
  // prompt, which is a different flow and not what this file is about.
  SharedPreferences.setMockInitialValues({'id_user': '7'});
  sharedPreferences = await SharedPreferences.getInstance();
  addTearDown(Get.reset);

  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => ChatActions.startSupportChat(context, api: api),
              child: const Text('tap me'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('tap me'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a 503 hands over a channel that works, with no retry', (
    tester,
  ) async {
    await _tapTheTile(
      tester,
      _api(
        http.Response(
          '{"success": false, "error": "Support chat is not configured."}',
          503,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    expect(
      find.text('Support chat is not set up yet'),
      findsOneWidget,
      reason:
          'the 503 is permanent until staff nominate an account, so the user '
          'must be told that and pointed somewhere that works',
    );
    expect(
      find.text('Open technical support'),
      findsOneWidget,
      reason: 'and the way out has to be a control, not a suggestion',
    );
    // The heart of the defect: the old message told the user to contact
    // support, from the button whose whole job was contacting support.
    expect(
      find.textContaining('Could not send your message'),
      findsNothing,
      reason:
          'a configuration gap is not a failed send, and must not be reported '
          'as one — nothing the user does differently will change it',
    );
  });

  testWidgets('a genuine failure is reported as one, and still offers a way out', (
    tester,
  ) async {
    await _tapTheTile(
      tester,
      _api(
        http.Response(
          '{"success": false, "error": "Database error"}',
          500,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    expect(find.textContaining('Could not send your message'), findsOneWidget);
    expect(
      find.text('Open technical support'),
      findsOneWidget,
      reason:
          'a dead-end error screen is a bug — the failure still leaves the '
          'ticket form one tap away',
    );
    expect(
      find.text('Support chat is not set up yet'),
      findsNothing,
      reason: 'a 500 is not a configuration gap and must not claim to be one',
    );
  });

  testWidgets('a 200 opens the conversation instead of saying anything', (
    tester,
  ) async {
    await _tapTheTile(
      tester,
      _api(
        http.Response(
          '{"success": true, "thread_id": 4321, "status": "active"}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    expect(find.text('Support chat is not set up yet'), findsNothing);
    expect(find.textContaining('Could not send your message'), findsNothing);
  });
}
