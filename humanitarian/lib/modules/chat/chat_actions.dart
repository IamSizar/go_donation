import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:get/get.dart';

/// Shared "start a chat" flow used by both entry points (donor from a donation,
/// owner from a donor name). Shows a confirm dialog, sends the request, then
/// either opens the conversation (if already active) or confirms the request
/// was sent (pending the other party's accept).
abstract final class ChatActions {
  static ChatController _controller() => Get.isRegistered<ChatController>()
      ? Get.find<ChatController>()
      : Get.put(ChatController());

  static Future<void> startChat(
    BuildContext context, {
    int? donationId,
    int? donorUserId,
    int? campaignId,
    required String otherPartyLabel, // "the campaign owner" / "this donor"
    String? conversationTitle,
    String? conversationSubtitle,
  }) async {
    // Note #40 — "assistance-related conversations" are restricted for guests.
    if (!await requireUpgrade(context)) return;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Start a chat?'.tr),
        content: Text(
          'You are about to start a conversation with $otherPartyLabel. They will be notified and must accept before you can message. Support can also view this chat.'
              .tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Yes, start chat'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ctrl = _controller();
    try {
      final res = await ctrl.requestChat(
        donationId: donationId,
        donorUserId: donorUserId,
        campaignId: campaignId,
      );
      if (!context.mounted) return;

      if (res.status == 'active') {
        // Already accepted before (existing thread) → open it straight away.
        Get.to(() => ChatConversationScreen(
              threadId: res.threadId,
              title: conversationTitle ?? 'Chat'.tr,
              subtitle: conversationSubtitle,
            ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.already
                  ? 'Your chat request is still waiting to be accepted.'.tr
                  : 'Chat request sent! You can message once they accept. Check the Messages tab.'
                      .tr,
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
