// Pins that AppSectionHeader's trailing action is genuinely tappable across a
// full 44pt square — the iOS HIG minimum, and the Android 48dp minimum's floor.
//
// THE BUG
// "See all" is roughly 60x16pt of glyphs. AppPressable already wrapped it in a
// ConstrainedBox(minWidth: 44, minHeight: 44), so the box MEASURED correct —
// but the GestureDetector was nested inside that box's shrink-wrapping Center,
// so it only ever covered the text itself. On device, a tap landing a few
// points above or below the glyphs did nothing at all and the control read as
// broken.
//
// WHY THESE TESTS PROBE THE CORNERS
// A test that taps dead centre passes against the broken build — the centre is
// on the glyph either way. The defect only shows at the EDGES of the declared
// touch target, so that is where these tap. Every header on every screen using
// an `action` was affected, not just the Events hub where it was found.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';

/// Hosts a single header with a trailing action, at a realistic narrow width.
Future<void> pumpHeader(WidgetTester tester, {required VoidCallback onTap}) {
  return tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: AppSectionHeader(
            label: 'Events',
            action: 'See all',
            onActionTap: onTap,
          ),
        ),
      ),
    ),
  );
}

void main() {
  /// The action's pressable, as opposed to any other in the tree.
  Finder actionPressable() => find.byType(AppPressable);

  testWidgets('the action declares at least a 44x44 touch target', (
    tester,
  ) async {
    await pumpHeader(tester, onTap: () {});

    final size = tester.getSize(actionPressable());
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('every corner of that target actually fires the callback', (
    tester,
  ) async {
    var taps = 0;
    await pumpHeader(tester, onTap: () => taps++);

    final rect = tester.getRect(actionPressable());

    // Inset by 2pt so the probes sit inside the declared box rather than on
    // its exact boundary, where hit-testing is legitimately ambiguous.
    const inset = 2.0;
    final probes = <String, Offset>{
      'top-left': rect.topLeft + const Offset(inset, inset),
      'top-right': rect.topRight + const Offset(-inset, inset),
      'bottom-left': rect.bottomLeft + const Offset(inset, -inset),
      'bottom-right': rect.bottomRight + const Offset(-inset, -inset),
      'above the glyphs': Offset(rect.center.dx, rect.top + inset),
      'below the glyphs': Offset(rect.center.dx, rect.bottom - inset),
    };

    for (final probe in probes.entries) {
      taps = 0;
      await tester.tapAt(probe.value);
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason:
            'A tap at the ${probe.key} of the declared 44pt target did not '
            'fire. The touch target is being measured but not hit-tested — '
            'see AppPressable.build, where the gesture handlers must wrap the '
            'padded box rather than sit inside it.',
      );
    }
  });
}
