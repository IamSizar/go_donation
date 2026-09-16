// chat_request_card.dart — an incoming chat request in the Messages tab.
//
// Accept opens the conversation; Decline dismisses the invite. Either answer
// can be refused by the server (declined, already active, or closed), and the
// refusal is mapped to translated copy by chat_invite_refusal.dart. Moved out
// of messages_screen.dart unchanged (OPOS #26495).
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_invite_refusal.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_sender_name.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_thread_tiles.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// A chat request someone sent the user, with Decline and, unless the thread
/// is paused or ended, Accept. A refused answer is shown with the copy from
/// [chatInviteRefusalMessage] (OPOS #26433), never the raw exception.
class IncomingChatRequestCard extends StatelessWidget {
  const IncomingChatRequestCard({
    super.key,
    required this.thread,
    required this.ctrl,
  });
  final ChatThread thread;
  final ChatController ctrl;

  Future<void> _accept(BuildContext context) async {
    try {
      await ctrl.accept(thread.id);
      if (context.mounted) {
        Get.to(
          () => ChatConversationScreen(
            threadId: thread.id,
            title: chatThreadOtherName(thread),
            subtitle: thread.campaignTitle,
          ),
        );
      }
    } catch (e) {
      // Was `Text('$e')`, the raw English exception on every locale. The
      // controller has already refreshed the list, so a declined, active or
      // closed invite leaves this section on its own (OPOS #26433).
      debugPrint('accept thread ${thread.id} failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatInviteRefusalMessage(e, ChatInviteAnswer.accept)),
          ),
        );
      }
    }
  }

  Future<void> _decline(BuildContext context) async {
    try {
      await ctrl.decline(thread.id);
    } catch (e) {
      // Was `catch (_) {}` — a failed decline did nothing at all: the request
      // card stayed on screen with no explanation, so the tap read as a dead
      // button. Declining is a real mutation, not best-effort, so the failure
      // is told to the user and the technical cause goes to the log.
      debugPrint('decline thread ${thread.id} failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              chatInviteRefusalMessage(e, ChatInviteAnswer.decline),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel =
        (thread.myRole == 'donor' ? 'campaign owner' : 'donor').tr;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChatThreadAvatar(
                  name: chatThreadOtherName(thread),
                  color: AppThemeConfig.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chatThreadOtherName(thread),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'wants to chat with you (@role)'.trParams({
                          'role': roleLabel,
                        }),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                      if (thread.campaignTitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '“${thread.campaignTitle}”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AppThemeConfig.mutedText(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decline(context),
                    child: Text('Decline'.tr),
                  ),
                ),
                // No Accept on a paused or ended thread: the server refuses
                // it. Decline stays, to dismiss the invite (OPOS #26433).
                if (!ChatLifecycle.isClosed(thread.lifecycle)) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _accept(context),
                      child: Text('Accept'.tr),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
