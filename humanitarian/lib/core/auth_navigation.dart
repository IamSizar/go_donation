import 'package:flutter_application_1/core/app_state.dart';
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
  final s =
      (status ?? sharedPreferences.getString('registration_status') ?? '')
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

/// Entry point used right after OTP verification. Reads the status the verify
/// response persisted to prefs.
void goToPostLoginDestination() => routeByRegistrationStatus();
