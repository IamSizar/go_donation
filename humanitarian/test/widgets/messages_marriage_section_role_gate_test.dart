// Pins the ROLE SEPARATION on the engagement (خطوبة) block inside «الرسائل».
//
// WHY THIS FILE EXISTS
// The client could not find the messaging channels at all ("لم نعلم طريقة
// استخدامهم او من اين"), so items 4 and 5 of their list were surfaced inside
// the Messages screen alongside the ones already there. Zaid's condition on
// that change was explicit: "make sure of propper seperation, like each chat
// appears for the correct role". A volunteer or a donor must never be shown
// engagement chats.
//
// WHAT MAKES THIS WORTH A TEST
// The gate has two halves that pull in opposite directions and neither is
// obviously right on its own:
//
//   • Role alone would hide the section from a genuine participant whose
//     locally-known role has drifted — a real defect on this codebase, pinned
//     next door in test/core/role_drift_test.dart, where a device was found
//     holding donor for an account the server reported as beneficiary.
//   • Data alone would hide the section from an engagement user who has no
//     accepted meeting yet — which is exactly the user in the client's
//     complaint. A section that only appears once you already have a
//     conversation cannot teach anyone where to start one.
//
// So the section shows when EITHER holds, and disappears only when NEITHER
// does. All three of those branches are asserted below; the third is the one
// that keeps a volunteer's screen clean.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/chat/widgets/marriage_chats_section.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// Returns a fixed thread list without a network. Only `marriageChats` is
/// overridden; everything else is the real class.
class _ChatsApi extends ModuleApi {
  const _ChatsApi(this.threads);

  final List<Map<String, dynamic>> threads;

  @override
  Future<List<Map<String, dynamic>>> marriageChats() async => threads;
}

/// The real controller with its lifecycle suppressed: `onInit` would fetch the
/// dashboard summary and start a 10s poll, and a widget test that leaves a
/// periodic timer running fails on teardown for reasons unrelated to the gate.
class _RoleController extends RoleDashboardController {
  _RoleController(String role) {
    roleKey.value = role;
  }

  // Skips RoleDashboardController.onInit deliberately: it fires fetchSummary()
  // and starts a 10s poll, so a widget test would hit the network and then
  // fail on teardown with a pending timer. super.onInit() is not called for
  // the same reason — there is nothing here that needs disposing.
  @override
  // ignore: must_call_super
  void onInit() {}
}

Future<void> pumpSection(
  WidgetTester tester, {
  required String role,
  required List<Map<String, dynamic>> threads,
}) async {
  Get.reset();
  Get.put<RoleDashboardController>(_RoleController(role));
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: MarriageChatsSection(api: _ChatsApi(threads)),
        ),
      ),
    ),
  );
  // Settles the FutureBuilder that reads marriageChats().
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  /// The two entry tiles this section contributes, as opposed to anything else
  /// a host screen might render.
  Finder tiles() => find.byType(SectionTile);

  testWidgets('engagement role, no threads: both entries are shown', (
    tester,
  ) async {
    await pumpSection(tester, role: 'marriage', threads: const []);

    expect(
      tiles(),
      findsNWidgets(2),
      reason:
          'this is the user in the client complaint — no accepted meeting yet, '
          'and no idea where the section lives. Hiding it until a conversation '
          'exists is what made it undiscoverable in the first place.',
    );
  });

  testWidgets('volunteer with no engagement threads: nothing renders', (
    tester,
  ) async {
    await pumpSection(tester, role: 'volunteer', threads: const []);

    expect(
      tiles(),
      findsNothing,
      reason:
          'the separation Zaid asked for: a volunteer has no business seeing '
          'engagement chats on their Messages screen',
    );
  });

  testWidgets('donor with no engagement threads: nothing renders', (
    tester,
  ) async {
    await pumpSection(tester, role: 'donor', threads: const []);

    expect(tiles(), findsNothing);
  });

  testWidgets(
    'a real participant is shown the section even when the role says otherwise',
    (tester) async {
      await pumpSection(
        tester,
        role: 'volunteer',
        threads: const [
          {'id': 1, 'status': 'active'},
        ],
      );

      expect(
        tiles(),
        findsNWidgets(2),
        reason:
            'role_drift_test pins that the locally-known role really does go '
            'stale on this app. Data the server returned outranks it: someone '
            'who is in the conversation must never be locked out of it by a '
            'label.',
      );
    },
  );
}
