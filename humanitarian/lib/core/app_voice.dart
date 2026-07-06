// #21 — AppVoice: a tiny text-to-speech helper, sibling of AppSound.
//
// Used by the beneficiary "My Entitlements" screen to read the entitlement
// summary aloud (accessibility for low-literacy users). Like AppSound it is a
// lazily-initialized, catch-everything, safe no-op: if the platform has no TTS
// engine or a language isn't installed, calls silently do nothing rather than
// throwing.

import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract final class AppVoice {
  static FlutterTts? _tts;
  static bool _disabled = false;

  static Future<FlutterTts> _ensure() async {
    if (_tts != null) return _tts!;
    final t = FlutterTts();
    // Calm, clear defaults for a spoken announcement.
    try {
      await t.setSpeechRate(0.45);
      await t.setVolume(1.0);
      await t.setPitch(1.0);
    } catch (_) {}
    _tts = t;
    return t;
  }

  /// Map the app's canonical language (en/ar/ckb/kmr) to a TTS locale. Kurdish
  /// TTS voices are rarely installed, so Sorani/Badini fall back to the Arabic
  /// voice (the text is Arabic-script, so it reads acceptably).
  static String _ttsLang(String appLang) {
    switch (appLang) {
      case 'en':
        return 'en-US';
      case 'ar':
      case 'ckb':
      case 'kmr':
      default:
        return 'ar-SA';
    }
  }

  /// Speak [text] aloud, cancelling any in-progress speech first. langCode
  /// overrides the app locale when given. Safe no-op on failure.
  static Future<void> speak(String text, {String? langCode}) async {
    if (_disabled || text.trim().isEmpty) return;
    try {
      final t = await _ensure();
      await t.stop();
      try {
        await t.setLanguage(_ttsLang(langCode ?? AppLocaleService.assistantLang()));
      } catch (_) {
        // Language not available — speak with whatever the engine defaults to.
      }
      await t.speak(text);
    } catch (_) {
      _disabled = true;
    }
  }

  /// Stop any in-progress speech (e.g. when the screen closes).
  static Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
