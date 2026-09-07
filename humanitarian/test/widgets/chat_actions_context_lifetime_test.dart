// Pins that starting a donor ↔ owner chat actually SENDS the request, and that
// it is the caller's context lifetime that decides whether it does.
//
// THE BUG (OPOS 24399)
// "Chat with campaign owner" — the only way to open item 1 of the client's
// messaging list from the app — did nothing at all. The confirm dialog
// appeared, the user accepted, and no request ever reached the server. Run
// twice against the deployed dev backend, GET /api/admin/chats stayed at three
// threads; the app's own Messages screen stayed on «لا محادثات بعد».
//
// The detail sheet closed itself and then handed its OWN context on:
//
//     Navigator.of(context).pop();          // unmounts this element
//     await ChatActions.startChat(context,  // ...and then uses it
//
// startChat awaits the confirm dialog and then re-checks `context.mounted`.
// That guard is correct — a dead context can host neither a dialog nor a
// snackbar — but by then the sheet's element was defunct, so the guard fired
// and the flow was abandoned one line BEFORE the POST.
//
// Nothing showed because startChat reports through ScaffoldMessenger, and this
// app has already established that snackbars do not paint on these routes (see
// the note on `supportChatError` in chat/screens/messages_screen.dart). A
// silent abort behind an invisible error reads as "the button is dead".
//
// WHY THE TEST IS SHAPED LIKE THIS
// The two widgets involved are private, so this pins the contract they depend
// on rather than the widgets themselves: given a context that outlived the
// route it closed, the request goes out; given one that did not, it does not.
// The first case is the fix, and it is the one that fails against the old
// code. Asserting only the second would pass against the bug.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';

/// Records whether the request was issued, without a network. Only the one
/// method is overridden; everything else is the real controller.
class _RecordingChatController extends ChatController {
  int requests = 0;

  // Skips ChatController.onInit deliberately: it fires fetchThreads() and
  // starts a 5s Timer.periodic, so a widget test would hit the network and
  // then fail on teardown with a pending timer. super.onInit() is not called
  // for the same reason — there is nothing here that needs disposing.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<({int threadId, String status, bool already})> requestChat({
    int? donationId,
    int? donorUserId,
    int? campaignId,
  }) async {
    requests++;
    return (threadId: 99, status: 'pending', already: false);
  }
}

void main() {
  late _RecordingChatController chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'id_user': '58', 'role_id': '1'});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
    chat = _RecordingChatController();
    Get.put<ChatController>(chat);
  });

  tearDown(Get.reset);

  /// Taps "Yes, start chat" on the confirm dialog startChat puts up.
  Future<void> confirm(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final yes = find.text('Yes, start chat');
    expect(
      yes,
      findsOneWidget,
      reason: 'the confirm dialog must be on screen before it can be accepted',
    );
    await tester.tap(yes);
    await tester.pumpAndSettle();
  }

  testWidgets('a context that outlives the closed sheet sends the request', (
    tester,
  ) async {
    late BuildContext hostContext;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // The shape of the fix: a sheet is opened and closed, and the flow then
    // continues on the HOST's context, which is still on screen.
    // NOT awaited — the sheet's future only completes once it is popped, and
    // popping needs pumps, so awaiting it here would deadlock the test.
    late BuildContext sheetContext;
    unawaited(
      showModalBottomSheet<void>(
        context: hostContext,
        builder: (context) {
          sheetContext = context;
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();
    expect(
      hostContext.mounted,
      isTrue,
      reason: 'the host outlives the sheet — that is the point of the fix',
    );

    final started = ChatActions.startChat(
      hostContext,
      donationId: 22,
      otherPartyLabel: 'the owner',
    );
    await confirm(tester);
    await started;

    expect(
      chat.requests,
      1,
      reason:
          'this is the whole feature: accepting the dialog must post the chat '
          'request. Against the old code the sheet handed over its own dead '
          'context and this stayed at 0 — silently.',
    );
  });

  testWidgets('a context belonging to a closed route sends nothing', (
    tester,
  ) async {
    late BuildContext hostContext;

    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // The shape of the BUG: capture the sheet's own context, pop the sheet,
    // then try to drive the flow from it.
    late BuildContext deadContext;
    unawaited(
      showModalBottomSheet<void>(
        context: hostContext,
        builder: (sheetContext) {
          deadContext = sheetContext;
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(deadContext).pop();
    await tester.pumpAndSettle();

    expect(
      deadContext.mounted,
      isFalse,
      reason: 'the premise: popping the route unmounts its element',
    );

    await ChatActions.startChat(
      deadContext,
      donationId: 22,
      otherPartyLabel: 'the owner',
    );
    await tester.pumpAndSettle();

    expect(
      chat.requests,
      0,
      reason:
          'aborting is correct here — a dead context can host neither dialog '
          'nor snackbar. It must simply never be what the caller passes.',
    );
  });
}
