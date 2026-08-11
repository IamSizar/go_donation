// App theme — builds Flutter's ThemeData from the design tokens.
//
// This file is the bridge between `core/design/tokens.dart` (which owns every
// value) and the rest of the app (which asks for colours through the static
// accessors below). It deliberately keeps the accessor names the app already
// uses — `text(context)`, `mutedText(context)`, `border(context)` and so on,
// ~650 call sites between them — so the redesign changes what those return
// without touching every screen at once.
//
// WHAT CHANGED AND WHY (from the design audit)
//
//   * `defaultFontFamily` was hardcoded to 'Arial'. Arial is neither iOS's SF
//     Pro nor Android's Roboto — a third face that happens to exist on both,
//     so it worked everywhere and belonged nowhere. It is now null, which
//     means "use the platform's own system font", the one that already ships
//     optical sizing and tracking tables.
//
//   * The accent colour was one constant reused in both themes and measured
//     3.42:1 against the dark background across 104 usage sites. It now
//     resolves per brightness via [accent]; the legacy const [primary] is
//     retained for compatibility but deprecated.
//
//   * `heroGradient` ran teal→blue with white text on it. White on the teal
//     stop measured 2.49:1 — below even the 3.0 large-text floor — on the
//     most prominent element in the product. Contrast on a gradient is
//     positional, which is why it cannot be fixed by nudging one value. Both
//     stops are now the accent, so it renders as a flat, measured surface.
//
//   * Card radius 24, input radius 18, button radius 18 and a dozen other
//     one-off values are now AppRadius.sm/md.
import 'package:flutter/material.dart';

import 'package:flutter_application_1/core/design/tokens.dart';

class AppThemeConfig {
  /// The Latin-script font family.
  ///
  /// `null` on purpose: it hands typography to the platform, so iOS renders
  /// in SF Pro and Android in Roboto. Do not put a named family here again
  /// unless the brand genuinely requires one — the system faces are better
  /// tuned than anything we would substitute.
  static const String? defaultFontFamily = null;

  /// The Arabic-script family, used for ar / ckb / kmr.
  ///
  /// KNOWN GAP: this asset is bundled at weight 400 only, so every
  /// FontWeight.w600 in the app is synthesised for three of our four
  /// languages — which damages Arabic letterforms considerably more than it
  /// does Latin. Replacing this with a family shipping 400/600/700 (IBM Plex
  /// Sans Arabic and Noto Sans Arabic are both free and good) is the single
  /// highest-impact typographic fix available.
  static const String arabicScriptFontFamily = 'Kurdfont';

  /// What used to be the teal→blue hero ramp.
  ///
  /// Both stops are now the same accent, so any `LinearGradient` built from
  /// this paints a flat colour — the original ran white text over a teal stop
  /// measuring 2.49:1, below even the 3.0 large-text floor, on the most
  /// prominent element in the product. Contrast on a gradient is positional,
  /// which is why it could not be fixed by nudging one value.
  ///
  /// Exactly ONE caller remains: splash_screen, the deliberate brand moment
  /// and documented exception to the flat treatment. Every other hero now
  /// paints a solid [accent] directly.
  @Deprecated(
    'Gradients make contrast positional. Use AppThemeConfig.accent(context) '
    'with a solid fill instead; this will be removed once splash_screen is '
    'migrated.',
  )
  static const List<Color> heroGradient = <Color>[
    Color(0xFF2F5D4A),
    Color(0xFF2F5D4A),
  ];

  /// Legacy accent constant.
  ///
  /// Kept because 104 call sites still reference it and it is used in
  /// positions where no BuildContext is in scope (e.g. platform image-cropper
  /// configuration). It is the LIGHT accent, so in dark mode it under-contrasts
  /// — prefer [accent] anywhere a context is available.
  @Deprecated(
    'Does not adapt to dark mode (measures 3.42:1 on the dark ground). '
    'Use AppThemeConfig.accent(context).',
  )
  static const Color primary = Color(0xFF2F5D4A);

