// ChatGroupComposer — the message box and send button at the foot of a
// chat-group conversation (OPOS #25284 Phase 5).
//
// Presentation only: it owns no send logic. ChatGroupConversationScreen hands
// it the draft's controller, what to do on send, and whether a send is in
// flight.
//
// The send button is usable only when there is something to send: it is
// disabled — dimmed, and announced as disabled to screen readers — while the
// draft is blank (rule 5.6: never let a doomed request fire) and while a send
// is in flight, when a spinner replaces its icon so a second tap cannot send
// the same message twice.
//
// No length limit is enforced here because the server enforces none: the
// chat-group send route rejects only an empty body.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:get/get.dart';

/// The send button's diameter — the same as the 1:1 chat's, and above the
/// 44pt minimum touch target.
const double _sendButtonSize = 46;

/// The send glyph's size inside the button.
const double _sendIconSize = 20;

/// The Material spinner's stroke, thin enough to sit inside the button.
const double _spinnerStrokeWidth = 2;

/// How faded the send button is while there is nothing to send.
const double _disabledOpacity = 0.45;

/// A growing text field and a round send button, in one bar.
class ChatGroupComposer extends StatelessWidget {
  /// Builds the bar around [input].
  const ChatGroupComposer({
    super.key,
    required this.input,
    required this.onSend,
    required this.isSending,
  });

  /// Holds the member's draft; the screen clears and restores it.
  final TextEditingController input;

  /// Called when the send button is tapped with something to send.
  final VoidCallback onSend;

  /// True while a send is in flight; the button is disabled meanwhile.
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpace.sm,
          AppSpace.xs,
          AppSpace.sm,
          AppSpace.xs,
        ),
        decoration: BoxDecoration(
          color: AppThemeConfig.softSurface(context),
          border: Border(
            top: BorderSide(color: AppThemeConfig.border(context)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _DraftField(input: input)),
            const SizedBox(width: AppSpace.xs),
            _SendButton(input: input, onSend: onSend, isSending: isSending),
          ],
        ),
      ),
    );
  }
}

/// The multi-line draft. Return inserts a new line, as in every chat app;
/// sending is the button's job.
class _DraftField extends StatelessWidget {
  const _DraftField({required this.input});

  /// Holds the draft.
  final TextEditingController input;

  @override
  Widget build(BuildContext context) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.full),
      borderSide: BorderSide(color: AppThemeConfig.border(context)),
    );
    return TextField(
      controller: input,
      minLines: 1,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Type a message…'.tr,
        filled: true,
        fillColor: AppThemeConfig.surface(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        // Only the resting outlines are set; the focused outline comes from
        // the app theme, so the field shows the same focus state as every
        // other input.
        border: outline,
        enabledBorder: outline,
      ),
    );
  }
}

/// The round send button: enabled only while the draft holds more than
/// whitespace and no send is in flight.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.input,
    required this.onSend,
    required this.isSending,
  });

  /// The draft, watched keystroke by keystroke.
  final TextEditingController input;

  /// Called on tap when there is something to send.
  final VoidCallback onSend;

  /// True while a send is in flight.
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    // Rebuilds on every keystroke, so the button enables the moment there is
    // something to send and disables again when the box is cleared.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: input,
      builder: (context, draft, _) {
        final canSend = !isSending && draft.text.trim().isNotEmpty;
        final foreground = AppThemeConfig.onAccent(context);
        return AppPressable(
          key: const Key('chat_group_send'),
          onTap: canSend ? onSend : null,
          semanticLabel: 'Send message'.tr,
          child: Opacity(
            // A sending button stays at full strength: it is busy, not idle.
            opacity: canSend || isSending ? 1 : _disabledOpacity,
            child: Container(
              width: _sendButtonSize,
              height: _sendButtonSize,
              decoration: BoxDecoration(
                color: AppThemeConfig.accent(context),
                shape: BoxShape.circle,
              ),
              child: isSending
                  ? _SendingSpinner(color: foreground)
                  // The glyph the 1:1 and marriage chats use. It is declared
                  // with matchTextDirection, so it points the other way in
                  // Arabic and Kurdish without a second asset.
                  : Icon(
                      Icons.send_rounded,
                      color: foreground,
                      size: _sendIconSize,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// The in-button "sending" spinner, in [color] on both platforms.
///
/// Deliberately not `CircularProgressIndicator.adaptive`: on iOS that builds a
/// CupertinoActivityIndicator coloured by `backgroundColor` and ignores
/// `valueColor`, which left grey ticks on the accent fill — about 1.5:1, so an
/// iPhone user saw a blank green circle while their message was sending.
class _SendingSpinner extends StatelessWidget {
  const _SendingSpinner({required this.color});

  /// The spinner's colour — the button's foreground.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return Center(child: CupertinoActivityIndicator(color: color));
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: CircularProgressIndicator(
        strokeWidth: _spinnerStrokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
