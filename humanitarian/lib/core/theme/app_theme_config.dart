import 'package:flutter/material.dart';

class _AppPalette {
  static const Color primary = Color(0xFF0F766E);
  static const Color backgroundTop = Color(0xFFF5FBFF);
  static const Color backgroundBottom = Color(0xFFE8F3FF);
  static const Color darkBackgroundTop = Color(0xFF08131F);
  static const Color darkBackgroundBottom = Color(0xFF0F1B2D);
  static const Color text = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkMutedText = Color(0xFF94A3B8);
  static const List<Color> heroGradient = [
    Color(0xFF14B8A6),
    Color(0xFF2563EB),
  ];
}

class AppThemeConfig {
  static const String defaultFontFamily = 'Arial';
  static const String arabicScriptFontFamily = 'Kurdfont';
  static const List<Color> heroGradient = _AppPalette.heroGradient;
  static const Color primary = _AppPalette.primary;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundTop(BuildContext context) => isDark(context)
      ? _AppPalette.darkBackgroundTop
      : _AppPalette.backgroundTop;

  static Color backgroundBottom(BuildContext context) => isDark(context)
      ? _AppPalette.darkBackgroundBottom
      : _AppPalette.backgroundBottom;

  static Color text(BuildContext context) =>
      isDark(context) ? _AppPalette.darkText : _AppPalette.text;

  static Color mutedText(BuildContext context) =>
      isDark(context) ? _AppPalette.darkMutedText : _AppPalette.mutedText;

  static Color surface(BuildContext context) => isDark(context)
      ? const Color(0xCC132033)
      : Colors.white.withValues(alpha: 0.78);

  static Color elevatedSurface(BuildContext context) =>
      isDark(context) ? const Color(0xFF16263A) : Colors.white;

  static Color softSurface(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.04);

  static Color border(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.8);

  static Color shadow(BuildContext context) => isDark(context)
      ? Colors.black.withValues(alpha: 0.28)
      : Colors.black.withValues(alpha: 0.05);

  static Color navBarSurface(BuildContext context) => isDark(context)
      ? const Color(0xD9111C2D)
      : Colors.white.withValues(alpha: 0.8);

  static ThemeData buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textColor = isDark ? _AppPalette.darkText : _AppPalette.text;
    final mutedColor = isDark
        ? _AppPalette.darkMutedText
        : _AppPalette.mutedText;
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.85);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.teal.shade100;

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _AppPalette.primary,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: isDark
          ? _AppPalette.darkBackgroundTop
          : _AppPalette.backgroundTop,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark
            ? const Color(0xCC132033)
            : Colors.white.withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: TextStyle(color: mutedColor),
        hintStyle: TextStyle(color: mutedColor.withValues(alpha: 0.85)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _AppPalette.primary, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _AppPalette.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        bodyMedium: TextStyle(color: textColor, fontSize: 16),
      ),
      dividerColor: mutedColor.withValues(alpha: 0.2),
      fontFamily: defaultFontFamily,
      useMaterial3: true,
    );
  }

  static ThemeData applyLocaleFont(ThemeData theme, Locale? locale) {
    final fontFamily = _fontFamilyForLocale(locale);
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }

  static String _fontFamilyForLocale(Locale? locale) {
    final languageCode = locale?.languageCode.toLowerCase() ?? '';
    if (languageCode == 'ar') {
      return arabicScriptFontFamily;
    }
    return defaultFontFamily;
  }
}
