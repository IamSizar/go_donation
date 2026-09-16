// chat_thread_tiles.dart — the rows of the Messages tab's thread list.
//
// Holds the section heading used over "Chat requests", "Conversations" and
// "Waiting for accept", the initial avatar, the active-conversation tile and
// the outgoing-pending tile. The sections themselves are still assembled by
// MessagesScreen, which decides which threads go where; these widgets only
// draw one row each. Moved out of messages_screen.dart unchanged (OPOS #26495)
// to keep that file under the 500-line limit.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:flutter_application_1/modules/chat/utils/chat_sender_name.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// A section heading over the thread list ("Chat requests", "Conversations",
/// "Waiting for accept") with the section's item count beside it.
class ChatThreadSectionLabel extends StatelessWidget {
  const ChatThreadSectionLabel({
    super.key,
    required this.label,
    required this.count,
  });
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Text(
            label.tr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppThemeConfig.mutedText(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(
              fontSize: 12,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded initial badge shown at the start of every thread row and
/// chat request card. [color] defaults to the primary colour.
class ChatThreadAvatar extends StatelessWidget {
  const ChatThreadAvatar({super.key, required this.name, this.color});
  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppThemeConfig.primary;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c),
        ),
      ),
    );
  }
}

/// One active 1:1 conversation in the Messages tab. Tapping it opens
/// [ChatConversationScreen]; it shows the last message, the date, the unread
/// count and, when claimed, the responsible staff member.
class ChatThreadTile extends StatelessWidget {
  const ChatThreadTile({super.key, required this.thread});
  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final roleLabel = thread.myRole == 'donor' ? 'Campaign owner' : 'Donor';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Get.to(
            () => ChatConversationScreen(
              threadId: thread.id,
              title: chatThreadOtherName(thread),
              subtitle: thread.campaignTitle ?? roleLabel.tr,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ChatThreadAvatar(name: chatThreadOtherName(thread)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chatThreadOtherName(thread),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppThemeConfig.text(context),
                              ),
                            ),
                          ),
                          if (thread.lastMessageAt != null)
                            Text(
                              DateFormat('MMM d').format(thread.lastMessageAt!),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppThemeConfig.mutedText(context),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        thread.lastMessage ??
                            '${roleLabel.tr} · ${thread.campaignTitle ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: thread.unreadCount > 0
                              ? AppThemeConfig.text(context)
                              : AppThemeConfig.mutedText(context),
                          fontWeight: thread.unreadCount > 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      // Note #36 — the "Responsible Staff Member," if claimed.
                      if (thread.assignedStaffName != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.shield_rounded,
                              size: 11,
                              color: AppThemeConfig.subtleText(context),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'helped_by'.trParams({
                                'name': thread.assignedStaffName!,
                              }),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppThemeConfig.subtleText(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (thread.unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppThemeConfig.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    child: Center(
                      child: Text(
                        '${thread.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chat request the user sent that the other side has not accepted yet.
/// It is informational only and has no actions.
class OutgoingPendingChatTile extends StatelessWidget {
  const OutgoingPendingChatTile({super.key, required this.thread});
  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ChatThreadAvatar(
              name: chatThreadOtherName(thread),
              color: AppThemeConfig.pending(context),
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
                      fontWeight: FontWeight.w800,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Waiting for them to accept your chat request…'.tr,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.hourglass_top_rounded,
              color: AppThemeConfig.pending(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
