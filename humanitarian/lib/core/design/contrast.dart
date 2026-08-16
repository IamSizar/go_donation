// WCAG contrast maths, and one helper that USES it to pick a colour.
//
// WHY THIS FILE EXISTS
// The design tokens in tokens.dart are guarded by test/design/contrast_test.dart,
// which measures every foreground/background pair a user reads. That guard is
// why the palette is trustworthy.
//
// It only covers tokens. A screen that defines its OWN colours sits outside it,
// and the community-services category palette did exactly that: eight hand-
// picked hues, each drawn as 11.5px bold text on a 12% wash of itself. Measured
// on the simulator, five of the eight failed WCAG's 4.5:1 text floor in dark
// mode and ALL EIGHT failed in light mode — the worst, food amber, at 2.22:1,
// below even the 3:1 floor that applies to non-text UI.
//
// Nothing caught it because nothing measured it. So rather than hand-tune
// sixteen values that the next added category would not inherit, [readableOn]
// derives the readable colour from the maths at build time: a ninth hue added
// later is compliant by construction.
import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.1 relative luminance of an OPAQUE sRGB colour.
///
/// Composite any translucent colour onto its background (`Color.alphaBlend`)
/// before calling this — a colour's alpha is not part of the formula, so
/// passing a translucent one silently measures the wrong thing.
///
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double relativeLuminance(Color color) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  // `.r/.g/.b` are already normalised 0..1 in current Flutter.
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio between two OPAQUE colours. Ranges 1.0 … 21.0.
///
/// The thresholds that matter: 4.5 for body text, 3.0 for large text (18.66px
/// bold or 24px regular) and for meaningful non-text UI.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// How many steps [readableOn] takes between the tint and the ink.
///
/// Fine enough that the returned colour keeps as much of the original hue as
/// the threshold allows — the point is legibility, not repainting the palette.
const int _kSteps = 24;

/// [tint] nudged toward [ink] until it clears [minRatio] against [background].
///
/// Use for a brand or category colour that has to carry TEXT on a surface it
/// was not chosen against — the case where "it looked fine" and "it measured
/// fine" come apart.
///
/// Returns [tint] unchanged when it already passes, so a colour that was picked
/// correctly is never altered. Otherwise it walks toward [ink] — the theme's
/// own foreground, near-white in dark mode and near-black in light — and
/// returns the FIRST step that clears the bar, which is the smallest change
/// that fixes the problem.
///
/// The walk is monotonic and therefore terminates usefully: moving toward a
/// lighter ink over a dark background only raises contrast, and moving toward a
/// darker ink over a light background does the same. If nothing clears it, [ink]
/// itself is returned — on any real theme that is a token pair the design
/// guard already measures.
///
/// [background] must be OPAQUE. Composite the wash first:
///
///     final fill = Color.alphaBlend(tint.withValues(alpha: 0.12), card);
///     final label = readableOn(tint: tint, background: fill, ink: ink);
Color readableOn({
  required Color tint,
  required Color background,
  required Color ink,
  double minRatio = 4.5,
}) {
  if (contrastRatio(tint, background) >= minRatio) return tint;

  for (var step = 1; step <= _kSteps; step++) {
    final candidate = Color.lerp(tint, ink, step / _kSteps)!;
    if (contrastRatio(candidate, background) >= minRatio) return candidate;
  }
  return ink;
}
