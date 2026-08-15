// The one way an auth screen reports a failure the user can retype their way
// out of — a wrong code, a malformed phone number, a refused password.
//
// WHY THIS FILE EXISTS (E4)
// Three screens in the same flow each grew their own version of this line, and
// they disagreed. The sign-in screen used the themed `consequence` token and
// measured 7.4:1 on its card; the OTP screen and the registration form both
// hardcoded `Colors.redAccent`, which measures 3.19:1 on the same surface —
// under the 4.5:1 AA floor, and unreadable against a dark card because a fixed
// red cannot suit both themes.
//
// A hardcoded colour is invisible to a palette guard by definition, so
// `test/design/contrast_test.dart` could never have caught it. Having exactly
// one widget carry this line is what makes it catchable at all: there is now a
// single place where the colour is chosen, and a test reads it back off the
// rendered OTP screen.
//
// NOT AN ERROR *STATE*
// `AppErrorState` (core/widgets/app_states.dart) is the four-state widget for a
// failed async region — an illustration, a message and a Retry. This is the
// other kind of error from section 5.7: a field-level message about what the
// user just typed, where the retry is the form itself. Reaching for the big one
// here would put a Retry button next to a form whose submit button is the
// retry.
import 'package:flutter/material.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';

/// A single inline error line: a warning glyph and the message beside it.
///
/// [message] is expected to be already localized — every caller pulls it from
/// `LoginController.errorMessage`, which is written through `.tr`.
///
/// Renders nothing at all when [message] is empty, so callers can hand it the
/// observable directly instead of each repeating the same `isNotEmpty` guard.
class AuthInlineError extends StatelessWidget {
  const AuthInlineError({
    super.key,
    required this.message,
    this.padding = const EdgeInsets.only(top: 12),
  });

  final String message;

  /// Where the gap goes relative to the neighbouring control.
  ///
  /// A parameter rather than a fixed value because the sign-in screen puts the
  /// error ABOVE the field it refers to and the OTP screen puts it below —
  /// so the breathing room belongs on opposite sides. The padding is inside
  /// the widget rather than around it at the call site so that an empty
  /// message collapses to nothing at all, gap included.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();

    // The token, never a literal: `consequence` is the only red the contrast
    // suite measures, and it is defined separately for light and dark.
    final colour = AppThemeConfig.consequence(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The glyph is what makes the state readable without colour vision;
          // red text alone says "error" only to people who can see the red.
          Icon(Icons.error_outline_rounded, size: 18, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colour, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
