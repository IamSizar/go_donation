// ConnectRequestSubmitButton — the "Send request" button at the foot of the
// "Ask our team to connect me" sheet (OPOS #25284 Phase 5).
//
// Moved out of connect_request_sheet.dart (OPOS #26344) when that file reached
// the 500-line cap. Behaviour is unchanged: the existing connect-request tests
// still find it by its `connect_request_submit` key.
//
// The button is usable only when there is something to send: disabled and
// dimmed while the trimmed message is blank (rule 5.6: never let a doomed
// request fire), and disabled with a spinner in place of its label while the
// request is in flight — so a second tap cannot send a second request.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// The send button's height — above the 44pt minimum touch target.
const double _submitHeight = 48;

/// The in-button spinner's diameter.
const double _spinnerSize = 20;

/// How faded the send button is while there is nothing to send — the same as
/// the chat-group composer's send button (chat_group_composer.dart).
const double _disabledOpacity = 0.45;

/// The filled primary button. Usable only when there is something to send:
/// disabled and dimmed while the trimmed [message] is blank (rule 5.6), and
/// disabled with a spinner in place of its label while [isSending] — so a
/// second tap cannot send a second request.
class ConnectRequestSubmitButton extends StatelessWidget {
  /// Builds the button for [message]; [onTap] sends it.
  const ConnectRequestSubmitButton({
    super.key,
    required this.message,
    required this.isSending,
    required this.onTap,
  });

  /// The member's message, watched keystroke by keystroke.
  final TextEditingController message;

  /// True while the request is in flight.
  final bool isSending;

  /// Called on tap when there is something to send and nothing in flight.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = 'connect_request_submit'.tr;
    // Rebuilds on every keystroke, so the button enables the moment there is
    // something to send and disables again when the field is cleared — the
    // same pattern as the chat-group composer's send button.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: message,
      builder: (context, draft, _) {
        final canSend = !isSending && draft.text.trim().isNotEmpty;
        return AppPressable(
          key: const Key('connect_request_submit'),
          onTap: canSend ? onTap : null,
          semanticLabel: label,
          expand: true,
          child: Opacity(
            // A sending button stays at full strength: it is busy, not idle.
            opacity: canSend || isSending ? 1 : _disabledOpacity,
            child: _SubmitFace(label: label, isSending: isSending),
          ),
        );
      },
    );
  }
}

/// What the send button draws: the accent fill, with its label — or, while
/// [isSending], a spinner in the label's place.
class _SubmitFace extends StatelessWidget {
  const _SubmitFace({required this.label, required this.isSending});

  /// The already-translated label.
  final String label;

  /// True while the request is in flight.
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final foreground = AppThemeConfig.onAccent(context);
    return Container(
      height: _submitHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context),
        borderRadius: AppRadius.mdAll,
      ),
      child: isSending
          ? SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator.adaptive(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          // Excluded because the button already announces [label]; reading
          // the text too would say it twice.
          : ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppType.body,
                  fontWeight: AppType.wAction,
                  color: foreground,
                ),
              ),
            ),
    );
  }
}
