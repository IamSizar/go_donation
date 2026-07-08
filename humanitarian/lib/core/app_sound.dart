// Phase 27.1 — short notification chime, sibling of AppHaptics.
//
// The polling-based real-time pipeline (Phase 25 + 27) calls these on
// new-notification arrival and on status transitions detected via diff.
// Sound + haptic together is what gives the volunteer / donor / beneficiary
// the "something just happened" cue without them having to stare at the
// screen — Phase 27 had the haptic wired but the sound was never coded,
// despite comments in NotificationsController hinting at "chime".
//
// We use a tiny (~15KB) WAV bundled in assets/sounds/chime.wav rather than
// SystemSound.play() so the cue is identical on Android + iOS. AudioPlayer
// is lazily initialized on first use and reused — opening it on each call
// would burn ~50ms per chime on older devices.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_application_1/core/app_mute.dart';

abstract final class AppSound {
  static AudioPlayer? _player;
  static bool _disabled = false;
  static DateTime? _lastPlayed;

  /// Minimum gap between consecutive plays. Stops a burst of 5 simultaneous
  /// status transitions (e.g. admin bulk-approves 5 applications) from
  /// stuttering the same chime on top of itself.
  static const Duration _minInterval = Duration(milliseconds: 350);

  static Future<AudioPlayer> _ensurePlayer() async {
    if (_player != null) return _player!;
    final p = AudioPlayer();
    // Lower-latency context — we don't need ducking, looping, or background
    // playback; this is a tiny one-shot cue.
    await p.setReleaseMode(ReleaseMode.stop);
    _player = p;
    return p;
  }

  /// Play the notification chime once. Safe no-op when:
  ///   - audio is permanently disabled (load failure on first try)
  ///   - the previous play was less than 350ms ago (debounce)
  ///   - the platform / device rejects audio (e.g. web before first user
  ///     gesture). Catches everything so callers don't need try/catch.
  static void notification() {
    if (_disabled || AppMute.isMuted) return; // #37 — global mute
    final now = DateTime.now();
    if (_lastPlayed != null && now.difference(_lastPlayed!) < _minInterval) {
      return;
    }
    _lastPlayed = now;
    unawaited(_play());
  }

  static Future<void> _play() async {
    try {
      final p = await _ensurePlayer();
      await p.stop();
      await p.play(AssetSource('sounds/chime.wav'), volume: 0.65);
    } catch (_) {
      // First failure marks us as disabled so we don't keep retrying every
      // 5s — covers desktop without an audio device, web before a click,
      // CI environments, etc.
      _disabled = true;
    }
  }

  /// Drop the underlying player. Useful in tests or if the app wants to
  /// rebuild the audio stack after a long background pause.
  static Future<void> dispose() async {
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
