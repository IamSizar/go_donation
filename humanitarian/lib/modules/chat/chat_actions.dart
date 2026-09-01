import 'package:flutter/material.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/support_chat_result.dart';
import 'package:flutter_application_1/modules/chat/widgets/support_chat_unavailable_notice.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';
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
    final confirmed = await showAdaptiveConfirm(
      context,
      title: 'Start a chat?'.tr,
      message:
          'You are about to start a conversation with @who. They will be notified and must accept before you can message. Support can also view this chat.'
              .trParams({'who': otherPartyLabel}),
      confirmLabel: 'Yes, start chat'.tr,
      cancelLabel: 'Cancel'.tr,
    );
    if (!confirmed) return;
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
        Get.to(
          () => ChatConversationScreen(
            threadId: res.threadId,
            title: conversationTitle ?? 'Chat'.tr,
            subtitle: conversationSubtitle,
          ),
        );
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
        SnackBar(content: Text(failureMessage(e, 'error_message_send_failed'))),
      );
    }
  }

  /// "Message the staff team" — a direct chat with the admin-configured
  /// support/tech staff account (#45), not tied to a donation or campaign.
  ///
  /// WHY THIS DOES NOT GO THROUGH ChatController.requestSupportChat
  /// That path posts and throws on any non-2xx, so all three server answers
  /// arrived as one generic failure: "couldn't send your message, try again —
  /// and if it keeps happening, contact support". On production that is what
  /// the events section's support tile actually did, because the server
  /// answers 503 until a staff account is nominated (Settings -> support
  /// user). So the button for contacting support told the user to contact
  /// support, and offered a retry that could not ever succeed.
  ///
  /// [openSupportThread] tells the three answers apart, and each gets the
  /// response it deserves: open the chat, hand over a channel that works, or
  /// report a genuine failure.
  static Future<void> startSupportChat(
    BuildContext context, {
    String? conversationTitle,
    // A seam for tests, defaulted so the call site is unchanged.
    ModuleApi api = const ModuleApi(),
  }) async {
    if (!await requireUpgrade(context)) return;
    if (!context.mounted) return;

    final result = await api.openSupportThread();
    if (!context.mounted) return;

    switch (result) {
      case SupportChatOpened(:final threadId):
        Get.to(
          () => ChatConversationScreen(
            threadId: threadId,
            title: conversationTitle ?? 'Staff support'.tr,
          ),
        );

      case SupportChatUnavailable():
        // Nothing has gone wrong from the user's side and there is nothing to
        // retry, so this is not an error and gets no Retry. The ticket form
        // and the WhatsApp handoff both still work, and the notice hands them
        // over — the same words the Messages screen uses, for the same 503.
        debugPrint(
          '[support-chat] no support account configured (503). '
          'Set it in the dashboard: Settings -> support user.',
        );
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: SupportChatUnavailableNotice(),
            ),
          ),
        );

      case SupportChatFailed(:final detail, :final offline):
        // The user gets the translated sentence; the server's own wording goes
        // to the log only, since it is written in English on an Arabic screen.
        debugPrint('[support-chat] could not open a thread: $detail');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // "What failed" from this call site, "what to do next" from the
            // failure's own type — the same split failureMessage makes, via
            // the same two keys, for call sites that still hold the exception.
            content: Text(
              failureMessageFor(
                offline: offline,
                whatFailedKey: 'error_message_send_failed',
              ),
            ),
            duration: const Duration(seconds: 6),
            // A way out, per the error rules: even a genuine failure must not
            // dead-end on a screen whose whole purpose was reaching someone.
            action: SnackBarAction(
              label: 'chat_support_unavailable_action'.tr,
              onPressed: () => Get.to(() => const TechnicalSupportScreen()),
            ),
          ),
        );
    }
  }
}
