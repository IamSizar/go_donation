import 'dart:async';

import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';

/// Routes the user after sign-in (or on app launch) based on their new-user
/// registration approval status. Replaces the old role-only branch.
///
///   incomplete           -> registration form (must fill name/DOB/address/role)
///   pending | rejected   -> waiting-for-approval screen (can't enter the app)
///   approved | (empty)   -> home (existing/grandfathered users have no status)
///
/// Pass [status] explicitly when you already have it (e.g. straight from the
/// login response); otherwise it's read from the persisted pref.
void routeByRegistrationStatus([String? status]) {
  final s = (status ?? sharedPreferences.getString('registration_status') ?? '')
      .trim()
      .toLowerCase();

  if (s == 'incomplete') {
    Get.offAllNamed(AppRoutes.registration);
    return;
  }
  if (s == 'pending' || s == 'rejected') {
    Get.offAllNamed(AppRoutes.pendingApproval);
    return;
  }

  // approved, or unknown (grandfathered accounts predate the status column).
  final roleId = sharedPreferences.getString('role_id');
  if (roleId != null && roleId.trim().isNotEmpty) {
    Get.offAllNamed(AppRoutes.home);
  } else {
    // Approved but no role yet — send them through the form to pick one.
    Get.offAllNamed(AppRoutes.registration);
  }
}

/// Entry point used right after a session is established. Reads the status the
/// sign-in response persisted to prefs.
void goToPostLoginDestination() => routeByRegistrationStatus();

/// Persists a fresh session's identity and routes to wherever this user belongs.
///
/// A16 — extracted from the verification screen, which used to be the only place
/// a phone session was born. There are three now (password sign-in, finishing
/// sign-up with a password, and the code-verified rescue of an account that had
/// none), and all three must land the user in the same state: same prefs, same
/// profile refresh, same push registration, same routing decision. Three copies
/// of this would have drifted, and the first symptom would have been a user
/// signed in with an empty profile.
///
/// [user] is the map the login controller builds from any /auth/* success
/// response. Safe to await; it never throws for a missing field.
Future<void> completeSignInAndRoute(Map<String, dynamic> user) async {
  await sharedPreferences.setString('id_user', user['id'].toString());
  await sharedPreferences.setString(
    'phone_user',
    (user['phone'] ?? '').toString(),
  );
  await sharedPreferences.setString('name_user', user['name'].toString());

  // WHY `includeRoleId: false` SURVIVES HERE, AND IS NOT THE ROLE DRIFT.
  //
  // Both this map and the GET below are followed by the `has_role` block at the
  // bottom of this function, which writes the sign-in response's ROOT
  // `role_id` — and, crucially, REMOVES the stored role when `has_role` is
  // false. `applyUserAccountToSharedPreferences` cannot express that removal:
  // it only ever writes a positive role. So the root block is strictly the
  // better-informed writer, it runs last, and it always runs —
  // `LoginController._buildUserFromLoginResponse` sets `user['has_role']`
  // unconditionally on every path that reaches here (password sign-in, first
  // password after OTP, Google). Flipping these flags to true would therefore
  // be harmless and also pointless: the root block would overwrite the result a
  // few lines later, and both values came out of the same response anyway.
  //
  // The drift that was actually observed — role_id "1" stored for an account
  // the server reports as 2 — happens AFTER sign-in, when staff grant a role,
  // and no flag on this call could have caught it. It is fixed where the app
  // does learn the new role: see applyServerRoleKeyToSharedPreferences, called
  // from the dashboard summary in RoleDashboardController.
  final rawAcc = user['account'];
  if (rawAcc is Map) {
    await applyUserAccountToSharedPreferences(
      Map<String, dynamic>.from(rawAcc),
      includeRoleId: false,
    );
  }

  // Always reload the profile from GET — the sign-in `account` may be missing,
  // nested, or use odd keys.
  final uid = int.tryParse(user['id'].toString());
  if (uid != null && uid > 0) {
    final remote = await fetchUserAccount(uid);
    if (remote != null) {
      await applyUserAccountToSharedPreferences(remote, includeRoleId: false);
    }
  }

  // The sign-in APIs return has_role / role_id — sync prefs with the server.
  if (user.containsKey('has_role')) {
    final hasRole = user['has_role'] == true;
    if (hasRole) {
      final raw = user['role_id'];
      final rid = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      if (rid != null && rid > 0) {
        await sharedPreferences.setString('role_id', rid.toString());
      }
    } else {
      await sharedPreferences.remove('role_id');
    }
  }

  // New-user approval flow — persist the status so the router can decide
  // between the registration form, the pending screen, or home.
  final regStatus = user['registration_status']?.toString();
  if (regStatus != null && regStatus.isNotEmpty) {
    await sharedPreferences.setString('registration_status', regStatus);
  }

  // Phase 27.3 — register the FCM device row with the user's locale so
  // server-side pushes arrive in the right language. Fire-and-forget so
  // navigation doesn't wait on the network.
  unawaited(PushRegistration.registerNow());

  goToPostLoginDestination();
}
