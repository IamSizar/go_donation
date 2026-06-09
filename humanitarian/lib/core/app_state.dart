import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences sharedPreferences;
late Locale appLocale;
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);
final ValueNotifier<int> dashboardTabNotifier = ValueNotifier(0);
final ValueNotifier<bool> profileIncompleteNotifier = ValueNotifier(false);

Future<void> initializeAppState() async {
  sharedPreferences = await SharedPreferences.getInstance();
  appLocale = await AppLocaleService.loadLocale();
  appThemeMode.value = (sharedPreferences.getBool('dark_mode') ?? false)
      ? ThemeMode.dark
      : ThemeMode.light;
  profileIncompleteNotifier.value =
      (sharedPreferences.getInt('done_profile') ?? 0) != 1;
}

Future<void> setAppDarkMode(bool isDark) async {
  appThemeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  await sharedPreferences.setBool('dark_mode', isDark);
}
