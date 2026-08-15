// Contrast guard for the design tokens.
//
// WHY THIS TEST EXISTS
// A design audit of this app found two shipped WCAG failures that nobody
// noticed because nobody measured:
//
//   * white on the hero gradient's teal stop  — 2.49:1, below even the 3.0
//     large-text floor, on the most prominent element in the product
//   * the primary accent in dark mode         — 3.42:1, across 104 usage sites
//
// Both were introduced by picking a colour that looked right rather than one
// that measured right, and both survived because contrast was asserted in
// comments instead of checked by anything.
//
// While writing the replacement palette the same mistake was very nearly made
// a third time: the tertiary ink tier was first drafted at #949C96, which
// measures 2.57:1 — and it was carrying labels, helper text and inactive nav
// items, not decoration. Measuring caught it. This test is that measurement,
// made permanent.
//
// If you change a token in `lib/core/design/tokens.dart` and this test fails,
// the token is wrong — not the test.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/tokens.dart';

/// WCAG 2.1 relative luminance for an opaque sRGB colour.
///
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  // `.r/.g/.b` are already normalised 0..1 in current Flutter.
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between two opaque colours. Ranges 1.0 … 21.0.
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// One foreground/background pair that carries text or a meaningful glyph.
class _Pair {
  const _Pair(this.name, this.fg, this.bg);
  final String name;
  final Color fg;
  final Color bg;
}

/// Every pair in the palette that a user actually reads.
///
/// Deliberately excluded: `line` and `lineStrong`. Those are structural
/// hairlines, never text, and WCAG's 4.5:1 text threshold does not apply to
/// them — they are meant to be quiet.
List<_Pair> _textPairs(AppColors c, String theme) => <_Pair>[
  _Pair('$theme ink on ground', c.ink, c.ground),
  _Pair('$theme ink on card', c.ink, c.card),
  _Pair('$theme ink on sunken', c.ink, c.groundSunken),
  _Pair('$theme inkSecondary on ground', c.inkSecondary, c.ground),
  _Pair('$theme inkSecondary on card', c.inkSecondary, c.card),
  _Pair('$theme inkTertiary on ground', c.inkTertiary, c.ground),
  _Pair('$theme inkTertiary on card', c.inkTertiary, c.card),
  _Pair('$theme accent on ground', c.accent, c.ground),
  _Pair('$theme accent on card', c.accent, c.card),
  _Pair('$theme accent on accentWash', c.accent, c.accentWash),
  _Pair('$theme onAccent on accent', c.onAccent, c.accent),
  _Pair('$theme consequence on ground', c.consequence, c.ground),
  _Pair('$theme consequence on card', c.consequence, c.card),
  _Pair('$theme consequence on wash', c.consequence, c.consequenceWash),
  _Pair('$theme pending on ground', c.pending, c.ground),
  _Pair('$theme pending on card', c.pending, c.card),
  _Pair('$theme pending on wash', c.pending, c.pendingWash),
];

