// One place that knows how a dialog should look on each platform.
//
// WHY THIS EXISTS
// Fourteen dialogs across eleven files were built with showDialog + AlertDialog
// + TextButton, which puts a Material dialog in front of an iPhone user: square
// corners, Material typography, and Material button placement. Section 3.1 of
// the house rules asks for exactly the opposite — Cupertino on iOS, Material on
// Android, behind a single wrapper — and three call sites already did it right,
// so the app disagreed with itself.
//
// WHAT SWAPPING THE CONSTRUCTOR ALONE WOULD MISS
// AlertDialog.adaptive renders a CupertinoAlertDialog on iOS, but its ACTIONS
// are whatever you hand it. A TextButton inside a Cupertino dialog is still a
// Material button — right shape, wrong contents. The buttons have to adapt too,
// which is why [adaptiveDialogAction] exists rather than callers passing
// TextButtons directly.
//
// BUTTON ORDER is deliberately the same on both platforms: cancel first, then
// the affirmative action. iOS reads that as cancel-left/action-right, and
// Material lays it out with the affirmative at the end — the conventions agree
// here, so one order satisfies both (Section 3.1).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A dialog button that is a [CupertinoDialogAction] on iOS and a [TextButton]
/// elsewhere.
///
/// [isDestructive] paints the label in the platform's destructive colour —
/// iOS's own red on Cupertino, the passed [destructiveColor] on Material — so a
/// "delete" reads as dangerous in both places.
Widget adaptiveDialogAction(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool isDefault = false,
  bool isDestructive = false,
  Color? destructiveColor,
}) {
  final isApple = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };

  if (isApple) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDefaultAction: isDefault,
      isDestructiveAction: isDestructive,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    style: isDestructive && destructiveColor != null
        ? TextButton.styleFrom(foregroundColor: destructiveColor)
        : null,
    child: Text(label),
  );
}

/// Asks the user to confirm something, in the idiom of the platform they are on.
///
/// Returns true only if they chose the affirmative action; dismissing the dialog
/// by any other means returns false, so a caller can treat the result as "did
/// the user actually agree".
///
/// All four labels are taken already-translated, so this file never needs to
/// know which keys a caller uses.
Future<bool> showAdaptiveConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool isDestructive = false,
  Color? destructiveColor,
}) async {
  final result = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [
        adaptiveDialogAction(
          ctx,
          label: cancelLabel,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        adaptiveDialogAction(
          ctx,
          label: confirmLabel,
          onPressed: () => Navigator.of(ctx).pop(true),
          isDefault: !isDestructive,
          isDestructive: isDestructive,
          destructiveColor: destructiveColor,
        ),
      ],
    ),
  );
  return result ?? false;
}
