import 'package:flutter/material.dart';

/// Wraps its [child] so tapping any empty area dismisses the on-screen
/// keyboard — app-wide. It is installed once at the root (GetMaterialApp's
/// `builder`) so every route inherits the behaviour without per-screen wiring.
///
/// Why it doesn't break the rest of the UI:
///   * `HitTestBehavior.translucent` + an `onTap`-only detector means the
///     gesture arena still lets buttons, `InkWell`s, links, list-row taps and
///     scroll/drag gestures win their own gestures — this detector only fires
///     for taps that nothing else claims (i.e. empty space).
///   * The unfocus is guarded on `hasFocus`, so it's a no-op when no text
///     field is focused.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final FocusNode? focus = FocusManager.instance.primaryFocus;
        if (focus != null && focus.hasFocus) {
          focus.unfocus();
        }
      },
      child: child,
    );
  }
}
