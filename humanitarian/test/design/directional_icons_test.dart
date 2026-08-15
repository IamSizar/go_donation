// Tests for AppIcons.
//
// These exist because of a specific mistake that is easy to make and almost
// impossible to see in code review: some Material icons carry
// `matchTextDirection: true` and are mirrored by Flutter under RTL, and some
// do not. Swapping a self-mirroring icon by hand double-mirrors it, so it
// points the WRONG way — which is worse than doing nothing, and looks correct
// in the LTR build everyone develops in.
//
// Three of this app's four languages are right-to-left, so getting this
// backwards affects the majority of its users.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/directional_icons.dart';

/// Resolves [pick] under the given text direction.
Future<IconData> _under(
  WidgetTester tester,
  TextDirection direction,
  IconData Function(BuildContext) pick,
) async {
  late IconData resolved;
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: Builder(
        builder: (context) {
          resolved = pick(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  group('every accessor relies on Flutter mirroring, never a manual swap', () {
    // If any of these starts returning a different glyph per direction, it is
    // being double-mirrored and now points the wrong way.
    // ALL of them. Verified against the real IconData at runtime: every
    // arrow and chevron this app uses carries matchTextDirection.
    final selfMirroring = <String, IconData Function(BuildContext)>{
      'forward': AppIcons.forward,
      'forwardSolid': AppIcons.forwardSolid,
      'back': AppIcons.back,
      'backSolid': AppIcons.backSolid,
      'chevronForward': AppIcons.chevronForward,
    };

    selfMirroring.forEach((name, pick) {
      testWidgets('$name resolves to one glyph in both directions', (
        tester,
      ) async {
        final ltr = await _under(tester, TextDirection.ltr, pick);
        final rtl = await _under(tester, TextDirection.rtl, pick);

        expect(
          ltr.matchTextDirection,
          isTrue,
          reason:
              '$name relies on Flutter mirroring it. If the underlying '
              'icon no longer carries matchTextDirection, this accessor must '
              'start branching on direction instead.',
        );
        expect(
          rtl,
          ltr,
          reason:
              '$name must return the SAME icon in both directions — '
              'Flutter already mirrors it. Branching here cancels that out '
              'and points the arrow backwards in Arabic and Kurdish.',
        );
      });
    });
  });

  testWidgets('forward and back are opposites', (tester) async {
    final forward = await _under(tester, TextDirection.ltr, AppIcons.forward);
    final back = await _under(tester, TextDirection.ltr, AppIcons.back);
    expect(forward, isNot(back));
  });
}
