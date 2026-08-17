// Pins the locally stored role following the server's, rather than the
// account's registration day.
//
// WHY THIS FILE EXISTS
// SharedPreferences held `flutter.role_id = "1"` (donor) for an account the
// server reports as `role_id: 2` (beneficiary) — read straight off the
// simulator's plist and confirmed against `GET /api/admin/users?q=said`. Every
// screen gated on the local value therefore behaved as the wrong role:
// Services (`proposal_services_section` switches on '2'/'3'), Kafala
// (`sponsorship_section` on '2'), Settings (`settings_section` on '3'), the
// assistant, and the notification filters.
//
// WHERE THE DRIFT COMES FROM
// The local copy is written when the USER acts — at registration
// (`registration_api`), at sign-in (`core/auth_navigation`), and when the user
// changes their own account type (`ModuleApi.chooseRole`). Nothing wrote it
// when the SERVER acted, and that is the common case: the Recipient and
// Volunteer roles are granted by staff after vetting, and `chooseRole` refuses
// to set them at all. So a promoted account kept its old role until the app
// was cold-started (splash refreshes it) or the profile tab happened to be
// opened.
//
// The truth was already arriving and being thrown away. Every dashboard
// summary carries `role_key`; `profile_menu_screen` says outright that "the
// backend is the source of truth for the role"; and `widgets/dashboard`
// already prefers that value over the stored one — a local workaround that
// fixed the home screen's body and left every other role gate reading the
// stale pref.
//
// WHAT IS PINNED HERE
//   1. The mapping, including the two cases that must NOT be written: 'guest'
//      is this app's "I do not know" as much as it is a role (it is the
//      controller's seed value AND its failure fallback), and an unrecognised
//      key is a newer server talking to an older build.
//   2. The write-back itself: a summary reporting beneficiary corrects a
//      device holding donor.
//   3. That it happens on the SILENT poll too, because that is what makes the
//      correction land while the user is sitting on the home screen rather
//      than at the next cold start.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';

/// A ModuleApi whose dashboard summary answers with a fixed role, so the
/// controller can be exercised without a network. Only the one method is
/// overridden; everything else is the real class.
class _SummaryApi extends ModuleApi {
  const _SummaryApi(this.roleKey);

  final String roleKey;

  @override
  Future<Map<String, dynamic>> dashboardSummary({required int userId}) async {
    return <String, dynamic>{
      'success': true,
      'role_key': roleKey,
      'summary': const <String, dynamic>{},
    };
  }
}

void main() {
  setUp(() async {
    // A device that registered as a donor and was later promoted by staff.
    SharedPreferences.setMockInitialValues({'id_user': '7', 'role_id': '1'});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  group('the server role key maps onto the stored role id', () {
    test('the three granted roles and the marriage service map', () {
      // The numbers are the ones the rest of the app switches on; 5 is named
      // in ModuleApi.chooseRole ("a switch INTO the marriage service (5)").
      expect(roleIdForServerRoleKey('donor'), '1');
      expect(roleIdForServerRoleKey('beneficiary'), '2');
      expect(roleIdForServerRoleKey('volunteer'), '3');
      expect(roleIdForServerRoleKey('marriage'), '5');
    });

    test('guest maps to nothing, because it also means "I do not know"', () {
      expect(
        roleIdForServerRoleKey('guest'),
        isNull,
        reason:
            'RoleDashboardController seeds roleKey with guest and falls back '
            'to guest whenever the summary cannot be read, so writing it back '
            'would let one failed poll demote a real account',
      );
    });

    test('an unrecognised key maps to nothing', () {
      expect(roleIdForServerRoleKey('employee'), isNull);
      expect(roleIdForServerRoleKey(''), isNull);
      expect(
        roleIdForServerRoleKey('some_role_added_later'),
        isNull,
        reason:
            'a newer server talking to an older build is silence, and silence '
            'is not a statement about this account',
      );
    });
  });

  group('the stored role follows the server', () {
    test('a promoted account is corrected', () async {
      final changed = await applyServerRoleKeyToSharedPreferences(
        'beneficiary',
      );

      expect(changed, isTrue);
      expect(
        sharedPreferences.getString('role_id'),
        '2',
        reason: 'this is the exact drift that was observed on a device',
      );
    });

    test('an unchanged role writes nothing', () async {
      expect(await applyServerRoleKeyToSharedPreferences('donor'), isFalse);
      expect(sharedPreferences.getString('role_id'), '1');
    });

    test('guest and unknown keys leave the stored role alone', () async {
      expect(await applyServerRoleKeyToSharedPreferences('guest'), isFalse);
      expect(await applyServerRoleKeyToSharedPreferences('employee'), isFalse);
      expect(
        sharedPreferences.getString('role_id'),
        '1',
        reason:
            'a value that cannot be interpreted must never clear or overwrite '
            'one that could',
      );
    });
  });

  group('the dashboard summary is where the app learns it', () {
    test('loading the summary corrects the stored role', () async {
      final controller = RoleDashboardController(
        api: const _SummaryApi('beneficiary'),
      );

      await controller.fetchSummary();

      expect(controller.roleKey.value, 'beneficiary');
      expect(
        sharedPreferences.getString('role_id'),
        '2',
        reason:
            'the observable alone only fixed the home tab body; every other '
            'role gate reads this pref',
      );
    });

    test('the silent poll corrects it too', () async {
      final controller = RoleDashboardController(
        api: const _SummaryApi('volunteer'),
      );

      // Silent is the 10s poll. If the write-back only happened on a visible
      // load, a role granted while the user watched the home screen would not
      // land until they navigated away and back.
      await controller.fetchSummary(silent: true);

      expect(sharedPreferences.getString('role_id'), '3');
    });

    test('a summary that fails leaves the stored role untouched', () async {
      final controller = RoleDashboardController(api: const _FailingApi());

      await controller.fetchSummary();

      expect(
        sharedPreferences.getString('role_id'),
        '1',
        reason:
            'a failed request says nothing about the account; demoting it to '
            'the guest fallback would be worse than the drift being fixed',
      );
    });
  });
}

/// A ModuleApi whose summary always fails, standing in for an offline device
/// or a 500.
class _FailingApi extends ModuleApi {
  const _FailingApi();

  @override
  Future<Map<String, dynamic>> dashboardSummary({required int userId}) async {
    throw Exception('Request failed (500)');
  }
}