  // ── Brightness-resolved accessors ───────────────────────────────────────
  // Every one of these reads from the token palette, so light/dark is decided
  // in exactly one place.

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// The action / active / settled colour, correct for the current theme.
  static Color accent(BuildContext context) => AppColors.of(context).accent;

  /// Text or icon colour that sits on top of [accent].
  static Color onAccent(BuildContext context) => AppColors.of(context).onAccent;

  /// Money or state still in flight (unconfirmed, upcoming).
  static Color pending(BuildContext context) => AppColors.of(context).pending;

  /// Destructive actions, validation errors, urgency.
  static Color consequence(BuildContext context) =>
      AppColors.of(context).consequence;

  static Color backgroundTop(BuildContext context) =>
      AppColors.of(context).ground;

  /// Retained for the handful of call sites that build a two-stop background.
  /// Identical to [backgroundTop], so those render flat.
  static Color backgroundBottom(BuildContext context) =>
      AppColors.of(context).ground;

  static Color text(BuildContext context) => AppColors.of(context).ink;

  static Color mutedText(BuildContext context) =>
      AppColors.of(context).inkSecondary;

  /// The quietest text tier — labels, helper text, inactive nav.
  static Color subtleText(BuildContext context) =>
      AppColors.of(context).inkTertiary;

  /// A raised surface. Opaque now rather than a translucent white: a
  /// semi-transparent white over a white ground was paying a legibility cost
  /// for no perceptual gain, because nothing was blurring behind it.
  static Color surface(BuildContext context) => AppColors.of(context).card;

  static Color elevatedSurface(BuildContext context) =>
      AppColors.of(context).card;

  /// A recessed fill: progress troughs, skeleton bones, inert chips.
  static Color softSurface(BuildContext context) =>
      AppColors.of(context).groundSunken;

  static Color border(BuildContext context) => AppColors.of(context).line;

  /// A firmer rule, for input underlines and outlined controls.
  static Color borderStrong(BuildContext context) =>
      AppColors.of(context).lineStrong;

  /// Shadow colour.
  ///
  /// The redesign separates surfaces with a hairline rather than a shadow, so
  /// this is intentionally very light. The audit found 50 BoxShadows spread
  /// across 10+ blur radii with no elevation system behind them.
  static Color shadow(BuildContext context) =>
      isDark(context) ? const Color(0x40000000) : const Color(0x0F191F1C);

  /// The bottom navigation surface.
  ///
  /// Opaque. It was previously `white @ 0.8` applied as a plain colour with
  /// no BackdropFilter behind it — translucency without blur is not a
  /// material, it is a washed-out flat colour that lets content smear
  /// through. Either commit to a real blurred material or go opaque; this
  /// goes opaque and gets crisp legibility back.
  static Color navBarSurface(BuildContext context) =>
      AppColors.of(context).card;

  // ── ThemeData ───────────────────────────────────────────────────────────

  static ThemeData buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: defaultFontFamily,

      // Register the tokens so AppColors.of(context) resolves anywhere under
      // the app, and lerps when the theme animates between modes.
      extensions: <ThemeExtension<dynamic>>[c],