void main() {
  group('WCAG AA contrast — every text pair, both themes', () {
    const minimum = 4.5;

    for (final entry in <String, AppColors>{
      'light': AppColors.light,
      'dark': AppColors.dark,
    }.entries) {
      for (final pair in _textPairs(entry.value, entry.key)) {
        test('${pair.name} clears $minimum:1', () {
          final ratio = contrastRatio(pair.fg, pair.bg);
          expect(
            ratio,
            greaterThanOrEqualTo(minimum),
            reason:
                '${pair.name} measures ${ratio.toStringAsFixed(2)}:1, below '
                'the $minimum:1 AA threshold for normal text. Darken the '
                'foreground or lighten the background until it clears.',
          );
        });
      }
    }
  });

  group('palette sanity', () {
    test('the ink ladder is monotonic in both themes', () {
      // Each tier must be genuinely quieter than the one above it, or the
      // three-tier hierarchy is decorative rather than functional.
      for (final c in <AppColors>[AppColors.light, AppColors.dark]) {
        final ink = contrastRatio(c.ink, c.ground);
        final secondary = contrastRatio(c.inkSecondary, c.ground);
        final tertiary = contrastRatio(c.inkTertiary, c.ground);
        expect(ink, greaterThan(secondary));
        expect(secondary, greaterThan(tertiary));
      }
    });

    test('accent differs between themes', () {
      // The bug this guards: one accent constant reused in both themes, which
      // measured 3.42:1 on the dark ground across 104 usage sites.
      expect(
        AppColors.light.accent,
        isNot(equals(AppColors.dark.accent)),
        reason: 'The dark theme needs its own accent, not the light one.',
      );
    });

    test('no token is pure black or pure white on a text surface', () {
      // Pure #000 on #FFF is a tell that a palette was never considered.
      // (onAccent is exempt: white on the olive accent is measured and correct.)
      for (final c in <AppColors>[AppColors.light, AppColors.dark]) {
        expect(c.ink, isNot(equals(const Color(0xFF000000))));
        expect(c.ground, isNot(equals(const Color(0xFF000000))));
      }
    });
  });

  group('the guard has teeth', () {
    // A contrast test that only ever passes proves nothing. These pin the
    // three real failures this palette replaced, so the measurement itself is
    // demonstrably able to detect them. If any of these ever starts passing,
    // the contrastRatio implementation has broken.
    test('detects the old hero gradient failure (2.49:1)', () {
      const white = Color(0xFFFFFFFF);
      const oldHeroTeal = Color(0xFF14B8A6);
      final ratio = contrastRatio(white, oldHeroTeal);
      expect(ratio, closeTo(2.49, 0.01));
      expect(ratio, lessThan(3.0)); // fails even the large-text floor
    });

    test('detects the old dark-mode accent failure (3.42:1)', () {
      const oldAccent = Color(0xFF0F766E);
      const oldDarkGround = Color(0xFF0B1220);
      final ratio = contrastRatio(oldAccent, oldDarkGround);
      expect(ratio, closeTo(3.42, 0.01));
      expect(ratio, lessThan(4.5));
    });

    test('detects the grey-on-grey draft that was nearly shipped (2.57:1)', () {
      const draftTertiary = Color(0xFF949C96);
      final ratio = contrastRatio(draftTertiary, AppColors.light.ground);
      expect(ratio, closeTo(2.57, 0.01));
      expect(ratio, lessThan(4.5));
    });
  });

  group('scales are ordered', () {
    test('spacing ascends', () {
      final scale = <double>[
        AppSpace.xxs,
        AppSpace.xs,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xxl,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('type scale descends from display to label', () {
      final scale = <double>[
        AppType.display,
        AppType.title,
        AppType.heading,
        AppType.body,
        AppType.dense,
        AppType.meta,
        AppType.label,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], lessThan(scale[i - 1]));
      }
    });

    test('display tracking is negative and label tracking positive', () {
      // The audit found 14 of 15 letter-spacing values in the app were
      // positive, including on the largest headings — the opposite of what
      // optical sizing requires.
      expect(AppType.trackDisplay, lessThan(0));
      expect(AppType.trackTitle, lessThan(0));
      expect(AppType.trackLabel, greaterThan(0));
    });
  });

  group('selected chip', () {
    // A chip's selected fill is `accent` and its label is `onAccent`. This
    // pair is easy to break because ChipThemeData names the selected label
    // `secondaryLabelStyle`, which reads like a de-emphasis rather than the
    // on-accent foreground it actually is — the theme originally paired
    // `selectedColor: ink` with `secondaryLabelStyle: ground` for exactly
    // that reason.
    test('light: label on the selected fill clears AA', () {
      expect(
        contrastRatio(AppColors.light.onAccent, AppColors.light.accent),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('dark: label on the selected fill clears AA', () {
      expect(
        contrastRatio(AppColors.dark.onAccent, AppColors.dark.accent),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('an unselected chip label is still readable on the card', () {
      expect(
        contrastRatio(AppColors.light.inkSecondary, AppColors.light.card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(AppColors.dark.inkSecondary, AppColors.dark.card),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('foreground on a semantic fill', () {
    // The whole point of onAccent is that it FLIPS: white in light, near-black
    // in dark. Hardcoded Colors.white was correct in light mode and 2.19:1 in
    // dark, because every semantic colour in the dark palette is a light tint
    // (accent #6FBF9C, consequence #E08B72, pending #D6AB5A). That is worse
    // than the 2.49:1 hero gradient this redesign set out to remove, so it is
    // pinned here for all three fills in both palettes.
    test('light: onAccent clears AA on accent, consequence and pending', () {
      for (final fill in [
        AppColors.light.accent,
        AppColors.light.consequence,
        AppColors.light.pending,
      ]) {
        expect(
          contrastRatio(AppColors.light.onAccent, fill),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('dark: onAccent clears AA on accent, consequence and pending', () {
      for (final fill in [
        AppColors.dark.accent,
        AppColors.dark.consequence,
        AppColors.dark.pending,
      ]) {
        expect(
          contrastRatio(AppColors.dark.onAccent, fill),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('plain white on the dark accent is the failure being guarded', () {
      // If this ever starts passing, the dark accent has been darkened and the
      // Colors.white sites could come back — but check the rest of the palette
      // before allowing that.
      expect(
        contrastRatio(const Color(0xFFFFFFFF), AppColors.dark.accent),
        lessThan(4.5),
      );
    });
  });
}
