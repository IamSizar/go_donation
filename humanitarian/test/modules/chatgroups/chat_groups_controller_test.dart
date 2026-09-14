// Pins ChatGroupsController — the list behind the Messages tab's
// "My Connections" (masked) and "My Team Groups" (team) sections, OPOS #25284
// Phase 5.
//
// WHAT IS PINNED
//   1. A load splits masked groups from team groups, keeping server order.
//   2. A failed first load says what failed and what to do next, localized,
//      and clears the spinner — never a raw exception.
//   3. A successful retry clears that error (the Retry button's contract).
//   4. A failed SILENT poll keeps the last good list and shows no error: a
//      5-second background tick must never flicker an error banner on screen.
//   5. The new-group chime: a poll that brings a group chimes — including the
//      member's very first one, which is the moment a connect request is
//      approved — while the first load and an unchanged poll stay quiet, and
//      nothing chimes after the screen has closed.
//   6. A poll tick never overlaps a load already in flight.
//   7. The poll really runs every 5 seconds, and really stops once closed.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_groups_controller.dart';

import 'fake_chat_groups_api.dart';

/// Lets every pending future and microtask run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() async {
    // The real chime reads the global mute preference.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
  });

  tearDown(Get.reset);

  test('a load splits masked connections from team groups', () async {
    final api = FakeChatGroupsApi()
      ..groups = [
        groupRow(id: 1, kind: 'masked'),
        groupRow(id: 2, kind: 'team', title: 'Distribution team'),
        groupRow(id: 3, kind: 'masked'),
      ];
    final ctrl = ChatGroupsController(api: api);

    await ctrl.fetchGroups();

    expect(ctrl.masked.map((g) => g.id), [1, 3]);
    expect(ctrl.teams.map((g) => g.id), [2]);
    expect(ctrl.isLoading.value, isFalse);
    expect(ctrl.errorMessage.value, isNull);
  });

  test('a failed first load says what failed and what to do next', () async {
    final api = FakeChatGroupsApi()
      ..groupsError = const SocketException('no route to host');
    final ctrl = ChatGroupsController(api: api);

    await ctrl.fetchGroups();

    expect(ctrl.groups, isEmpty);
    expect(ctrl.isLoading.value, isFalse);
    expect(
      ctrl.errorMessage.value,
      allOf(
        contains('Could not load your group chats.'),
        contains('Check your connection'),
        isNot(contains('SocketException')),
      ),
    );
  });

  test('a successful retry clears the earlier error', () async {
    final api = FakeChatGroupsApi()..groupsError = Exception('Database error.');
    final ctrl = ChatGroupsController(api: api);
    await ctrl.fetchGroups();

    api
      ..groupsError = null
      ..groups = [groupRow(id: 5, kind: 'team', title: 'Night shift')];
    await ctrl.fetchGroups();

    expect(ctrl.errorMessage.value, isNull);
    expect(ctrl.teams.map((g) => g.id), [5]);
  });

  test('a failed silent poll keeps the last good list and shows no error', () async {
    final api = FakeChatGroupsApi()..groups = [groupRow(id: 1, kind: 'masked')];
    final ctrl = ChatGroupsController(api: api);
    await ctrl.fetchGroups();

    api.groupsError = Exception('Database error.');
    await ctrl.fetchGroups(silent: true);

    expect(ctrl.groups.map((g) => g.id), [1]);
    expect(ctrl.errorMessage.value, isNull);
  });

  group('the new-group chime', () {
    test("a poll that brings the member's very first group chimes", () async {
      var chimes = 0;
      final api = FakeChatGroupsApi();
      final ctrl = ChatGroupsController(api: api, onNewGroup: () => chimes++);
      await ctrl.fetchGroups();

      api.groups = [groupRow(id: 1, kind: 'masked')];
      await ctrl.fetchGroups(silent: true);

      expect(chimes, 1);
    });

    test('the first load and an unchanged poll stay quiet', () async {
      var chimes = 0;
      final api = FakeChatGroupsApi()..groups = [groupRow(id: 1, kind: 'masked')];
      final ctrl = ChatGroupsController(api: api, onNewGroup: () => chimes++);

      await ctrl.fetchGroups();
      await ctrl.fetchGroups(silent: true);

      expect(chimes, 0);
    });

    test('a poll that finishes after the screen closed does not chime', () async {
      var chimes = 0;
      final api = FakeChatGroupsApi();
      final ctrl = Get.put(
        ChatGroupsController(api: api, onNewGroup: () => chimes++),
      );
      await _settle(); // onInit's opening load (no groups) has finished

      final gate = Completer<void>();
      api
        ..groups = [groupRow(id: 1, kind: 'masked')]
        ..groupsGate = gate;
      final poll = ctrl.fetchGroups(silent: true);
      Get.delete<ChatGroupsController>();
      await _settle();
      gate.complete();
      await poll;

      expect(chimes, 0);
    });
  });

  test('a poll tick while a load is in flight sends no second request', () async {
    final api = FakeChatGroupsApi()
      ..groups = [groupRow(id: 1, kind: 'masked')]
      ..groupsGate = Completer<void>();
    final ctrl = ChatGroupsController(api: api);

    final opening = ctrl.fetchGroups();
    unawaited(ctrl.fetchGroups(silent: true));
    await _settle();
    expect(api.groupsCalls, 1);

    api.groupsGate!.complete();
    await opening;
    await _settle();
    expect(ctrl.groups.map((g) => g.id), [1]);
    expect(
      api.groupsCalls,
      1,
      reason:
          'the skipped tick must not run later either: on a slow connection '
          'queued ticks would pile up behind every request',
    );
  });

  testWidgets('polls every 5 seconds and stops once closed', (tester) async {
    final api = FakeChatGroupsApi()..groups = [groupRow(id: 1, kind: 'masked')];
    Get.put(ChatGroupsController(api: api));
    await tester.pump();
    expect(api.groupsCalls, 1, reason: 'opening the controller loads once');

    await tester.pump(const Duration(seconds: 5));
    expect(api.groupsCalls, 2, reason: 'one background poll after 5s');

    Get.delete<ChatGroupsController>();
    await tester.pump(const Duration(seconds: 15));
    expect(api.groupsCalls, 2, reason: 'no polling after the controller closes');
  });
}
