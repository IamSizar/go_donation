import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences sharedPreferences;
late Locale appLocale;

/// The app's appearance preference.
///
/// Defaults to [ThemeMode.system] so a phone in dark mode gets a dark app
/// without the user having to find a setting. It previously defaulted to
/// ThemeMode.light and could only ever be light or dark, which meant the dark
/// theme was built, shipped, and almost never seen — and that is how a 2.19:1
/// contrast failure survived on every accent-filled card in the product.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);

final ValueNotifier<int> dashboardTabNotifier = ValueNotifier(0);
final ValueNotifier<bool> profileIncompleteNotifier = ValueNotifier(false);

/// The stored appearance preference. Values: 'system' | 'light' | 'dark'.
const String _themeModeKey = 'theme_mode';

/// The pre-tri-state key: a bool meaning "dark mode is on".
///
/// Read once by [_migrateLegacyDarkMode] and then left alone. It is not
/// deleted, so downgrading to an older build still finds the user's choice.
const String _legacyDarkModeKey = 'dark_mode';

/// Parses a stored preference string. Unknown values fall back to system
/// rather than throwing — a corrupt pref should not stop the app booting.
ThemeMode _themeModeFromName(String? name) => switch (name) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

String _themeModeToName(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// Resolves the startup appearance, upgrading the old bool if it is all we
/// have.
///
/// The three cases the migration has to get right:
///   * `dark_mode` true  → the user explicitly chose dark. Keep dark.
///   * `dark_mode` false → AMBIGUOUS: it is both "chose light" and the old
///     default. It is preserved as light anyway, because silently switching a
///     user to system would change the appearance of an app they were happy
///     with, and that is worse than being conservative for existing installs.
///   * absent            → a fresh install. System.
ThemeMode _migrateLegacyDarkMode(SharedPreferences prefs) {
  final stored = prefs.getString(_themeModeKey);
  if (stored != null) return _themeModeFromName(stored);

  final legacy = prefs.getBool(_legacyDarkModeKey);
  if (legacy == null) return ThemeMode.system;
  return legacy ? ThemeMode.dark : ThemeMode.light;
}

Future<void> initializeAppState() async {
  sharedPreferences = await SharedPreferences.getInstance();
  appLocale = await AppLocaleService.loadLocale();
  await AppLocaleService.syncDateFormatLocale(appLocale);
  appThemeMode.value = _migrateLegacyDarkMode(sharedPreferences);
  profileIncompleteNotifier.value =
      (sharedPreferences.getInt('done_profile') ?? 0) != 1;
}

/// Records the user's appearance choice and applies it immediately.
Future<void> setAppThemeMode(ThemeMode mode) async {
  appThemeMode.value = mode;
  await sharedPreferences.setString(_themeModeKey, _themeModeToName(mode));
  // Keep the legacy bool in step so an older build installed over this one
  // still reads a sensible value. System resolves to "not dark" there, which
  // is that build's default anyway.
  await sharedPreferences.setBool(_legacyDarkModeKey, mode == ThemeMode.dark);
}

/// Kept for the two-state call sites that have not moved to the tri-state
/// picker yet.
@Deprecated('Use setAppThemeMode; this cannot express ThemeMode.system.')
Future<void> setAppDarkMode(bool isDark) =>
    setAppThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);

// Exposed for tests, which cannot reach the private helpers.
@visibleForTesting
ThemeMode themeModeFromNameForTest(String? name) => _themeModeFromName(name);

@visibleForTesting
ThemeMode migrateLegacyDarkModeForTest(SharedPreferences prefs) =>
    _migrateLegacyDarkMode(prefs);
