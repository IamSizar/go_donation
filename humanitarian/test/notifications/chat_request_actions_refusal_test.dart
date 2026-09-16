// Pins how a chat_request notification's inline Accept / Decline answers a
// refusal, and that it stops offering Accept on a closed thread (OPOS #26433).
//
// WHY THIS FILE EXISTS
// ChatRequestActions showed a failed accept as `SnackBar(Text('$e'))`, the raw
// "Exception: This chat request was declined, ..." in English on every
// locale, and a failed decline only re-enabled the buttons with no message.
// This tile is also where an active chat most often gets declined: it shows
// Decline whenever the thread is not in ChatController's loaded list.
//
// WHAT IS PINNED
//   1. A decline refused because the chat is already active says so, and the
//      buttons are not silently re-enabled.
//   2. A failed accept never shows raw exception text; it shows a human line.
//   3. An accept refused as closed shows the closed copy, removes Accept and
//      keeps Decline.
//   4. An accept refused as declined says so, in Arabic for an Arabic reader.
//   5. A thread the list reports as ended offers no Accept.
//
// HARNESS NOTES (as in chat_request_tile_guest_test.dart)
//   * HTTP goes through FakeHttpOverrides with a per-request `respond`.
//   * Every test unmounts the tile, then deletes ChatController, which cancels
//     its 5-second poll.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/notifications/widgets/chat_request_actions.dart';

import '../support/fake_http.dart';

// ─── Fixtures ───

const _english = Locale('en', 'US');
const _arabic = Locale('ar', 'SA');
const _threadId = 42;

const _emptyList = '{"success": true, "items": []}';

/// The chats list with thread [_threadId] pending in [lifecycle].
String _listWith(String lifecycle) =>
    '{"success": true, "items": [{"id": $_threadId, "status": "pending", '
    '"incoming_pending": true, "my_role": "owner", "other_user_id": 3, '
    '"other_name": "Donor", "lifecycle": "$lifecycle"}]}';

/// Routes a POST to [write]; the chats list answers [list].
FakeHttpOverrides _http({FakeHttpAnswer? write, String list = _emptyList}) =>
    FakeHttpOverrides(
      HttpBehaviour.ok,
      respond: (method, url) {
        if (method.toUpperCase() == 'POST' && write != null) return write;
        return FakeHttpAnswer(200, list);
      },
    );

// ─── Helpers ───

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpTile(WidgetTester tester, {Locale locale = _english}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.locale = locale;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: _english,
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: ChatRequestActions(threadId: _threadId),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _unmountAndStopPolling(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  if (Get.isRegistered<ChatController>()) {
    Get.delete<ChatController>(force: true);
  }
  await tester.pump();
}

bool _textShown(String text) => find.textContaining(text).evaluate().isNotEmpty;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'id_user': '7', 'role_id': '1'});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('a decline refused because the chat is already active says so '
      'and does not leave the buttons silently re-enabled', (tester) async {
    final http = _http(
      write: const FakeHttpAnswer(
        409,
        '{"success": false, '
        '"error": "This chat is already active, so it can no longer be declined."}',
      ),
    );
    var shown = false;
    var declineButtons = -1;
    await withHttp(http, () async {
      await _pumpTile(tester);
      await tester.tap(find.byType(OutlinedButton));
      await _settle(tester);
      shown = _textShown('This chat is already active');
      declineButtons = find.byType(OutlinedButton).evaluate().length;
      await _unmountAndStopPolling(tester);
    });

    expect(
      http.requestSignatures,
      contains('POST /api/chats/$_threadId/decline'),
    );
    expect(shown, isTrue);
    expect(declineButtons, 0, reason: 'an active chat cannot be declined');
  });

  testWidgets('a failed accept never shows raw exception text', (tester) async {
    final http = _http(
      write: const FakeHttpAnswer(
        500,
        '{"success": false, "error": "Database error."}',
      ),
    );
    var raw = true;
    var human = false;
    await withHttp(http, () async {
      await _pumpTile(tester);
      await tester.tap(find.byType(FilledButton));
      await _settle(tester);
      raw = _textShown('Exception') || _textShown('Database error.');
      human = _textShown('Could not accept this chat request.');
      await _unmountAndStopPolling(tester);
    });

    expect(raw, isFalse);
    expect(human, isTrue);
  });

  testWidgets('an accept refused as closed shows the closed copy, '
      'removes Accept and keeps Decline', (tester) async {
    final http = _http(
      write: const FakeHttpAnswer(
        409,
        '{"success": false, "code": "chat_lifecycle_closed", '
        '"lifecycle": "paused", "lifecycle_reason": "", '
        '"error": "This conversation has been paused by staff."}',
      ),
    );
    var shown = false;
    var accepts = -1;
    var declines = -1;
    await withHttp(http, () async {
      await _pumpTile(tester);
      await tester.tap(find.byType(FilledButton));
      await _settle(tester);
      shown = _textShown('This conversation has been paused by our team.');
      accepts = find.byType(FilledButton).evaluate().length;
      declines = find.byType(OutlinedButton).evaluate().length;
      await _unmountAndStopPolling(tester);
    });

    expect(shown, isTrue);
    expect(accepts, 0);
    expect(declines, 1);
  });

  testWidgets('in Arabic, an accept refused as declined says so in Arabic', (
    tester,
  ) async {
    final http = _http(
      write: const FakeHttpAnswer(
        409,
        '{"success": false, "code": "chat_invite_declined", '
        '"error": "This chat request was declined, so it can no longer be accepted."}',
      ),
    );
    var shown = false;
    var english = true;
    await withHttp(http, () async {
      await _pumpTile(tester, locale: _arabic);
      await tester.tap(find.byType(FilledButton));
      await _settle(tester);
      shown = _textShown('لقد رفضتَ هذه الدعوة.');
      english = _textShown('declined');
      await _unmountAndStopPolling(tester);
    });

    expect(shown, isTrue);
    expect(english, isFalse);
  });

  testWidgets('a thread the list reports as ended offers no Accept', (
    tester,
  ) async {
    final http = _http(list: _listWith('ended'));
    var accepts = -1;
    var declines = -1;
    await withHttp(http, () async {
      await _pumpTile(tester);
      accepts = find.byType(FilledButton).evaluate().length;
      declines = find.byType(OutlinedButton).evaluate().length;
      await _unmountAndStopPolling(tester);
    });

    expect(accepts, 0);
    expect(declines, 1);
  });
}
