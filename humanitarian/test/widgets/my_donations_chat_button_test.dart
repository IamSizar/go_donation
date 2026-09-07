// Pins that "Chat with campaign owner" actually sends the chat request.
//
// THE BUG (OPOS 24399)
// This button — the only way to open item 1 of the client's messaging list
// (donor ↔ campaign owner ↔ staff) from the app — did nothing whatsoever. The
// confirm dialog appeared, the user accepted, and no request ever reached the
// server. Verified twice on device against the deployed dev backend: GET
// /api/admin/chats stayed at three threads, and the Messages screen stayed on
// «لا محادثات بعد».
//
//     Navigator.of(context).pop();          // unmounts the sheet's element
//     await ChatActions.startChat(context,  // ...then hands it onwards
//
// startChat awaits the confirm dialog and re-checks `context.mounted`. The
// guard is right — a dead context can host neither dialog nor snackbar — but
// the sheet had already destroyed the context it was passing, so the flow was
// abandoned one line before the POST. Nothing surfaced, because startChat
// reports through ScaffoldMessenger and snackbars do not paint on these routes
// (see the note on `supportChatError` in chat/screens/messages_screen.dart).
//
// WHY IT DRIVES THE REAL WIDGET
// A test that called ChatActions.startChat directly with a healthy context
// would pass against the broken build: the defect was never in startChat, it
// was in which context this sheet chose to hand it. So the sheet itself is
// pumped, and its own button is tapped. DonationDetailSheet is package-visible
// for exactly this reason.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/donations/models/donation_history_models.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';

/// Records whether the request was issued, without a network.
class _RecordingChatController extends ChatController {
  int requests = 0;
  int? lastDonationId;

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
    lastDonationId = donationId;
    return (threadId: 99, status: 'pending', already: false);
  }
}

/// A campaign donation — `id` and `campaignId` both present, which is what
/// gates the button on (`canChat`).
const _entry = DonationHistoryEntry(
  campaignName: 'School Supplies for Orphan Children',
  amount: 25000,
  dateLabel: '07 Sep 2026',
  paymentMethod: 'Cash',
  status: DonationRecordStatus.success,
  deliveryStatus: null,
  reference: '#22',
  note: 'E2E verification contribution',
  id: 22,
  campaignId: 3,
);

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

  testWidgets('tapping it, and confirming, posts the chat request', (
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

    // Presented the way the page presents it: inside a modal sheet, with the
    // row's (host's) context handed down.
    unawaitedSheet(
      showModalBottomSheet<void>(
        context: hostContext,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            DonationDetailSheet(item: _entry, hostContext: hostContext),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('Chat with campaign owner');
    expect(button, findsOneWidget, reason: 'the sheet must offer the button');

    await tester.tap(button);
    await tester.pumpAndSettle();

    final yes = find.text('Yes, start chat');
    expect(
      yes,
      findsOneWidget,
      reason:
          'the confirm dialog is the last thing that worked on the broken '
          'build — everything after it was silently dropped',
    );

    await tester.tap(yes);
    await tester.pumpAndSettle();

    expect(
      chat.requests,
      1,
      reason:
          'THE regression. On the broken build the sheet popped itself and '
          'then passed its own dead context on, so startChat bailed out at its '
          'mounted check and this stayed at 0 — with no error anywhere.',
    );
    expect(
      chat.lastDonationId,
      22,
      reason: 'and it must be THIS donation the chat is opened against',
    );
  });
}

/// The sheet's future only completes when it is popped, and popping needs
/// pumps — awaiting it inline would deadlock the test.
void unawaitedSheet(Future<void> future) {
  future.ignore();
}
