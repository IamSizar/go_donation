// Contrast guard for the volunteer skill picker's seven category colours.
//
// WHY THIS FILE EXISTS
// test/design/contrast_test.dart guards the design TOKENS. It is why the
// palette in tokens.dart is trustworthy, and it is also why it caught nothing
// here: skill_chip_picker.dart hardcodes seven hues of its own, and a literal
// inside a widget file is outside everything that measures.
//
// The screen it draws is behind the volunteer role (طلب التطوع → اختر مهاراتك),
// which is why the sweep that found the community-services pills and the
// wheel-of-fortune labels never reached it — until today nobody had signed in
// as a volunteer to look.
//
// Measured against the real composite (the hue's own 6% wash over the surface
// beneath it), the raw hue as label text measured:
//
//   dark    brand 2.33  field 2.49  transport 2.79  office 3.08  medical 3.65
//           (5 of 7 FAILING; trades 4.84 and teaching 5.17 passed)
//   light   teaching 2.82  trades 3.03  medical 4.02
//           (3 of 7 FAILING)
//
// and white on the SELECTED pill's solid accent measured 3.56 on trades orange
// and 3.30 on teaching green — a failure independent of theme, since the fill
// is the same in both.
//
// This test measures the chip the way it is actually drawn: ink against the
// OPAQUE composite, not against the hue in isolation. Measuring the
// translucent wash is how a chip can look measured without being measured.
//
// If a hue is added to `_categoryStyle` and this fails, route its ink through
// the helpers below — do not lower a threshold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/modules/support/widgets/skill_chip_picker.dart';

/// WCAG floor for body text. The chip label is 13px w500, the category
/// heading 15px w700, the preview chip 12px w600 — all ordinary body text,
/// since the large-text exemption starts at 18.66px bold.
const _kTextFloor = 4.5;

/// WCAG floor for meaningful non-text UI: the header glyph and the ✕ button.
const _kUiFloor = 3.0;

