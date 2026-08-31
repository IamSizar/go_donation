// The one place a dashboard tab's top/bottom insets get stripped, correctly.
//
// WHY THIS FILE EXISTS
// dashboard_screen.dart used to inline this as
// `MediaQuery.removePadding(context: context, ...)`, called with the
// SURROUNDING build method's own `context` — the State's element, which
// sits ABOVE the Scaffold being built in that same method. `MediaQuery.of`
// on that context reads the app-root MediaQuery, not the Scaffold body's
// own MediaQuery (where `resizeToAvoidBottomInset` already strips
// `viewInsets.bottom`). `removePadding` only ever touches padding, so the
// raw, un-stripped keyboard inset rode straight through to every tab, whose
// own nested Scaffold (kept for standalone-route reuse) then subtracted the
// SAME keyboard height a second time — crushing the active tab to a sliver
// the moment its keyboard opened. On Marketplace this read as "a blank box
// covers everything" the instant the search field was tapped.
//
// Pulling the `Builder` out into its own named widget does two things a
// bare inline `Builder` in dashboard_screen.dart could not: it makes the
// context boundary the fix depends on impossible to "simplify away" without
// deleting a widget with this file's name attached, and it lets
// marketplace_embedded_keyboard_test.dart pump the SAME class
// DashboardScreen uses, rather than a hand-copied stand-in — so reverting
// this widget's `Builder` is what makes that test fail, not reverting a
// private copy inside the test file.
import 'package:flutter/widgets.dart';

/// Wraps [child] in `MediaQuery.removePadding`, using a context obtained
/// from INSIDE the ancestor Scaffold's body rather than whatever `context`
/// the caller happens to be building with.
///
/// [removeTop] strips the status-bar padding a persistent top bar above this
/// widget already reserves. [removeBottom] strips the home-indicator padding
/// a persistent bottom nav bar below this widget already reserves. Neither
/// touches `viewInsets` (the keyboard) — that is left for the ancestor
/// Scaffold's own `resizeToAvoidBottomInset` to handle exactly once, which is
/// only true if this widget's `Builder` reads a context inside that
/// Scaffold's body. See the file header for what goes wrong otherwise.
class KeyboardSafeTabBody extends StatelessWidget {
  const KeyboardSafeTabBody({
    super.key,
    required this.child,
    this.removeTop = true,
    this.removeBottom = true,
  });

  final Widget child;
  final bool removeTop;
  final bool removeBottom;

  @override
  Widget build(BuildContext context) {
    // The Builder is load-bearing: it is what gives `MediaQuery.of` below a
    // context genuinely inside the ancestor Scaffold's body, instead of the
    // context of whatever widget constructed this one.
    return Builder(
      builder: (innerContext) => MediaQuery.removePadding(
        context: innerContext,
        removeTop: removeTop,
        removeBottom: removeBottom,
        child: child,
      ),
    );
  }
}
