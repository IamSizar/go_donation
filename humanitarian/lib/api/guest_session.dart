import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// Note #40 — Guest Account Structure and Permissions. A guest is now a real
/// (lightweight) account: username + password, a real Bearer token, and
/// server-side enforced restrictions (City Directory, messaging, purchases/
/// service requests — see the backend's auth.RequireNotGuest /
/// BlockGuestOptional). The Super Admin still decides which BROWSE screens
/// are visible via the dashboard "Guest Access" page (GET /api/guest/config);
/// that's independent of and unrelated to the hard-coded restrictions above.

const String kGuestModePrefsKey = 'is_guest';

/// In-memory whitelist fetched from the backend: screen slug -> visible.
/// Empty (everything hidden) until [fetchGuestConfig] populates it.
final Map<String, bool> guestScreenConfig = <String, bool>{};

/// True when the app is running as a signed-out guest.
bool isGuestMode() => sharedPreferences.getBool(kGuestModePrefsKey) ?? false;

/// Leave guest mode (e.g. when the guest chooses to sign in).
Future<void> exitGuestMode() async {
  await sharedPreferences.setBool(kGuestModePrefsKey, false);
}

/// Whether a given screen is visible. Signed-in users always see it (their own
/// role decides); guests only see screens the Super Admin enabled.
bool guestCanSee(String screen) {
  if (!isGuestMode()) return true;
  return guestScreenConfig[screen] ?? false;
}

/// Fetch the guest whitelist. Best-effort: on failure the map stays as-is so a
/// transient error can't accidentally open gated screens.
Future<void> fetchGuestConfig() async {
  try {
    final resp = await http.get(
      Uri.parse('${baseUrl}guest/config'),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final decoded = jsonDecode(resp.body);
      final screens = decoded is Map ? decoded['screens'] : null;
      if (screens is Map) {
        guestScreenConfig
          ..clear()
          ..addEntries(screens.entries.map(
            (e) => MapEntry(e.key.toString(), e.value == true),
          ));
      }
    }
  } catch (_) {
    /* keep whatever we have */
  }
}

/// Result of a guest register/login/upgrade call.
class GuestAuthResult {
  const GuestAuthResult({required this.ok, this.error, this.code});
  final bool ok;
  final String? error;
  // Machine-readable failure reason from the backend (e.g. "username_taken"),
  // when present, so the UI can react specifically instead of just showing
  // the generic message.
  final String? code;
}

/// #40 — create a new guest account (username + password) and enter guest
/// mode with a real, server-issued session.
Future<GuestAuthResult> registerGuest(String username, String password) =>
    _guestAuthCall(guestRegisterUrl, username, password, isLogin: false);

/// #40 — sign back into an existing guest account.
Future<GuestAuthResult> loginGuest(String username, String password) =>
    _guestAuthCall(guestLoginUrl, username, password, isLogin: true);

