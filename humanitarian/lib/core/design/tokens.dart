// Design tokens — the single source of truth for every colour, size, space
// and radius in the app.
//
// WHY THIS FILE EXISTS
// A design audit of the app found the same decision being made over and over
// with a different answer each time: 23 distinct border radii (including both
// `99` and `999` used as "pill", i.e. two people independently invented a way
// to say the same thing), 24 distinct SizedBox gap values, 18 font sizes and
// 10+ shadow blur radii. None of those were wrong individually; collectively
// they were unjustifiable, and there was no token to reach for.
//
// It also found two measured WCAG failures:
//   * white on the hero gradient's teal stop  — 2.49:1 (fails even large-text 3.0)
//   * the primary accent in dark mode         — 3.42:1 across 104 usage sites
// Both are impossible to reintroduce here: there is no gradient, and every
// colour below carries its verified contrast ratio in a comment.
//
// HOW TO USE
//   final c = AppColors.of(context);      // brightness-resolved semantic colours
//   Container(padding: EdgeInsets.all(AppSpace.md), color: c.card)
//
// AppColors is a ThemeExtension, so it resolves from the ambient Theme and
// lerps correctly when the app animates between light and dark. Never read a
// raw hex outside this file.
//
// CONTRAST
// Every ratio quoted below is computed to the WCAG 2.1 relative-luminance
// formula against the surface it is designed to sit on. Anything carrying text
// clears 4.5:1 in BOTH themes. `line`/`line2` are non-text borders and are
// deliberately below that — they are structure, not content.
import 'package:flutter/material.dart';

