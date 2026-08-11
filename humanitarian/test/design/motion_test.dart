// Tests for the motion tokens and the Reduce Motion switch.
//
// The audit found MediaQuery.disableAnimations was never read anywhere in the
// app, so a user with Reduce Motion enabled at the OS level still got the full
// animation set — including four easeOutBack overshoots, which is exactly the
// vestibular-trigger shape the setting exists to suppress.
//
// These tests pin the switch itself. They are worth more than a simulator
// check: `xcrun simctl defaults write com.apple.Accessibility
// ReduceMotionEnabled 1` writes into the device container but accessibilityd
// does not re-read it, so a running Flutter app never observes the change and
// an on-device check of this behaviour is inconclusive either way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/motion.dart';

/// Pumps [builder] under a MediaQuery with animations on or off, and hands
/// back whatever the builder resolved.
Future<T> _resolvedUnder<T>(
  WidgetTester tester, {
  required bool reduced,
  required T Function(BuildContext) builder,
}) async {
  late T captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Builder(
        builder: (context) {
          captured = builder(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('AppMotion.reduced reads the OS setting', () {
    testWidgets('false when animations are enabled', (tester) async {
      final r = await _resolvedUnder(
        tester,
        reduced: false,
        builder: AppMotion.reduced,
      );
      expect(r, isFalse);
    });

    testWidgets('true when animations are disabled', (tester) async {
      final r = await _resolvedUnder(
        tester,
        reduced: true,
        builder: AppMotion.reduced,
      );
      expect(r, isTrue);
    });
  });

  group('durations collapse under Reduce Motion', () {
    testWidgets('a normal build keeps the token duration', (tester) async {
      final d = await _resolvedUnder(
        tester,
        reduced: false,
        builder: (c) => AppMotion.resolve(c, AppMotion.settleDuration),
      );
      expect(d, AppMotion.settleDuration);
    });

    testWidgets('Reduce Motion collapses it to zero', (tester) async {
      final d = await _resolvedUnder(
        tester,
        reduced: true,
        builder: (c) => AppMotion.resolve(c, AppMotion.settleDuration),
      );
      expect(
        d,
        Duration.zero,
        reason:
            'Every implicit animation routes its duration through '
            'resolve(); if this stops collapsing, all 16 of them start '
            'animating again for users who asked them not to.',
      );
    });
  });

  group('overshoot curves are flattened', () {
    testWidgets('a normal build keeps the overshoot', (tester) async {
      final c = await _resolvedUnder(
        tester,
        reduced: false,
        builder: (ctx) => AppMotion.resolveCurve(ctx, Curves.easeOutBack),
      );
      expect(c, Curves.easeOutBack);
    });

    testWidgets('Reduce Motion replaces it with a flat curve', (tester) async {
      final c = await _resolvedUnder(
        tester,
        reduced: true,
        builder: (ctx) => AppMotion.resolveCurve(ctx, Curves.easeOutBack),
      );
      expect(
        c,
        Curves.linear,
        reason:
            'easeOutBack overshoots past its target and springs back — '
            'the specific motion Reduce Motion exists to suppress.',
      );
    });
  });

  group('spring presets', () {
    test('snap and settle are critically damped, carry alone bounces', () {
      // A control that wobbles after you press it feels cheap; bounce is only
      // honest when the user's own gesture put the energy there.
      expect(AppMotion.snap.dampingRatio, 1.0);
      expect(AppMotion.settle.dampingRatio, 1.0);
      expect(AppMotion.carry.dampingRatio, lessThan(1.0));
    });

    test('a tap settles faster than a presentation', () {
      expect(AppMotion.snap.response, lessThan(AppMotion.settle.response));
    });

    test('a simulation actually converges on its target', () {
      final sim = AppMotion.settle.simulate(from: 0, to: 1);
      expect(sim.x(0), closeTo(0, 0.001));
      // Two seconds is far past the 0.4s response; it must be done by then.
      expect(sim.x(2.0), closeTo(1, 0.01));
      expect(sim.isDone(2.0), isTrue);
    });

    test('release velocity is carried into the simulation', () {
      final atRest = AppMotion.carry.simulate(from: 0, to: 1);
      final flicked = AppMotion.carry.simulate(from: 0, to: 1, velocity: 5);
      // Same start, same target — the flicked one must be further along early,
      // which is what removes the seam between a drag and the animation that
      // follows it.
      expect(flicked.x(0.05), greaterThan(atRest.x(0.05)));
    });
  });
}
