import 'dart:convert';

import 'package:flutter/material.dart';

import 'guest_credentials.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
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

/// The generated credentials of the guest account on THIS device.
///
/// Stored so a guest can get back into the SAME account when a session ends,
/// rather than silently becoming a different person. Before these were
/// generated the user chose them and could retype them; keeping them here
/// preserves that, it does not add a new capability.
///
/// They sit beside the access token, which is at least as sensitive, so this
/// introduces no new class of exposure. The account itself is browse-only —
/// the server blocks a guest from the City Directory, messaging and purchases
/// (auth.RequireNotGuest) — so the value of the credential is low by design.
const String kGuestUsernamePrefsKey = 'guest_username';
const String kGuestPasswordPrefsKey = 'guest_password';

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
          ..addEntries(
            screens.entries.map(
              (e) => MapEntry(e.key.toString(), e.value == true),
            ),
          );
      }
    }
  } catch (_) {
    // DELIBERATE and fail-CLOSED: the whitelist is left untouched, so a
    // transient error can never widen a guest's access. There is no screen to
    // report this on — it is a background config fetch — and the worst case
    // is a guest seeing fewer screens, never more.
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

/// Creates a guest account, asking the user for nothing at all.
///
/// The username and password are GENERATED — see api/guest_credentials.dart
/// for why — and remembered on this device so the same account can be
/// re-entered later.
///
/// NO NAME IS COLLECTED. The sign-up sheet that asked for one is gone: the
/// owner asked for "Continue as guest" to be a single tap into the app. A
/// guest who later upgrades (requireUpgrade → phone + OTP) fills in the
/// normal registration form, which is where a real name is captured.
///
/// A taken username is retried rather than reported. The user did not choose
/// the name, so a collision is the app's problem — showing it would be asking
/// somebody to fix something they cannot even see.
Future<GuestAuthResult> registerGuestAccount() async {
  // Three attempts. Each username is 40 bits of randomness, so a single
  // collision already means something is badly wrong; looping further would
  // just make a real outage look like a hang.
  GuestAuthResult result = const GuestAuthResult(ok: false);
  for (var attempt = 0; attempt < 3; attempt++) {
    final username = generateGuestUsername();
    final password = generateGuestPassword();
    result = await registerGuest(username, password);
    if (result.ok) {
      await sharedPreferences.setString(kGuestUsernamePrefsKey, username);
      await sharedPreferences.setString(kGuestPasswordPrefsKey, password);
      return result;
    }
    if (result.code != 'username_taken') return result;
    debugPrint(
      '[guest] username collision on attempt ${attempt + 1}, retrying',
    );
  }
  return result;
}

/// #40 — create a new guest account (username + password) and enter guest
/// mode with a real, server-issued session.
///
/// Sends no name. POST /api/auth/guest/register treats a body without
/// `full_name` as "this client collected no name" and writes an empty
/// user_profiles.full_name, which is exactly what a nameless guest is.
Future<GuestAuthResult> registerGuest(String username, String password) =>
    _guestAuthCall(guestRegisterUrl, username, password, isLogin: false);

/// #40 — sign back into an existing guest account.
///
/// Takes no name, deliberately. `GuestLogin` (handlers/auth.go) parses the
/// same request struct but never reads the name, so accepting one here would
/// let a caller believe it had renamed an account it had not.
Future<GuestAuthResult> loginGuest(String username, String password) =>
    _guestAuthCall(guestLoginUrl, username, password, isLogin: true);

Future<GuestAuthResult> _guestAuthCall(
  String url,
  String username,
  String password, {
  required bool isLogin,
}) async {
  try {
    // Credentials and nothing else. The endpoint also accepts `full_name`,
    // but the app has no name to send: guest entry is one tap and asks for
    // nothing (see registerGuestAccount).
    final payload = <String, dynamic>{
      'username': username,
      'password': password,
    };
    final resp = await http
        .post(
          Uri.parse(url),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
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
      // No note: it said only what eventType already says, in English, and
      // the dashboard prints notes verbatim. The feed localizes by type.
    );
    return const GuestAuthResult(ok: true);
  } catch (_) {
    // NOT swallowed: the failure is reported through GuestAuthResult, which
    // is what the sign-in form renders. Deliberately not a throw — this is
    // the auth entry point and a network blip must stay a retryable form
    // error, not an unhandled exception on the login screen.
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
  } catch (_) {
    // DELIBERATE: an unparseable body is handled by the empty map below — the
    // callers then find no 'status' == 'success' and report the failure with
    // their generic message. The error is signalled, just not from here.
  }
  return <String, dynamic>{};
}

/// Gate for account-only actions (donate, volunteer, apply, chat, profile).
/// For a guest it shows a "sign in to continue" prompt and returns false so the
/// caller aborts; for a signed-in user it returns true immediately.
Future<bool> requireSignIn(BuildContext context) async {
  if (!isGuestMode()) return true;
  final go = await showAdaptiveConfirm(
    context,
    title: 'Sign in required'.tr,
    message: 'Please sign in to use this feature.'.tr,
    confirmLabel: 'Sign in'.tr,
    cancelLabel: 'Not now'.tr,
  );
  if (go) {
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
  final go = await showAdaptiveConfirm(
    context,
    title: 'Upgrade Account'.tr,
    message: (reason ?? 'Create a full account to use this feature.').tr,
    confirmLabel: 'Upgrade Account'.tr,
    cancelLabel: 'Not now'.tr,
  );
  if (go) {
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
    // NOT swallowed: reported via GuestUpgradeResult, which the OTP screen
    // shows. Deliberately not a throw for the same reason as the guest
    // auth call above — the user must be able to retry the code, and the
    // guest flag is only cleared on a confirmed success, never on failure.
    return const GuestUpgradeResult(
      ok: false,
      error: 'Network error. Please try again.',
    );
  }
}
