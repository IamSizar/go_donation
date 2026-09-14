// ConnectRequestSentView — what the "Ask staff to connect me" sheet shows once
// staff have the request (OPOS #25284 Phase 5, OPOS #26331).
//
// WHY IT LIVES INSIDE THE SHEET
// The confirmation used to be a SnackBar on the screen underneath, and the
// member often never saw it: on My Donations the donation's detail sheet stays
// open over that screen and covers it, and on the Messages route toasts were
// found not to paint at all (see supportChatError in messages_screen.dart).
// Replacing the form in place puts the answer where the member is already
// looking, and tells them where to follow the request from here.
//
// Centred, like the app's other whole-area states (AppEmpty in
// app_states.dart): it is a moment to read, not a form to scan. Centring is
// direction-neutral, so it needs no RTL counterpart.
//
// ICON: a Material glyph, like every icon on the screens that open this sheet
// — connect_request_button.dart explains why there is no SF Symbols layer yet.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// The success glyph's size: large enough to read as the state at a glance,
/// small enough that the words stay the main thing.
const double _iconSize = 56;

/// The Done button's height — the same as the send button it replaces, and
/// above the 44pt minimum touch target.
const double _doneHeight = 48;

/// The request went through: a success glyph, what happens next, and Done.
class ConnectRequestSentView extends StatelessWidget {
  /// Builds the view; [onDone] is expected to close the sheet.
  const ConnectRequestSentView({super.key, required this.onDone});

  /// Called when the member taps Done.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Decorative: the title below says the same thing in words, so a
        // screen reader is not told twice.
        ExcludeSemantics(
          child: Icon(
            Icons.check_circle_rounded,
            size: _iconSize,
            color: AppThemeConfig.accent(context),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'connect_request_sent_title'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppType.heading,
            fontWeight: AppType.wLabel,
            color: AppThemeConfig.text(context),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        // Where to follow the request next — the guidance a member needs now
        // that the sheet, and its explainer, are about to close.
        Text(
          'connect_request_sent_body'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppType.body,
            height: AppType.leadBody,
            color: AppThemeConfig.mutedText(context),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        _DoneButton(onTap: onDone),
      ],
    );
  }
}

/// The filled primary button: closing the sheet is the one thing left to do.
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

  /// Closes the sheet.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The app-wide `Done` key, already translated in every language.
    final label = 'Done'.tr;
    return AppPressable(
      key: const Key('connect_request_done'),
      onTap: onTap,
      semanticLabel: label,
      expand: true,
      child: Container(
        height: _doneHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppThemeConfig.accent(context),
          borderRadius: AppRadius.mdAll,
        ),
        // Excluded because the button already announces [label]; reading the
        // text too would say it twice.
        child: ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppType.body,
              fontWeight: AppType.wAction,
              color: AppThemeConfig.onAccent(context),
            ),
          ),
        ),
      ),
    );
  }
}
