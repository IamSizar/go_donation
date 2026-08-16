// Contrast guard for عجلة الحظ's slice labels.
//
// WHY THIS FILE EXISTS
// The wheel is the one screen that leaves the app's single-accent palette, and
// that is defended: a fortune wheel's segment colours are what make it read as
// a wheel, and eight tints of the brand green would be eight slices nobody
// could tell apart. The rainbow stays.
//
// What did not survive review is what was written ON it. Every label was white,
// and white does not work on a rainbow. Measured from the rendered pixels on an
// iPhone 17 Pro simulator:
//
//   amber  #F59E0B  2.15:1     green  #16A34A  3.30:1
//   orange #EA580C  3.56:1     cyan   #0891B2  3.68:1
//
// Four of eight slices, and the amber one below even the 3:1 floor that applies
// to non-text UI — this is 12px bold text, which needs 4.5:1. The drop shadow
// under the labels is a perceptual nicety; WCAG gives it no credit, and at
// 2.15:1 it was not rescuing anything.
//
// So the fix picks the INK per slice instead of repainting the wheel. This test
// pins both halves of that bargain: every label readable, every hue untouched.
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

    test('the four that white could not carry now use the dark ink', () {
      // Named explicitly so a palette edit that quietly re-breaks one of them
      // fails here with the specific slice, not just a count.
      const amber = Color(0xFFF59E0B);
      const green = Color(0xFF16A34A);
      const orange = Color(0xFFEA580C);
      const cyan = Color(0xFF0891B2);

      for (final slice in [amber, green, orange, cyan]) {
        expect(
          wheelLabelInk(slice),
          isNot(Colors.white),
          reason: 'white measured under the floor on this slice',
        );
      }
    });

    test('the dark slices keep white, rather than flipping everything', () {
      // A "fix" that made every label dark would pass the contrast assertion
      // and destroy the deep-green and indigo slices instead.
      const deepGreen = Color(0xFF2F5D4A);
      const indigo = Color(0xFF4F46E5);

      for (final slice in [deepGreen, indigo]) {
        expect(wheelLabelInk(slice), Colors.white);
      }
    });
  });

  group('the wheel keeps its own palette', () {
    test('the eight hues are untouched by the label fix', () {
      // The rainbow is the deliberate exception. If a future change "aligns"
      // it with the accent, that is a product decision and should break here
      // so it is made on purpose rather than by drift.
      expect(wheelSliceColors, const [
        Color(0xFF2F5D4A),
        Color(0xFFF59E0B),
        Color(0xFFDB2777),
        Color(0xFF4F46E5),
        Color(0xFF16A34A),
        Color(0xFFDC2626),
        Color(0xFF0891B2),
        Color(0xFFEA580C),
      ]);
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
