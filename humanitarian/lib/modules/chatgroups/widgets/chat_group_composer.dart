// ChatGroupComposer — the message box and send button at the foot of a
// chat-group conversation (OPOS #25284 Phase 5).
//
// Presentation only: it owns no send logic. ChatGroupConversationScreen hands
// it the draft's controller, what to do on send, and whether a send is in
// flight. While one is, the button is disabled — and announced as disabled to
// screen readers — with a spinner in place of its icon, so a second tap cannot
// send the same message twice.
//
// No length limit is enforced here because the server enforces none: the
// chat-group send route rejects only an empty body, and a blank draft never
// reaches it (the screen and the controller both refuse one).
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:get/get.dart';

/// The send button's diameter — the same as the 1:1 chat's, and above the
/// 44pt minimum touch target.
const double _sendButtonSize = 46;

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

  /// Called when the send button is tapped.
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
            _SendButton(onSend: onSend, isSending: isSending),
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

/// The round send button: disabled, with a spinner in place of its icon,
/// while [isSending].
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onSend, required this.isSending});

  /// Called on tap.
  final VoidCallback onSend;

  /// True while a send is in flight.
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final foreground = AppThemeConfig.onAccent(context);
    return AppPressable(
      key: const Key('chat_group_send'),
      onTap: isSending ? null : onSend,
      semanticLabel: 'Send message'.tr,
      child: Container(
        width: _sendButtonSize,
        height: _sendButtonSize,
        decoration: BoxDecoration(
          color: AppThemeConfig.accent(context),
          shape: BoxShape.circle,
        ),
        child: isSending
            ? Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foreground),
                ),
              )
            // The glyph the 1:1 and marriage chats use, kept for consistency.
            // It is declared with matchTextDirection, so it points the other
            // way in Arabic and Kurdish without a second asset.
            : Icon(Icons.send_rounded, color: foreground, size: AppSpace.lg),
      ),
    );
  }
}
