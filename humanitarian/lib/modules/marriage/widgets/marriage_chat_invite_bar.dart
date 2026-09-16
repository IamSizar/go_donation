// marriage_chat_invite_bar.dart — the profile owner's Accept / Decline row on
// a pending marriage chat invite.
//
// WHY THIS IS ITS OWN FILE
// It was inline in marriage_chat_conversation_screen.dart. OPOS #26433 made it
// lifecycle-aware, which would have pushed that screen past the project's
// 500-line limit, so the row moved here. The screen still owns the decision
// and the refusal copy; this widget only draws the buttons it is told to.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_invite_refusal.dart';
import 'package:get/get.dart';

/// The pending-invite notice with Decline and, when [canAccept], Accept.
class MarriageChatInviteBar extends StatelessWidget {
  /// Creates the row. [onAnswer] receives which button was tapped.
  const MarriageChatInviteBar({
    super.key,
    required this.deciding,
    required this.canAccept,
    required this.onAnswer,
  });

  /// True while an answer is in flight; both buttons are disabled.
  final bool deciding;

  /// False on a paused, ended or archived thread. The server refuses that
  /// accept with `chat_lifecycle_closed` (or 404), while declining stays
  /// allowed, so Decline remains the way to dismiss the invite.
  final bool canAccept;

  /// Called with the tapped answer.
  final ValueChanged<ChatInviteAnswer> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'marriage_chat_pending_owner_notice'.tr,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: deciding
                ? null
                : () => onAnswer(ChatInviteAnswer.decline),
            child: Text('marriage_chat_decline'.tr),
          ),
          if (canAccept) ...[
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: deciding
                  ? null
                  : () => onAnswer(ChatInviteAnswer.accept),
              child: Text('marriage_chat_accept'.tr),
            ),
          ],
        ],
      ),
    );
  }
}
