// Pins that the gender chips LOOK locked when they ARE locked.
//
// THE BUG
// Gender cannot be changed after sign-up, and the screen says so. The chips
// were correctly inert — onSelected was null — but they were painted with an
// explicit labelStyle, backgroundColor and side, which override the disabled
// treatment Flutter would otherwise apply. So «أنثى» and «آخر» looked exactly
// like live, tappable controls and silently did nothing when tapped.
//
// A control that invites a tap and then ignores it is worse than one that
// looks unavailable: the user cannot tell whether the app is broken, whether
// the tap missed, or whether they are not allowed. The sentence above the
// chips explains the rule, but only to someone who already suspects there is
// a rule to read about.
//
// WHAT IS PINNED
// Being inert (onSelected == null) and looking inert (muted label) are pinned
// separately, because the first was already true while the second was not —
// a test that only checked the first would have passed throughout the bug.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/modules/auth/widgets/gender_choice_chip.dart';

void main() {
  /// Pumps one chip in the given state and returns its rendered label style.
  Future<TextStyle> pumpChip(
    WidgetTester tester, {
    required bool locked,
    required bool selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => GenderChoiceChip(
              label: 'أنثى',
              selected: selected,
              locked: locked,
              onSelected: () {},
            ),
          ),
        ),
      ),
    );
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    return chip.labelStyle!;
  }

  testWidgets('a locked chip is inert', (tester) async {
    await pumpChip(tester, locked: true, selected: false);
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.onSelected, isNull,
        reason: 'a locked chip must not accept a selection');
  });

  testWidgets('an unlocked chip is tappable', (tester) async {
    await pumpChip(tester, locked: false, selected: false);
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.onSelected, isNotNull);
  });

  testWidgets('a locked, unselected chip is painted as unavailable',
      (tester) async {
    final locked = await pumpChip(tester, locked: true, selected: false);
    final live = await pumpChip(tester, locked: false, selected: false);
    expect(locked.color, isNot(equals(live.color)),
        reason: 'a locked chip must not be painted like a tappable one');
  });

  testWidgets('the locked chip holding the actual value stays legible',
      (tester) async {
    // The selected chip is not decoration — it is how the user reads their own
    // recorded gender. Muting it into unreadability to signal "locked" would
    // trade one defect for a worse one.
    final lockedSelected = await pumpChip(tester, locked: true, selected: true);
    final liveSelected = await pumpChip(tester, locked: false, selected: true);
    expect(lockedSelected.color, equals(liveSelected.color),
        reason: 'the recorded value must read the same whether locked or not');
  });
}