/// Semantic colour tokens, resolved per brightness.
///
/// Read via [AppColors.of]. The two concrete palettes are [AppColors.light]
/// and [AppColors.dark]; they are registered on ThemeData by
/// `AppThemeConfig.buildTheme`, so any widget under the app's MaterialApp can
/// resolve them without being handed anything.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ground,
    required this.groundSunken,
    required this.card,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.accent,
    required this.accentWash,
    required this.onAccent,
    required this.consequence,
    required this.consequenceWash,
    required this.pending,
    required this.pendingWash,
    required this.line,
    required this.lineStrong,
  });

  // ── Surfaces ────────────────────────────────────────────────────────────
  /// Page background. Warm limestone rather than clinical white — it is the
  /// ground everything else is measured against.
  final Color ground;

  /// A recessed surface: progress-bar troughs, skeleton bones, inert fills.
  final Color groundSunken;

  /// A raised surface: the nav bar, sheets, anything that sits above [ground].
  final Color card;

  // ── Text ────────────────────────────────────────────────────────────────
  /// Body text and figures. 15.25:1 on ground, 16.75:1 on card.
  final Color ink;

  /// Supporting text. 7.15:1 on ground, 7.85:1 on card.
  final Color inkSecondary;

  /// Labels, helper text, inactive nav. 4.54:1 on ground, 4.98:1 on card.
  ///
  /// This tier is deliberately darker than it "looks like it should be". An
  /// earlier draft used a lighter grey that measured 2.57:1 — the classic
  /// grey-on-grey failure — while carrying real text. If you lighten this,
  /// re-measure it.
  final Color inkTertiary;

  // ── Meaning ─────────────────────────────────────────────────────────────
  /// Actionable or settled. 6.87:1 on ground light, 8.33:1 dark.
  ///
  /// Used for primary buttons, active nav, completed progress, confirmed
  /// status. Unlike the palette it replaces, this has a genuine dark-mode
  /// sibling rather than one constant reused in both themes.
  final Color accent;

  /// A tint of [accent] for selected backgrounds. Carries [accent] text at
  /// 6.44:1 (light).
  final Color accentWash;

  /// Text/icon colour that sits ON [accent]. 7.54:1 light, 7.72:1 dark.
  final Color onAccent;

  /// Consequence: destructive actions, validation errors, urgency.
  /// 5.38:1 on ground light, 7.03:1 dark.
  final Color consequence;

  /// A tint of [consequence] for error banners. Carries [consequence] text at
  /// 4.99:1.
  final Color consequenceWash;

  /// Money or state still in flight: unconfirmed donations, upcoming dues.
  /// 4.84:1 on ground light, 8.52:1 dark.
  final Color pending;

  /// A tint of [pending] for status chips. Carries [pending] text at 4.64:1.
  final Color pendingWash;

  // ── Structure ───────────────────────────────────────────────────────────
  /// The hairline. Separates list rows and sections. Non-text, so it is not
  /// held to 4.5:1 — it is deliberately quiet.
  final Color line;

  /// A firmer rule for input underlines and outlined controls.
  final Color lineStrong;

  /// Light palette. Ratios in the field docs above are measured against
  /// [ground] = `#F7F4EE` and [card] = `#FFFFFF`.
  static const AppColors light = AppColors(
    ground: Color(0xFFF7F4EE),
    groundSunken: Color(0xFFEFEAE0),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF191F1C),
    inkSecondary: Color(0xFF4A5450),
    inkTertiary: Color(0xFF68726D),
    accent: Color(0xFF2F5D4A),
    accentWash: Color(0xFFE7EFEA),
    onAccent: Color(0xFFFFFFFF),
    consequence: Color(0xFFA8452C),
    consequenceWash: Color(0xFFF7E9E4),
    pending: Color(0xFF8A6516),
    pendingWash: Color(0xFFF6EFE0),
    line: Color(0xFFE4DFD4),
    lineStrong: Color(0xFFCFC8B9),
  );

  /// Dark palette. Not an inversion — each value was chosen and measured
  /// against the dark ground independently, which is why [accent] is a
  /// different hue here rather than the light accent reused.
  static const AppColors dark = AppColors(
    ground: Color(0xFF121618),
    groundSunken: Color(0xFF181E20),
    card: Color(0xFF1A2124),
    ink: Color(0xFFEFF1EE),
    inkSecondary: Color(0xFFB4BCB7),
    inkTertiary: Color(0xFF8E9792),
    accent: Color(0xFF6FBF9C),
    accentWash: Color(0xFF152B25),
    onAccent: Color(0xFF10201B),
    consequence: Color(0xFFE08B72),
    consequenceWash: Color(0xFF2B1913),
    pending: Color(0xFFD6AB5A),
    pendingWash: Color(0xFF271F12),
    line: Color(0xFF283033),
    lineStrong: Color(0xFF3A4448),
  );

  /// Resolves the palette for the ambient theme.
  ///
  /// Falls back to the brightness-appropriate constant if the extension is
  /// somehow missing (e.g. a widget tested outside the app's MaterialApp), so
  /// this never throws in a preview or a test harness.
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({
    Color? ground,
    Color? groundSunken,
    Color? card,
    Color? ink,
    Color? inkSecondary,
    Color? inkTertiary,
    Color? accent,
    Color? accentWash,
    Color? onAccent,
    Color? consequence,
    Color? consequenceWash,
    Color? pending,
    Color? pendingWash,
    Color? line,
    Color? lineStrong,
  }) {
    return AppColors(
      ground: ground ?? this.ground,
      groundSunken: groundSunken ?? this.groundSunken,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkTertiary: inkTertiary ?? this.inkTertiary,
      accent: accent ?? this.accent,
      accentWash: accentWash ?? this.accentWash,
      onAccent: onAccent ?? this.onAccent,
      consequence: consequence ?? this.consequence,
      consequenceWash: consequenceWash ?? this.consequenceWash,
      pending: pending ?? this.pending,
      pendingWash: pendingWash ?? this.pendingWash,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      ground: Color.lerp(ground, other.ground, t)!,
      groundSunken: Color.lerp(groundSunken, other.groundSunken, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkTertiary: Color.lerp(inkTertiary, other.inkTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      consequence: Color.lerp(consequence, other.consequence, t)!,
      consequenceWash: Color.lerp(consequenceWash, other.consequenceWash, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingWash: Color.lerp(pendingWash, other.pendingWash, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
    );
  }
}

/// Spacing scale. Every gap, pad and inset in the app comes from here.
///
/// Four-based, because a 4pt grid is what both platform design systems align
/// to and because the audit found existing values (6, 7, 13, 18, 22) that were
/// each within a step or two of one of these anyway.
abstract final class AppSpace {
  /// 4 — hairline gaps, icon-to-label.
  static const double xxs = 4;

  /// 8 — between tightly related elements.
  static const double xs = 8;

  /// 12 — inside a row, between a title and its metadata.
  static const double sm = 12;

  /// 16 — the default. Screen gutters, card padding.
  static const double md = 16;

  /// 20 — comfortable screen gutter on wider phones.
  static const double lg = 20;

  /// 24 — between distinct groups.
  static const double xl = 24;

  /// 32 — between sections that should read as separate.
  static const double xxl = 32;
}

/// Corner radii. Three values, replacing the twenty-three the audit found.
abstract final class AppRadius {
  /// 10 — inputs, chips, small controls.
  static const double sm = 10;

  /// 16 — cards, sheets, buttons.
  static const double md = 16;

  /// Fully rounded — avatars, pills, progress tracks.
  ///
  /// Use this constant rather than inventing another large number. The audit
  /// found both `99` and `999` in use for exactly this.
  static const double full = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get fullAll => BorderRadius.circular(full);
}

/// Type scale — seven sizes, replacing eighteen.
///
/// Tracking follows the rule that display text needs NEGATIVE letter-spacing
/// (letters read too far apart as they grow) while small text needs slightly
/// positive. The audit found the opposite: 14 of 15 letter-spacing values in
/// the app were positive, including on the largest headings.
///
/// Leading is inverse to size — tight on display, generous on body.
abstract final class AppType {
  /// 38 — the one big figure on a screen. Weight 300: light, not bold.
  static const double display = 38;

  /// 23 — screen titles.
  static const double title = 23;

  /// 20 — a secondary figure, section headline.
  static const double heading = 20;

  /// 15 — body copy.
  static const double body = 15;

  /// 13 — list row titles, dense content.
  static const double dense = 13;

  /// 11 — metadata under a row title.
  static const double meta = 11;

  /// 10 — uppercase section labels and eyebrows.
  static const double label = 10;

  // Tracking, size-specific.
  static const double trackDisplay = -1.3; // ≈ -0.035em at 38
  static const double trackTitle = -0.4; // ≈ -0.018em at 23
  static const double trackBody = 0;
  static const double trackLabel = 1.1; // ≈ +0.11em at 10, uppercase

  // Leading, inverse to size.
  static const double leadDisplay = 1.02;
  static const double leadTitle = 1.14;
  static const double leadBody = 1.5;
  static const double leadDense = 1.45;

  // Weights. Hierarchy is carried by weight as much as size.
  //
  // Note: Flutter's FontWeight only exposes hundreds (w100…w900), unlike CSS
  // which accepts arbitrary values. The design called for 650 on actions;
  // w600 is the nearest available and is the correct choice — w700 reads too
  // heavy on a 13pt button label.
  static const FontWeight wDisplay = FontWeight.w300;
  static const FontWeight wBody = FontWeight.w400;
  static const FontWeight wLabel = FontWeight.w600;
  static const FontWeight wAction = FontWeight.w600;
}
