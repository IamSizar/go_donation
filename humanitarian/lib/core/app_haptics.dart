import 'dart:async';

import 'package:flutter/services.dart';

/// Crisp, modern haptics backed by the platform's native engine — the iOS
/// Taptic Engine and Android's haptic constants — via Flutter's built-in
/// [HapticFeedback].
///
/// These are short, instant taps (a few milliseconds), NOT the long
/// duration-based buzzes the app used before. Four semantic levels, ascending
/// in strength, so every screen feels consistent:
///
///   selection → tiny tick   (frequent UI taps)
///   gentle    → soft tap    (subtle confirmations / background updates)
///   success   → firm tap    (a flow completed)
///   error     → strong tap  (something failed)
///
/// Every call is fire-and-forget and a safe no-op on platforms/devices without
/// haptics — it can never throw into or block the UI flow.
abstract final class AppHaptics {
  static void _play(Future<void> Function() effect) {
    unawaited(_guard(effect));
  }

  static Future<void> _guard(Future<void> Function() effect) async {
    try {
      await effect();
    } catch (_) {
      // Haptics must never affect the UI flow.
    }
  }

  /// Light tick for frequent UI taps: list rows, chips, bottom-nav, toggles.
  static void selection() => _play(HapticFeedback.selectionClick);

  /// Soft tap for subtle confirmations and background updates: new data
  /// arrived, OTP sent, copied to clipboard.
  static void gentle() => _play(HapticFeedback.lightImpact);

  /// Firm tap for completed flows: login, role chosen, donation submitted,
  /// profile saved.
  static void success() => _play(HapticFeedback.mediumImpact);

  /// Strong tap for failures: failed verification, validation errors.
  static void error() => _play(HapticFeedback.heavyImpact);
}
