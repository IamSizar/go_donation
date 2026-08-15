// Behavioural tests for AppPressable.
//
// The claim being tested is specific: the widget must react to the finger
// LANDING, not to it lifting. The audit found zero onTapDown handlers in the
// app, so "responds on press" is the single behaviour worth pinning — if it
// regresses to release-only feedback these tests fail.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// Reads the horizontal scale currently applied by the widget's Transform.
///
/// Returns 1.0 when at rest. Reads what is actually painted rather than any
/// internal state.
///
/// NOTE: deliberately reads entry(0, 0) — the X scale — rather than
/// `getMaxScaleOnAxis()`. `Transform.scale` builds a matrix that scales X and
/// Y but leaves Z at 1.0, and `getMaxScaleOnAxis` returns the MAXIMUM of the
/// three, so it reports 1.0 for every press and the assertion silently never
/// fires. That mistake cost an hour; don't reintroduce it.
double _currentScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(AppPressable),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.entry(0, 0);
}

Widget _host(Widget child, {bool reduceMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

void main() {
  group('press responds on pointer-down, not release', () {
    testWidgets('scale shrinks while held and recovers after release', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppPressable(
            onTap: () {},
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );

      expect(_currentScale(tester), closeTo(1.0, 0.001));

      // Finger DOWN, and nothing else. No release.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppPressable)),
      );
      await tester.pump(); // one frame — this is the whole point
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        _currentScale(tester),
        lessThan(1.0),
        reason:
            'The press must be visible while the finger is still down. '
            'If this fails, feedback has regressed to release-only.',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_currentScale(tester), closeTo(1.0, 0.01));
    });

    testWidgets('dragging off before release cancels the press', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppPressable(
            onTap: () {},
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppPressable)),
      );
      // The bare pump is required: it is the frame on which the ticker
      // registers its start time. Advancing the clock on the very first pump
      // would elapse zero ticker-time and the spring would not have moved.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_currentScale(tester), lessThan(1.0));

      // Slide well away, then lift — this must cancel, not fire.
      await gesture.moveBy(const Offset(0, 400));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_currentScale(tester), closeTo(1.0, 0.01));
    });

    testWidgets('onTap fires once on a completed tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          AppPressable(
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );

      await tester.tap(find.byType(AppPressable));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('Reduce Motion', () {
    testWidgets('uses opacity instead of scale when animations are off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppPressable(
            onTap: () {},
            child: const SizedBox(width: 120, height: 48),
          ),
          reduceMotion: true,
        ),
      );

      // No Transform is built at all on this path.
      expect(
        find.descendant(
          of: find.byType(AppPressable),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppPressable)),
      );
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AppPressable),
          matching: find.byType(Opacity),
        ),
      );
      expect(
        opacity.opacity,
        lessThan(1.0),
        reason: 'Reduce Motion still needs feedback — just non-vestibular.',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('touch target and semantics', () {
    testWidgets('a small child still gets a 44pt tappable square', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppPressable(
            onTap: () {},
            child: const SizedBox(width: 16, height: 16),
          ),
        ),
      );

      final size = tester.getSize(find.byType(AppPressable));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('exposes itself as a labelled button to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          AppPressable(
            onTap: () {},
            semanticLabel: 'Give now',
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );

      // The label must be reachable by assistive technology. The audit found
      // 29 IconButtons in the app and only 10 carrying any label at all, so
      // an icon-only control announcing as "button" with no name is the exact
      // failure this guards.
      expect(find.bySemanticsLabel('Give now'), findsOneWidget);

      final data = tester
          .getSemantics(find.bySemanticsLabel('Give now'))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      handle.dispose();
    });

    testWidgets('a null onTap renders inert with no press animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const AppPressable(child: SizedBox(width: 120, height: 48))),
      );

      expect(
        find.descendant(
          of: find.byType(AppPressable),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });
}