Future<GuestAuthResult> _guestAuthCall(
  String url,
  String username,
  String password, {
  required bool isLogin,
}) async {
  try {
    final resp = await http
        .post(
          Uri.parse(url),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decodeGuestBody(resp.body);
    if (resp.statusCode != 200 || body['status'] != 'success') {
      return GuestAuthResult(
        ok: false,
        error: body['error']?.toString() ?? 'Something went wrong.',
        code: body['code']?.toString(),
      );
    }
    final uid = body['user_id'];
    if (uid != null) {
      await sharedPreferences.setString('id_user', uid.toString());
    }
    await persistApiSessionFromResponse(body);
    final regStatus = body['registration_status']?.toString();
    if (regStatus != null && regStatus.isNotEmpty) {
      await sharedPreferences.setString('registration_status', regStatus);
    }
    final rawAccount = body['account'];
    if (rawAccount is Map) {
      await applyUserAccountToSharedPreferences(
        Map<String, dynamic>.from(rawAccount),
      );
    }
    await sharedPreferences.setBool(kGuestModePrefsKey, true);
    await fetchGuestConfig();
    // Note #40 — same live-feed analytics event every other login/register
    // path fires, so the admin dashboard's EventsFeed shows guest activity
    // too (badged distinctly as "Guest").
    await AppEventFirestore.log(
      eventType: isLogin ? 'guest_login' : 'guest_register',
      eventLabel: isLogin ? 'Guest logged in' : 'Guest account created',
      module: 'auth',
      action: isLogin ? 'guest_login' : 'guest_register',
      userId: uid is int ? uid : int.tryParse(uid?.toString() ?? ''),
      name: username,
      note: isLogin ? 'Guest sign-in succeeded' : 'Guest registration succeeded',
    );
    return const GuestAuthResult(ok: true);
  } catch (_) {
    return const GuestAuthResult(
      ok: false,
      error: 'Network error. Please try again.',
    );
  }
}

Map<String, dynamic> _decodeGuestBody(String s) {
  try {
    final d = jsonDecode(s);
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {}
  return <String, dynamic>{};
}

/// Gate for account-only actions (donate, volunteer, apply, chat, profile).
/// For a guest it shows a "sign in to continue" prompt and returns false so the
/// caller aborts; for a signed-in user it returns true immediately.
Future<bool> requireSignIn(BuildContext context) async {
  if (!isGuestMode()) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Sign in required'.tr),
      content: Text('Please sign in to use this feature.'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Not now'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Sign in'.tr),
        ),
      ],
    ),
  );
  if (go == true) {
    await exitGuestMode();
    Get.offAllNamed(AppRoutes.authLogin);
  }
  return false;
}

/// #40 — gate for the note's three explicit guest restrictions: City
/// Directory, Marriage/assistance messaging, and any purchase or service
/// request. Shows an "Upgrade Account" prompt for a guest and routes to the
/// phone+OTP upgrade flow (which lands on the SAME registration form any new
/// signup fills in); a non-guest passes straight through, same shape as
/// [requireSignIn].
Future<bool> requireUpgrade(BuildContext context, {String? reason}) async {
  if (!isGuestMode()) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Upgrade Account'.tr),
      content: Text((reason ?? 'Create a full account to use this feature.').tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Not now'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Upgrade Account'.tr),
        ),
      ],
    ),
  );
  if (go == true) {
    Get.toNamed(AppRoutes.guestUpgrade);
  }
  return false;
}

/// Result of [upgradeGuestVerifyOtp].
class GuestUpgradeResult {
  const GuestUpgradeResult({required this.ok, this.error});
  final bool ok;
  final String? error;
}

/// #40 — consumes the phone's OTP (already sent via the normal
/// [otpRequestUrl] flow) and attaches it to the current, authed guest
/// account. On success the account is no longer a guest and
/// registration_status becomes 'incomplete', so the caller should follow up
/// with `routeByRegistrationStatus('incomplete')` to land on the standard
/// "complete your registration" form.
Future<GuestUpgradeResult> upgradeGuestVerifyOtp(
  String phone,
  String code,
) async {
  try {
    final resp = await http
        .post(
          Uri.parse(guestUpgradeVerifyUrl),
          headers: withApiAuthHeaders({'Content-Type': 'application/json'}),
          body: jsonEncode({'phone': phone, 'code': code}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decodeGuestBody(resp.body);
    if (resp.statusCode != 200 || body['status'] != 'success') {
      return GuestUpgradeResult(
        ok: false,
        error: body['error']?.toString() ?? 'Something went wrong.',
      );
    }
    final regStatus = body['registration_status']?.toString();
    if (regStatus != null && regStatus.isNotEmpty) {
      await sharedPreferences.setString('registration_status', regStatus);
    }
    final rawAccount = body['account'];
    if (rawAccount is Map) {
      await applyUserAccountToSharedPreferences(
        Map<String, dynamic>.from(rawAccount),
      );
    }
    await sharedPreferences.setBool(kGuestModePrefsKey, false);
    return const GuestUpgradeResult(ok: true);
  } catch (_) {
    return const GuestUpgradeResult(
      ok: false,
      error: 'Network error. Please try again.',
    );
  }
}
