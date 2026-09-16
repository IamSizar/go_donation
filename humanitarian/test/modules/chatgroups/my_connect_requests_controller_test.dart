// Pins MyConnectRequestsController — the requester's own history of "ask
// staff to connect me" requests, OPOS #25284 Phase 5.
//
// WHAT IS PINNED
//   1. A load exposes every request in server order, with its status and
//      decline reason parsed, and clears the spinner.
//   2. A failed load says what failed and what to do next, localized — never
//      the server's English sentence.
//   3. A successful retry clears that error (the Retry button's contract).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/my_connect_requests_controller.dart';

import 'fake_chat_groups_api.dart';

void main() {
  setUp(() {
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
  });

  tearDown(Get.reset);

  test('a load exposes every request in server order', () async {
    final api = FakeChatGroupsApi()
      ..requests = [
        connectRequestRow(id: 9, status: 'approved', groupId: 31),
        connectRequestRow(
          id: 8,
          status: 'declined',
          declineReason: 'Not eligible for this campaign.',
        ),
        connectRequestRow(id: 7, status: 'pending'),
      ];
    final ctrl = MyConnectRequestsController(api: api);

    await ctrl.fetchRequests();

    expect(ctrl.requests.map((r) => r.id), [9, 8, 7]);
    expect(ctrl.requests[0].groupId, 31);
    expect(ctrl.requests[1].declineReason, 'Not eligible for this campaign.');
    expect(ctrl.requests[2].isPending, isTrue);
    expect(ctrl.isLoading.value, isFalse);
    expect(ctrl.errorMessage.value, isNull);
  });

  test('a failed load says what failed and never quotes the server', () async {
    final api = FakeChatGroupsApi()
      ..requestsError = Exception('pq: relation does not exist');
    final ctrl = MyConnectRequestsController(api: api);

    await ctrl.fetchRequests();

    expect(ctrl.requests, isEmpty);
    expect(ctrl.isLoading.value, isFalse);
    expect(
      ctrl.errorMessage.value,
      allOf(
        contains('Could not load your connect requests.'),
        isNot(contains('pq:')),
      ),
    );
  });

  test('a successful retry clears the earlier error', () async {
    final api = FakeChatGroupsApi()..requestsError = Exception('Database error.');
    final ctrl = MyConnectRequestsController(api: api);
    await ctrl.fetchRequests();

    api
      ..requestsError = null
      ..requests = [connectRequestRow(id: 3, status: 'pending')];
    await ctrl.fetchRequests();

    expect(ctrl.errorMessage.value, isNull);
    expect(ctrl.requests.map((r) => r.id), [3]);
  });
}
