// Pins that a confirmation dialog is native on both platforms.
//
// THE BUG
// Fourteen dialogs used showDialog + AlertDialog + TextButton, which shows an
// iPhone user a Material dialog. Three other call sites already used the
// adaptive form, so the app contradicted itself.
//
// WHY THE ACTIONS ARE ASSERTED SEPARATELY FROM THE DIALOG
// AlertDialog.adaptive gives a CupertinoAlertDialog on iOS, but its actions are
// whatever the caller passes — a TextButton inside a Cupertino dialog is the
// right shape with the wrong contents. A test that only checked for
// CupertinoAlertDialog would pass while the buttons stayed Material, so both
// are pinned.
//
// Run under BOTH platform targets, per the house rule for adaptive components.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';

void main() {
  /// Opens a confirm dialog on [platform] and leaves it on screen.
  Future<void> openConfirm(WidgetTester tester, TargetPlatform platform) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAdaptiveConfirm(
                  context,
                  title: 'Log out?',
                  message: 'Are you sure?',
                  confirmLabel: 'Log out',
                  cancelLabel: 'Cancel',
                  isDestructive: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('iOS gets a Cupertino dialog with Cupertino actions',
      (tester) async {
    await openConfirm(tester, TargetPlatform.iOS);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsNWidgets(2));
    expect(find.byType(TextButton), findsNothing,
        reason: 'a Material button inside a Cupertino dialog is still Material');
  });

  testWidgets('Android gets a Material dialog with Material actions',
      (tester) async {
    await openConfirm(tester, TargetPlatform.android);

    // Asserted on the observable presentation rather than the AlertDialog
    // widget type: AlertDialog.adaptive does not leave an AlertDialog element
    // in the tree on Android, so a type assertion would fail while the user
    // was in fact getting the correct Material dialog.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(2));
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byType(CupertinoDialogAction), findsNothing);
  });

  testWidgets('cancel comes before the affirmative action on both platforms',
      (tester) async {
    // Order is the contract: iOS reads it as cancel-left/action-right, and
    // Material puts the affirmative last. One order satisfies both, but only
    // if it is actually this one.
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      await openConfirm(tester, platform);
      final cancel = tester.getTopLeft(find.text('Cancel'));
      final confirm = tester.getTopLeft(find.text('Log out'));
      expect(cancel.dx < confirm.dx || cancel.dy < confirm.dy, isTrue,
          reason: 'on $platform cancel must not come after the action');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('dismissing without choosing counts as "no"', (tester) async {
    // The caller treats the result as "did the user actually agree", so a
    // barrier tap must never read as consent.
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showAdaptiveConfirm(
                    context,
                    title: 'Delete?',
                    message: 'This cannot be undone.',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    isDestructive: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(CupertinoAlertDialog))).pop();
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });
}
