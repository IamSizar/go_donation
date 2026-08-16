// Contrast guard for the community-services category pills.
//
// WHY THIS FILE EXISTS
// test/design/contrast_test.dart guards the design TOKENS, and it is why the
// palette in tokens.dart is trustworthy. It does not guard colours a screen
// defines for itself — and community_services_section.dart defines eight, one
// per service category, each drawn as 11.5px bold text on a 12% wash of itself.
//
// Walking خدمات المجتمع on the simulator and sampling the rendered pixels put
// numbers on it. Raw hue as the label measured:
//
//   dark   blue 4.27:1  terracotta 4.46:1  rose 4.00:1  violet 3.81:1
//          indigo 3.49:1                                  (5 of 8 FAILING)
//   light  amber 2.22:1  teal 2.45:1  green 2.58:1  blue 2.86:1
//          terracotta 2.74:1  rose 3.08:1  violet 3.23:1  indigo 3.53:1
//                                                         (8 of 8 FAILING)
//
// Three of those sit below even the 3.0 floor for non-text UI. 11.5px w700 is
// ordinary body text — WCAG's large-text exemption starts at 18.66px bold — so
// 4.5:1 is the bar, and the pill was under it in twelve of sixteen cases.
//
// This test measures the pill the way it is actually drawn: label against the
// OPAQUE composite of the wash over the card, not against the hue in isolation.
// Measuring the translucent wash is how a pill can look measured without being
// measured.
//
// If a category colour is added to `categoryColor` and this test fails, run the
// label through `categoryPillInk` — do not lower the threshold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';

/// One representative input string per branch of `categoryColor`, plus a value
/// that matches nothing so the default indigo is covered too.
const _categories = <String>[
  'health',
  'education',
  'water',
  'food',
  'shelter',
  'relief',
  'women',
  'asdsa', // matches no branch — the default hue, and real data from the API
];

/// WCAG floor for body text. The pill label is 11.5px w700.
const _kTextFloor = 4.5;

void main() {
  final themes = <String, AppColors>{
    'dark': AppColors.dark,
    'light': AppColors.light,
  };

  group('category pill label is readable on its own wash', () {
    for (final theme in themes.entries) {
      test('every category clears $_kTextFloor:1 in ${theme.key}', () {
        final ink = theme.value.ink;
        final card = theme.value.card;
        final failures = <String>[];

        for (final category in _categories) {
          final tint = categoryColor(category);
          final fill = categoryPillFill(tint, card);
          final label = categoryPillInk(tint, card, ink);
          final ratio = contrastRatio(label, fill);
          if (ratio < _kTextFloor) {
            failures.add('$category ${ratio.toStringAsFixed(2)}:1');
          }
        }

        expect(
          failures,
          isEmpty,
          reason:
              'these pills render text nobody can read in ${theme.key}: '
              '$failures',
        );
      });
    }

    test('a hue that already passes is left exactly as it is', () {
      // The point is legibility, not repainting the palette: a colour chosen
      // correctly must survive untouched, or the fix becomes a redesign.
      const card = Color(0xFF101010);
      const ink = Color(0xFFFFFFFF);
      const bright = Color(0xFFFFFFFF);

      expect(
        categoryPillInk(bright, card, ink),
        bright,
        reason: 'white on a near-black wash is far past the floor already',
      );
    });

    test('the fill stays the raw hue, so categories stay recognisable', () {
      // Only the LABEL is corrected. If the fill drifted too, every category
      // would converge toward the same colour and the coding would be lost.
      final card = AppColors.dark.card;
      for (final category in _categories) {
        final tint = categoryColor(category);
        expect(
          categoryPillFill(tint, card),
          Color.alphaBlend(tint.withValues(alpha: 0.12), card),
          reason: '$category fill must remain the untouched 12% wash',
        );
      }
    });

    test('distinct categories keep distinct pills', () {
      // A fix that made everything readable by making everything the same
      // colour would pass the contrast assertions above and still be wrong.
      final card = AppColors.light.card;
      final ink = AppColors.light.ink;
      final inks = <Color>{
        for (final c in _categories) categoryPillInk(categoryColor(c), card, ink),
      };

      expect(
        inks.length,
        greaterThanOrEqualTo(6),
        reason:
            'the eight categories collapsed to ${inks.length} label colours — '
            'readable, but no longer colour-coded',
      );
    });
  });
}
