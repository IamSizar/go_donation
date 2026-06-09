// Phase 27.3 — FCM device token registration.
//
// The Flutter side previously called FirebaseMessaging.getToken() and only
// debug-printed the result, so the backend's user_device_tokens table
// stayed empty for real devices and every "admin accepts donation" push
// went nowhere. This service finally POSTs the token to
// `/api/notifications/device` and tags it with the user's preferred
// language so the backend can deliver push text in the right one.
//
// Wire from three places (kept idempotent — the backend upserts by
// (user_id, device_token), so re-registering is cheap):
//
//   1. main.dart, just after `initializeAppState()`, so a relaunch with
//      a still-valid session refreshes the token.
//   2. After a successful login (auth controller), so a freshly
//      signed-in volunteer/donor immediately receives pushes.
//   3. AppLocaleService.changeLocale — re-register so the new locale
//      replaces the prior one on the same device row.
//
// All errors are swallowed: a failed registration shouldn't break the
// app. The next trigger (or token refresh) will retry naturally.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';

abstract final class PushRegistration {
  static StreamSubscription<String>? _refreshSub;
  static bool _wired = false;

  /// Subscribe to FCM onTokenRefresh once. Call from app startup.
  /// Idempotent — subsequent calls are no-ops.
  static void wire() {
    if (_wired) return;
    _wired = true;
    _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) {
        // Don't pass the new token — `registerNow()` will read the
        // current token + current locale fresh, which matches what
        // the backend wants if the user also changed languages.
        registerNow();
      },
      onError: (Object e) {
        debugPrint('[push] token refresh error: $e');
      },
    );
  }

  /// Register (or re-register) the current FCM token + current locale
  /// with the backend. Safe to call repeatedly; the server upserts.
  ///
  /// Skips silently when:
  ///   - the user isn't signed in yet (no id_user)
  ///   - FCM hasn't issued a token (permissions denied, simulator without
  ///     APNs, etc.)
  ///   - the network call fails (will retry on next trigger)
  static Future<void> registerNow() async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    if (userId.trim().isEmpty) return;

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[push] getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) return;

    final localeCode = _canonicalLocaleCode(Get.locale);
    final platform = _platformString();

    try {
      await const ModuleApi().postJson(
        '${baseUrl}notifications/device',
        {
          'device_token': token,
          'platform': platform,
          'app_version': _appVersionGuess,
          'locale_code': localeCode,
        },
      );
      debugPrint('[push] registered token (locale=$localeCode, platform=$platform)');
    } catch (e) {
      // Don't surface to the user — silently retry on next trigger.
      debugPrint('[push] register failed (will retry): $e');
    }
  }

  /// Best-effort: drop the FCM token row when the user signs out. We
  /// don't actually delete the FCM token from the device — Firebase
  /// keeps it across sign-outs — but we mark the server row inactive so
  /// further pushes for that user don't land on this device.
  static Future<void> unregisterCurrentDevice() async {
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty) return;
    try {
      await const ModuleApi().postJson(
        '${baseUrl}notifications/device',
        {'device_token': token, 'unregister': true},
      );
    } catch (_) {
      // ignore
    }
  }

  // Map the Flutter Locale (which uses ar_SA / ar_IQ / ar_TR distinctions
  // because the app reuses the Arabic language for the three scripts) to
  // the canonical backend codes: en | ar | ckb | kmr.
  static String _canonicalLocaleCode(Locale? locale) {
    if (locale == null) return 'en';
    switch (AppLocaleService.contentVariant(locale)) {
      case 'ar':
        return 'ar';
      case 'sorani':
        return 'ckb';
      case 'badini':
        return 'kmr';
      default:
        return 'en';
    }
  }

  // We don't import dart:io to keep this file web-safe; instead lean on
  // defaultTargetPlatform from foundation. Web is reported as "web" so
  // the backend can distinguish a desktop browser registration.
  static String _platformString() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'android';
    }
  }

  // Static version label so the backend can later filter "v1.0.x clients
  // only". Bumping the literal here is easier than wiring package_info_plus
  // for one debug field.
  static const String _appVersionGuess = '1.0.0';

  // Tearable for tests + hot-reload sanity. Not called in production.
  @visibleForTesting
  static Future<void> debugTearDown() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    _wired = false;
  }
}
