import 'dart:async';

import 'package:vibration/vibration.dart';
import 'package:vibration/vibration_presets.dart';

/// Short, preset-based haptics via [vibration] — safe no-ops when unsupported.
abstract final class AppHaptics {
  static bool? _hasVibrator;
  static Future<bool>? _probe;

  static Future<void> _run(Future<void> Function() play) async {
    try {
      _probe ??= Vibration.hasVibrator();
      _hasVibrator ??= await _probe;
    } catch (_) {
      _hasVibrator = false;
      return;
    }
    if (_hasVibrator != true) return;
    try {
      await play();
    } catch (_) {
      // Ignore a single failed pattern on some devices.
    }
  }

  /// List taps, chips, bottom nav changes, toggles.
  static void selection() {
    unawaited(
      _run(() => Vibration.vibrate(preset: VibrationPreset.singleShortBuzz)),
    );
  }

  /// Notable confirmations: OTP sent, copy-to-clipboard.
  static void gentle() {
    unawaited(
      _run(() => Vibration.vibrate(preset: VibrationPreset.gentleReminder)),
    );
  }

  /// Completed flows: login, role chosen, donation submitted, profile saved.
  static void success() {
    unawaited(
      _run(() => Vibration.vibrate(preset: VibrationPreset.quickSuccessAlert)),
    );
  }

  /// Failed verify, validation errors (use sparingly).
  static void error() {
    unawaited(
      _run(() => Vibration.vibrate(preset: VibrationPreset.doubleBuzz)),
    );
  }
}
