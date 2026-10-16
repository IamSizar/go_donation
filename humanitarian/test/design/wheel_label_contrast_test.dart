// Contrast guard for عجلة الحظ's slice labels.
//
// WHY THIS FILE EXISTS
// The slice labels once sat in white on an eight-colour rainbow and four of
// eight measured under 4.5:1 (amber was 2.15:1). The fix picked the ink per
// slice. R2 #46 then replaced the rainbow with the brand's four tones; the
// per-slice ink rule still applies, and this file pins both: every label
// readable, and the palette is the brand one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/data/motivational_tasks.dart';
import 'package:flutter_application_1/modules/dashboard/screens/wheel_of_fortune_screen.dart';

/// WCAG floor for body text. Slice labels are 12px w800 — nowhere near the
/// 18.66px-bold threshold where the 3:1 large-text allowance starts.
const _kTextFloor = 4.5;

void main() {
  group('every slice label is readable on its slice', () {
    test('all eight clear $_kTextFloor:1', () {
      final failures = <String>[];

      for (final slice in wheelSliceColors) {
        final ratio = contrastRatio(wheelLabelInk(slice), slice);
        if (ratio < _kTextFloor) {
          final hex = slice.toARGB32().toRadixString(16).padLeft(8, '0');
          failures.add('#$hex ${ratio.toStringAsFixed(2)}:1');
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'slices carrying unreadable labels: $failures',
      );
    });

    test('the dark slices keep white, the light ones take the dark ink', () {
      // R2 #46 palette: deep green and teal carry white; ivory and mint need
      // the dark ink. A "fix" that flipped everything one way would fail one
      // half of this.
      const deepGreen = Color(0xFF2F5D4A);
      const teal = Color(0xFF1F6F8B);
      const ivory = Color(0xFFF3EFE4);
      const mint = Color(0xFF6FBF9C);

      for (final slice in [deepGreen, teal]) {
        expect(wheelLabelInk(slice), Colors.white);
      }
      for (final slice in [ivory, mint]) {
        expect(wheelLabelInk(slice), isNot(Colors.white));
      }
    });
  });

  group('the wheel uses the brand palette', () {
    test('only the four brand tones', () {
      // R2 #46 — the client called the eight-colour rainbow amateur; the
      // wheel moved to the brand's own tones on purpose. Changing it again
      // should break here so it is decided, not drifted into.
      final brand = <Color>{
        Color(0xFF2F5D4A),
        Color(0xFFF3EFE4),
        Color(0xFF1F6F8B),
        Color(0xFF6FBF9C),
      };
      expect(wheelSliceColors.toSet(), brand);
    });

    test('no two neighbouring slices share a colour', () {
      // With four tones over eight slices, the order is what keeps every
      // slice distinct — including the wrap from the last back to the first.
      for (var i = 0; i < wheelSliceColors.length; i++) {
        final next = wheelSliceColors[(i + 1) % wheelSliceColors.length];
        expect(wheelSliceColors[i], isNot(next), reason: 'slices $i and next');
      }
    });

    test('there is a colour for every slice the wheel actually draws', () {
      // The painter indexes colours with `i % colors.length`, so a mismatch
      // does not crash — it silently repeats a hue and puts two identical
      // slices side by side.
      expect(
        wheelSliceColors.length,
        motivationalTasks.length,
        reason:
            '${motivationalTasks.length} slices but ${wheelSliceColors.length} '
            'colours — the wheel would repeat a hue',
      );
      expect(
        motivationalTaskShortLabels.length,
        motivationalTasks.length,
        reason: 'every slice needs its own short label',
      );
    });
  });
}
