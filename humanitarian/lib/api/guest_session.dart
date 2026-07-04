import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// Section 27 — Guest Mode (skip sign-in). A guest browses the app with no
/// account/token; the Super Admin decides which screens are visible via the
/// dashboard "Guest Access" page (served at GET /api/guest/config).

const String kGuestModePrefsKey = 'is_guest';

/// In-memory whitelist fetched from the backend: screen slug -> visible.
/// Empty (everything hidden) until [fetchGuestConfig] populates it.
final Map<String, bool> guestScreenConfig = <String, bool>{};

/// True when the app is running as a signed-out guest.
bool isGuestMode() => sharedPreferences.getBool(kGuestModePrefsKey) ?? false;

/// Enter guest mode: flag it locally and load the screen whitelist.
Future<void> enterGuestMode() async {
  await sharedPreferences.setBool(kGuestModePrefsKey, true);
  await fetchGuestConfig();
}

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
