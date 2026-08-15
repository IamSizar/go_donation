// Pins that the circular status badge states its meaning in WORDS, not only
// in colour.
//
// WHY THIS FILE EXISTS
// The badge used to carry its state solely in a Tooltip. A tooltip needs a
// hover or a long press, so on a phone the disc's meaning was its colour and
// nothing else — green/red/amber with a percentage inside. That fails the
// same rule the suite already pins for AppRow, and it fails it for exactly
// the users the rule exists to protect: someone who cannot distinguish the
// three hues has no way to recover the state.
//
// The percentage is not a substitute. It says how far along, not what state
// that counts as; "40%" does not tell you whether that is on track or overdue.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/shared/widgets/operation_status_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Matches a semantics node that CONTAINS [phrase].
///
/// Not an exact match, deliberately. `container: true` merges the percentage
/// Text into the same node, so a partial badge announces something like
/// "Partially received 40%" — which is the desired result, both facts in one
/// utterance. Asserting equality here would fail for the very cases the
/// semantics were added to fix, and would push someone toward "fixing" it by
/// dropping the percentage from the announcement.
Finder _announcing(String phrase) => find.bySemanticsLabel(RegExp(phrase));

void main() {
  group('OperationStatusBadge states its meaning in words', () {
    testWidgets('a fully delivered badge is announced, not just coloured', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const OperationStatusBadge(progress: 1)));
      await tester.pump();

      expect(
        _announcing('Delivered in full'),
        findsOneWidget,
        reason: 'colour and a tick alone cannot convey the state',
      );
    });

    testWidgets('a nothing-received badge is announced', (tester) async {
      await tester.pumpWidget(_wrap(const OperationStatusBadge(progress: 0)));
      await tester.pump();

      expect(_announcing('Not received yet'), findsOneWidget);
    });

    testWidgets('a partial badge is announced, and is not the same as 0 or 1', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const OperationStatusBadge(progress: 0.4)));
      await tester.pump();

      // The distinction that matters: 40% must not read as either extreme.
      expect(_announcing('Partially received'), findsOneWidget);
      expect(_announcing('Delivered in full'), findsNothing);
      expect(_announcing('Not received yet'), findsNothing);
    });

    testWidgets('the percentage is still shown alongside the state', (
      tester,
    ) async {
      // Adding semantics must not cost the number that was already there.
      await tester.pumpWidget(_wrap(const OperationStatusBadge(progress: 0.4)));
      await tester.pump();

      expect(find.text('40%'), findsOneWidget);
    });
  });
}
