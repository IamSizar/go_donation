// Tests for the appearance preference and its migration.
//
// The migration is the part worth pinning: the app shipped a BOOL
// ('dark_mode') and now stores a tri-state STRING ('theme_mode'). Getting the
// upgrade wrong would silently change the appearance of the app for every
// existing install, which is the kind of regression nobody reports as a bug —
// they just think the app looks different now.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';

/// Builds a SharedPreferences seeded with [values].
Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migrating from the legacy dark_mode bool', () {
    test('a fresh install follows the system', () async {
      final prefs = await _prefs({});
      expect(migrateLegacyDarkModeForTest(prefs), ThemeMode.system);
    });

    test('someone who chose dark stays dark', () async {
      final prefs = await _prefs({'flutter.dark_mode': true});
      expect(migrateLegacyDarkModeForTest(prefs), ThemeMode.dark);
    });

    test('someone with the old default stays light, not system', () async {
      // dark_mode:false is ambiguous — it means both "chose light" and "never
      // touched it", because light was the old default. It resolves to light
      // deliberately: switching an existing user to system would change how
      // their app looks, and being conservative for existing installs beats
      // being clever.
      final prefs = await _prefs({'flutter.dark_mode': false});
      expect(migrateLegacyDarkModeForTest(prefs), ThemeMode.light);
    });

    test('an explicit tri-state choice wins over the legacy bool', () async {
      final prefs = await _prefs({
        'flutter.dark_mode': true,
        'flutter.theme_mode': 'system',
      });
      expect(
        migrateLegacyDarkModeForTest(prefs),
        ThemeMode.system,
        reason:
            'Once the user has made a tri-state choice, the legacy bool is '
            'stale and must not override it.',
      );
    });
  });

  group('parsing a stored value', () {
    test('round-trips every mode', () {
      for (final entry in {
        'system': ThemeMode.system,
        'light': ThemeMode.light,
        'dark': ThemeMode.dark,
      }.entries) {
        expect(themeModeFromNameForTest(entry.key), entry.value);
      }
    });

    test('a corrupt or unknown value falls back to system', () {
      // A bad pref must not stop the app booting.
      expect(themeModeFromNameForTest('mauve'), ThemeMode.system);
      expect(themeModeFromNameForTest(''), ThemeMode.system);
      expect(themeModeFromNameForTest(null), ThemeMode.system);
    });
  });

  group('the default', () {
    test('is system, so a dark phone gets a dark app unasked', () {
      // This is the whole point of the task: the dark theme is fully built and
      // was almost never seen, which is how a 2.19:1 contrast failure survived.
      expect(appThemeMode.value, ThemeMode.system);
    });
  });
}
