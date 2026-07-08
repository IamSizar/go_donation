import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/core/app_state.dart';

/// #37 — global mute switch. When on, AppSound / AppHaptics / AppVoice become
/// no-ops. Persisted in SharedPreferences; exposed as a [ValueNotifier] so the
/// settings toggle updates reactively. Kept dependency-light (no imports of the
/// sound/haptics/voice classes) to avoid circular imports — those classes read
/// [isMuted] instead.
abstract final class AppMute {
  static const String _prefKey = 'app_muted';

  static final ValueNotifier<bool> muted = ValueNotifier<bool>(
    sharedPreferences.getBool(_prefKey) ?? false,
  );

  static bool get isMuted => muted.value;

  static Future<void> set(bool value) async {
    muted.value = value;
    await sharedPreferences.setBool(_prefKey, value);
  }
}
