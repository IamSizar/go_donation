// Pins how the marriage chat screen answers a refused Accept or Decline, and
// that it stops offering Accept on a thread staff closed (OPOS #26433).
//
// WHY THIS FILE EXISTS
// The screen posted accept and decline through ModuleApi.postJson, which
// throws only the server's English sentence and drops its `code`. Every refusal
// therefore showed the send-failure line ("Could not send your message."),
// which is false: nothing was being sent. And Accept stayed on screen on a
// paused or ended thread, although the server refuses that accept with
// 409 `chat_lifecycle_closed` and the lifecycle notice already replaced the
// composer below it.
//
// WHAT IS PINNED
//   1. A pending invite on an ENDED thread offers no Accept, and still offers
//      Decline, the one way to dismiss it (the server allows that decline).
//   2. An accept refused with `chat_lifecycle_closed` shows "closed by our
//      team" plus staff's reason, never the send-failure line, and Accept goes.
//   3. An accept refused with `chat_invite_declined` says the user declined it,
//      in English and in Arabic.
//   4. A decline refused because the chat is already active says so.
//   5. An open invite still accepts: the POST goes out and the screen reloads.
//
// HARNESS NOTES
//   * HTTP goes through FakeHttpOverrides with a per-request `respond`, so the
//     messages GET and the accept/decline POST answer differently.
//   * Every test unmounts the screen before returning, which cancels its
//     3-second poll and any SnackBar timer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_chat_conversation_screen.dart';

import '../../support/fake_http.dart';

// ─── Fixtures ───

const _english = Locale('en', 'US');
const _arabic = Locale('ar', 'SA');
const _threadId = 31;

/// The messages load for the thread: pending, in [lifecycle].
String _messages({String status = 'pending', String lifecycle = 'open'}) =>
    '{"success": true, "items": [], "status": "$status", '
    '"lifecycle": "$lifecycle", "lifecycle_reason": "Reviewed by staff"}';

/// Routes the accept/decline POST to [write]; everything else is the load.
FakeHttpOverrides _http({
  required FakeHttpAnswer write,
  String status = 'pending',
  String lifecycle = 'open',
}) => FakeHttpOverrides(
  HttpBehaviour.ok,
  respond: (method, url) {
    final path = url.path;
    if (method.toUpperCase() == 'POST' &&
        (path.endsWith('/accept') || path.endsWith('/decline'))) {
      return write;
    }
    return FakeHttpAnswer(200, _messages(status: status, lifecycle: lifecycle));
  },
);

const _closedRefusal = FakeHttpAnswer(
  409,
  '{"success": false, "code": "chat_lifecycle_closed", "lifecycle": "ended", '
  '"lifecycle_reason": "Reviewed by staff", '
  '"error": "This conversation has been ended by staff."}',
);

const _declinedRefusal = FakeHttpAnswer(
  409,
  '{"success": false, "code": "chat_invite_declined", '
  '"error": "This chat request was declined, so it can no longer be accepted."}',
);

const _alreadyActiveRefusal = FakeHttpAnswer(
  409,
  '{"success": false, '
  '"error": "This chat is already active, so it can no longer be declined."}',
);