void main() {
  final themes = <String, AppColors>{
    'dark': AppColors.dark,
    'light': AppColors.light,
  };

  group('skill picker ink is readable on the category hues', () {
    test('the catalogue still has all seven styled categories', () {
      // If a category is added and left unstyled it falls back to the theme
      // primary at runtime, which is readable but colourless — worth knowing.
      expect(skillCategoryAccents.length, 7);
    });

    for (final theme in themes.entries) {
      // Both surfaces a category card is really drawn on: the sheet paints
      // scaffoldBackgroundColor (ground), the inline picker sits in a
      // GlassPanel (card).
      final surfaces = <String, Color>{
        'ground': theme.value.ground,
        'card': theme.value.card,
      };

      for (final surface in surfaces.entries) {
        test('heading + unselected chip clear $_kTextFloor:1 on '
            '${surface.key} in ${theme.key}', () {
          final failures = <String>[];
          for (final entry in skillCategoryAccents.entries) {
            final accent = entry.value;
            final fill = skillCategoryFill(accent, surface.value);
            final ratio = contrastRatio(
              skillCategoryInk(accent, surface.value, theme.value.ink),
              fill,
            );
            if (ratio < _kTextFloor) {
              failures.add('${entry.key} ${ratio.toStringAsFixed(2)}:1');
            }
          }
          expect(
            failures,
            isEmpty,
            reason:
                'these categories render text nobody can read on '
                '${surface.key} in ${theme.key}: $failures',
          );
        });

        test(
          'header glyph clears $_kUiFloor:1 on ${surface.key} in ${theme.key}',
          () {
            final failures = <String>[];
            for (final entry in skillCategoryAccents.entries) {
              final accent = entry.value;
              final tile = Color.alphaBlend(
                accent.withValues(alpha: 0.14),
                skillCategoryFill(accent, surface.value),
              );
              final ratio = contrastRatio(
                skillCategoryIconInk(accent, surface.value, theme.value.ink),
                tile,
              );
              if (ratio < _kUiFloor) {
                failures.add('${entry.key} ${ratio.toStringAsFixed(2)}:1');
              }
            }
            expect(failures, isEmpty, reason: 'invisible glyphs: $failures');
          },
        );
      }

      test('preview chip label clears $_kTextFloor:1 in ${theme.key}', () {
        final card = theme.value.card;
        final failures = <String>[];
        for (final entry in skillCategoryAccents.entries) {
          final accent = entry.value;
          final ratio = contrastRatio(
            skillPreviewInk(accent, card, theme.value.ink),
            skillPreviewFill(accent, card),
          );
          if (ratio < _kTextFloor) {
            failures.add('${entry.key} ${ratio.toStringAsFixed(2)}:1');
          }
        }
        expect(
          failures,
          isEmpty,
          reason: 'unreadable preview chips: $failures',
        );
      });

      test('preview chip ✕ clears $_kUiFloor:1 in ${theme.key}', () {
        final card = theme.value.card;
        final failures = <String>[];
        for (final entry in skillCategoryAccents.entries) {
          final accent = entry.value;
          final ratio = contrastRatio(
            skillPreviewRemoveInk(accent, card, theme.value.ink),
            skillPreviewFill(accent, card),
          );
          if (ratio < _kUiFloor) {
            failures.add('${entry.key} ${ratio.toStringAsFixed(2)}:1');
          }
        }
        expect(
          failures,
          isEmpty,
          reason:
              'the only affordance for removing a skill is invisible: '
              '$failures',
        );
      });
    }

    test('selected chip ink clears $_kTextFloor:1 on every solid hue', () {
      // Theme-independent: the selected fill is the raw accent in both.
      final failures = <String>[];
      for (final entry in skillCategoryAccents.entries) {
        final accent = entry.value;
        final ratio = contrastRatio(skillSelectedInk(accent), accent);
        if (ratio < _kTextFloor) {
          failures.add('${entry.key} ${ratio.toStringAsFixed(2)}:1');
        }
      }
      expect(
        failures,
        isEmpty,
        reason: 'selected pills nobody can read: $failures',
      );
    });

    test('white is kept wherever white already won', () {
      // The point is legibility, not repainting: hues where white was already
      // the right answer must not be flipped to dark ink.
      expect(
        skillSelectedInk(skillCategoryAccents['transport']!),
        Colors.white,
      );
      expect(skillSelectedInk(skillCategoryAccents['service']!), Colors.white);
    });

    test('a hue that already passes is left exactly as it is', () {
      const surface = Color(0xFF101010);
      const ink = Color(0xFFFFFFFF);
      const bright = Color(0xFFFFFFFF);
      expect(
        skillCategoryInk(bright, surface, ink),
        bright,
        reason: 'white on a near-black wash is far past the floor already',
      );
    });

    test('the fills stay the raw hue, so categories stay recognisable', () {
      // Only the INK is corrected. If the fills drifted the seven categories
      // would converge and the colour coding — the whole point — would be lost.
      final surface = AppColors.dark.ground;
      for (final entry in skillCategoryAccents.entries) {
        expect(
          skillCategoryFill(entry.value, surface),
          Color.alphaBlend(entry.value.withValues(alpha: 0.06), surface),
          reason: '${entry.key} fill must remain the untouched 6% wash',
        );
      }
    });

    test('distinct categories keep distinct inks', () {
      // A fix that made everything readable by making everything one colour
      // would pass every assertion above and still be wrong.
      final surface = AppColors.dark.ground;
      final ink = AppColors.dark.ink;
      final inks = <Color>{
        for (final accent in skillCategoryAccents.values)
          skillCategoryInk(accent, surface, ink),
      };
      expect(
        inks.length,
        greaterThanOrEqualTo(6),
        reason:
            'the seven categories collapsed to ${inks.length} label colours — '
            'readable, but no longer colour-coded',
      );
    });
  });
}