      // Built from our own values rather than fromSeed, so the accent is
      // exactly the measured colour instead of whatever the tonal-palette
      // algorithm derives from it.
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.accent,
        onSecondary: c.onAccent,
        error: c.consequence,
        onError: c.onAccent,
        surface: c.card,
        onSurface: c.ink,
        outline: c.lineStrong,
        outlineVariant: c.line,
      ),

      scaffoldBackgroundColor: c.ground,
      dividerColor: c.line,
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),

      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.ink,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: c.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: c.line),
        ),
      ),

      // Inputs are underlined rather than boxed: one rule instead of four
      // borders, which reads calmer in a form and puts the emphasis on the
      // value the user typed rather than on the container around it.
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.only(bottom: AppSpace.xs),
        labelStyle: TextStyle(
          color: c.inkSecondary,
          fontSize: AppType.meta,
          fontWeight: AppType.wLabel,
        ),
        hintStyle: TextStyle(color: c.inkTertiary, fontSize: AppType.body),
        helperStyle: TextStyle(color: c.inkTertiary, fontSize: AppType.label),
        errorStyle: TextStyle(
          color: c.consequence,
          fontSize: AppType.label,
          fontWeight: AppType.wLabel,
        ),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: c.lineStrong),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.lineStrong),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.consequence, width: 1.5),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.consequence, width: 1.5),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.groundSunken,
          disabledForegroundColor: c.inkTertiary,
          elevation: 0,
          // 48 tall — comfortably past the 44pt minimum touch target.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: 14,
          ),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(
            fontSize: AppType.dense,
            fontWeight: AppType.wAction,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.lineStrong),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: 14,
          ),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(
            fontSize: AppType.dense,
            fontWeight: AppType.wLabel,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(
            fontSize: AppType.dense,
            fontWeight: AppType.wLabel,
          ),
        ),
      ),

      // A selected chip is an ACCENT, not an inversion. This previously used
      // `c.ink` — the near-black body-text colour — which made a chosen filter
      // read as a disabled or inverted control rather than an active choice,
      // and put the app's only near-black fill on a screen with no other one.
      chipTheme: ChipThemeData(
        backgroundColor: c.card,
        selectedColor: c.accent,
        checkmarkColor: c.onAccent,
        side: BorderSide(color: c.lineStrong),
        labelStyle: TextStyle(color: c.inkSecondary, fontSize: AppType.meta),
        secondaryLabelStyle: TextStyle(
          color: c.onAccent,
          fontSize: AppType.meta,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.fullAll),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.card,
        selectedItemColor: c.accent,
        unselectedItemColor: c.inkTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.groundSunken,
        circularTrackColor: c.groundSunken,
      ),

      // The type scale. Sizes, weights, tracking and leading are set together
      // rather than size alone — tracking is negative on display sizes and
      // positive on small uppercase labels, which is the opposite of what the
      // app did before.
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: AppType.display,
          fontWeight: AppType.wDisplay,
          letterSpacing: AppType.trackDisplay,
          height: AppType.leadDisplay,
          color: c.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: AppType.title,
          fontWeight: FontWeight.w600,
          letterSpacing: AppType.trackTitle,
          height: AppType.leadTitle,
          color: c.ink,
        ),
        headlineSmall: TextStyle(
          fontSize: AppType.heading,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: AppType.leadTitle,
          color: c.ink,
        ),
        bodyLarge: TextStyle(
          fontSize: AppType.body,
          fontWeight: AppType.wBody,
          height: AppType.leadBody,
          color: c.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: AppType.dense,
          fontWeight: AppType.wBody,
          height: AppType.leadDense,
          color: c.ink,
        ),
        bodySmall: TextStyle(
          fontSize: AppType.meta,
          fontWeight: AppType.wBody,
          height: AppType.leadDense,
          color: c.inkSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: AppType.label,
          fontWeight: AppType.wLabel,
          letterSpacing: AppType.trackLabel,
          color: c.inkTertiary,
        ),
      ),
    );
  }

  /// Swaps in the Arabic-script family for ar / ckb / kmr.
  ///
  /// Note that Kurdish Sorani and Badini are registered as `ar_IQ` and
  /// `ar_TR` (see AppLocaleService), so testing the language code alone
  /// correctly catches all three right-to-left languages.
  static ThemeData applyLocaleFont(ThemeData theme, Locale? locale) {
    final fontFamily = _fontFamilyForLocale(locale);
    if (fontFamily == null) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }

  static String? _fontFamilyForLocale(Locale? locale) {
    final languageCode = locale?.languageCode.toLowerCase() ?? '';
    if (languageCode == 'ar') {
      return arabicScriptFontFamily;
    }
    return defaultFontFamily;
  }
}