// ─── Helpers ───

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  Locale locale = _english,
}) async {
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
      home: const MarriageChatConversationScreen(
        threadId: _threadId,
        otherLabel: 'Interested member',
        myRole: 'owner',
        initialStatus: 'pending',
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Finder _acceptButton() => find.widgetWithText(ElevatedButton, 'Accept'.tr);
Finder _declineButton() => find.widgetWithText(OutlinedButton, 'Decline'.tr);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'id_user': '7', 'role_id': '1'});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  testWidgets('a pending invite on an ended thread offers no Accept, '
      'but still offers Decline', (tester) async {
    final http = _http(write: _closedRefusal, lifecycle: 'ended');
    var accepts = -1;
    var declines = -1;
    await withHttp(http, () async {
      await _pumpScreen(tester);
      accepts = _acceptButton().evaluate().length;
      declines = _declineButton().evaluate().length;
      await _unmount(tester);
    });

    expect(accepts, 0, reason: 'the server refuses accept on a closed thread');
    expect(declines, 1, reason: 'decline is how a dead invite is dismissed');
  });

  testWidgets('an accept refused as closed shows the closed-by-our-team copy '
      'and the reason, not the send-failure line, and Accept goes', (
    tester,
  ) async {
    final http = _http(write: _closedRefusal);
    var closedShown = false;
    var reasonShown = false;
    var sendCopyShown = true;
    var acceptsAfter = -1;
    await withHttp(http, () async {
      await _pumpScreen(tester);
      await tester.tap(_acceptButton());
      await _settle(tester);
      closedShown = find
          .textContaining('This conversation has been closed by our team.')
          .evaluate()
          .isNotEmpty;
      reasonShown = find
          .textContaining('Reviewed by staff')
          .evaluate()
          .isNotEmpty;
      sendCopyShown = find
          .textContaining('Could not send your message.')
          .evaluate()
          .isNotEmpty;
      acceptsAfter = _acceptButton().evaluate().length;
      await _unmount(tester);
    });

    expect(
      http.requestSignatures,
      contains('POST /api/marriage/chats/$_threadId/accept'),
    );
    expect(closedShown, isTrue);
    expect(reasonShown, isTrue);
    expect(sendCopyShown, isFalse);
    expect(
      acceptsAfter,
      0,
      reason: 'a refused accept must not be offered again',
    );
  });

  testWidgets('an accept refused as already declined says so', (tester) async {
    final http = _http(write: _declinedRefusal);
    var shown = false;
    await withHttp(http, () async {
      await _pumpScreen(tester);
      await tester.tap(_acceptButton());
      await _settle(tester);
      shown = find
          .textContaining('You declined this invitation.')
          .evaluate()
          .isNotEmpty;
      await _unmount(tester);
    });

    expect(shown, isTrue);
  });

  testWidgets('in Arabic, an accept refused as already declined says so '
      'in Arabic', (tester) async {
    final http = _http(write: _declinedRefusal);
    var shown = false;
    await withHttp(http, () async {
      await _pumpScreen(tester, locale: _arabic);
      await tester.tap(find.widgetWithText(ElevatedButton, 'قبول'));
      await _settle(tester);
      shown = find
          .textContaining('لقد رفضتَ هذه الدعوة.')
          .evaluate()
          .isNotEmpty;
      await _unmount(tester);
    });

    expect(shown, isTrue);
  });

  testWidgets('a decline refused because the chat is already active says so', (
    tester,
  ) async {
    final http = _http(write: _alreadyActiveRefusal);
    var shown = false;
    await withHttp(http, () async {
      await _pumpScreen(tester);
      await tester.tap(_declineButton());
      await _settle(tester);
      shown = find
          .textContaining('This chat is already active')
          .evaluate()
          .isNotEmpty;
      await _unmount(tester);
    });

    expect(shown, isTrue);
  });

  testWidgets('an open invite still accepts and the screen reloads', (
    tester,
  ) async {
    final http = _http(
      write: const FakeHttpAnswer(
        200,
        '{"success": true, "thread_id": 31, "status": "active"}',
      ),
    );
    var loadsBefore = 0;
    var loadsAfter = 0;
    await withHttp(http, () async {
      await _pumpScreen(tester);
      loadsBefore = http.requestSignatures
          .where((s) => s.startsWith('GET '))
          .length;
      await tester.tap(_acceptButton());
      await _settle(tester);
      loadsAfter = http.requestSignatures
          .where((s) => s.startsWith('GET '))
          .length;
      await _unmount(tester);
    });

    expect(
      http.requestSignatures,
      contains('POST /api/marriage/chats/$_threadId/accept'),
    );
    expect(loadsAfter, greaterThan(loadsBefore));
  });
}
