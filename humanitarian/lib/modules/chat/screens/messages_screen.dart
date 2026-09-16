// messages_screen.dart — the Messages tab.
//
// Holds openSupportChat and its two notifiers, and MessagesScreen, which
// builds the assistant and support doors, the thread list sections and the
// group chats (or the guest prompt). The row widgets live in
// widgets/chat_thread_tiles.dart, widgets/chat_request_card.dart and
// widgets/messages_support_tiles.dart (OPOS #26495).
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/support_chat_result.dart';
import 'package:flutter_application_1/modules/chat/widgets/support_chat_unavailable_notice.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_groups_controller.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/chat_groups_section.dart';
import 'package:flutter_application_1/modules/dashboard/screens/guest_sections.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_request_card.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_thread_tiles.dart';
import 'package:flutter_application_1/modules/chat/widgets/messages_support_tiles.dart';

/// The "Messages" tab — lists all of a user's chat threads.
// #45 — open (or reuse) a direct chat with support/tech and jump into it.
/// The reason the last support-chat attempt failed, or null when it has not
/// failed. Rendered INLINE by [MessagesScreen] rather than shown as a toast.
///
/// WHY INLINE AND NOT A SNACKBAR
/// Three toast mechanisms were tried here and none rendered: ScaffoldMessenger
/// (this route has no Scaffold whose messenger is on screen), the same without
/// a context.mounted guard, and Get.snackbar — which is CALLED and returns
/// normally, yet paints nothing, verified with six consecutive frame captures.
/// The overlay problem is real and unexplained.
///
/// Chasing it further was the wrong trade. A transient toast is the weaker
/// answer regardless: rule 5.7 asks for an in-content error state for a failed
/// action, and an inline message cannot be missed, cannot race a screenshot,
/// and does not depend on an overlay host at all.
final ValueNotifier<String?> supportChatError = ValueNotifier<String?>(null);

/// True when the server has told us no staff account is set to receive support
/// chats. Kept apart from [supportChatError] because the two need opposite
/// treatment on screen — see [SupportChatResult].
final ValueNotifier<bool> supportChatUnavailable = ValueNotifier<bool>(false);

Future<void> openSupportChat(
  BuildContext context, {
  // A seam for tests, defaulted so every call site is unchanged. The two
  // failure branches set different notifiers and that difference is the whole
  // fix, so it needs asserting.
  ModuleApi api = const ModuleApi(),
}) async {
  supportChatError.value = null;
  supportChatUnavailable.value = false;

  final result = await api.openSupportThread();

  switch (result) {
    case SupportChatOpened(:final threadId):
      Get.to(
        () => ChatConversationScreen(
          threadId: threadId,
          title: 'chat_support'.tr,
        ),
      );

    case SupportChatUnavailable():
      // Deliberately NOT an error with a Retry. No staff account is nominated
      // to receive support chats, so every retry returns the same 503 until
      // someone picks one in the dashboard — a button the user presses and
      // presses that cannot work is worse than no button, because it implies
      // the fault is theirs.
      //
      // The user's actual intent was "reach support", and two channels that
      // work are one screen away: the ticket form and the WhatsApp handoff,
      // both on TechnicalSupportScreen. So they are offered that instead.
      debugPrint(
        '[support-chat] no support account configured (503). '
        'Set it in the dashboard: Settings -> support user.',
      );
      supportChatUnavailable.value = true;

    case SupportChatFailed(:final detail):
      // The USER gets the translated message; the SERVER's own sentence goes
      // to the log only. Showing the server text was tried and reverted after
      // seeing it: "Support chat is not configured." rendered in English on an
      // Arabic screen, which is precisely the leak this app has been fixing.
      //
      // This call previously left no trace anywhere, which is the only reason
      // the underlying 503 went unnoticed for so long.
      debugPrint('[support-chat] could not open a thread: $detail');
      supportChatError.value = 'chat_support_failed';
  }
}

/// The Messages tab: the assistant and support doors, then the user's 1:1 chat
/// threads, then their staff-mediated group chats.
///
/// A GUEST gets the same doors and, in place of the threads and groups, a
/// sign-in prompt (OPOS #26423). The comment at the top of [build] says why.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // OPOS #26423 — no ChatController for a guest. The server gives a guest
    // session an empty /api/chats and refuses thread messages (OPOS #26354),
    // so a controller here would fetch on open and poll every 5 seconds for a
    // list that can never fill, and the tab would draw its empty or error
    // state for something a guest simply does not have. The guest gets
    // GuestMessagesPrompt in the list's place; the doors above it stay.
    final guest = isGuestMode();
    final ctrl = guest
        ? null
        : Get.isRegistered<ChatController>()
        ? Get.find<ChatController>()
        : Get.put(ChatController());
    // Put here, never in the lazily built ChatGroupsSection: GetX deletes a
    // controller with the route current when it was put, and only this build
    // is sure to run while Messages is that route. Guests have no groups.
    final groups = guest
        ? null
        : Get.isRegistered<ChatGroupsController>()
        ? Get.find<ChatGroupsController>()
        : Get.put(ChatGroupsController());

    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        // These three are standing entry points, not content: the bot,
        // support chat and case chats are reachable whether or not the user
        // has any threads, and whether or not the user is a guest. They were
        // previously duplicated across the empty branch and the content
        // branch, which is why the empty state had to re-list them. They now
        // live outside the async region and are written once.
        const BotAssistantCard(),
        const SizedBox(height: 10),
        // #45 — direct chat with support/tech staff.
        SectionTile(
          icon: Icons.support_agent_rounded,
          title: 'chat_support'.tr,
          subtitle: 'chat_support_desc'.tr,
          color: AppThemeConfig.accent(context),
          onTap: () => openSupportChat(context),
        ),
        const SizedBox(height: 10),
        // A standing (not error-gated) route to the ticket form. This is not a
        // duplicate of chat_support above: that is a live conversation with a
        // human, this files a tracked request that survives no one being
        // online to answer chat — which, in production today, is the common
        // case (support chat returns 503 until a staff account is configured).
        SectionTile(
          icon: Icons.contact_support_outlined,
          title: 'support_request_form'.tr,
          subtitle: 'support_request_form_desc'.tr,
          color: AppThemeConfig.accent(context),
          onTap: () => Get.to(() => const TechnicalSupportScreen()),
        ),
        // Sits directly beneath the control that failed, so the message is
        // attached to the thing the user just pressed.
        ValueListenableBuilder<String?>(
          valueListenable: supportChatError,
          builder: (context, message, _) {
            if (message == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AppErrorState(
                message: message,
                onRetry: () => openSupportChat(context),
              ),
            );
          },
        ),
        // The PERMANENT case, which deliberately looks nothing like the error
        // above: no Retry, because retrying cannot work, and a route to the
        // two support channels that do.
        ValueListenableBuilder<bool>(
          valueListenable: supportChatUnavailable,
          builder: (context, unavailable, _) {
            if (!unavailable) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SupportChatUnavailableNotice(),
            );
          },
        ),
        // Only the THREAD list has four states. Its error branch used to
        // replace the whole screen, taking the support and bot entry points
        // down with it - so a failed thread fetch also removed the user's way
        // to contact support about it.
        //
        // The Obx wraps this region alone rather than the whole list: nothing
        // above it reads the threads, and a guest has no controller to observe
        // at all (an Obx that reads no observable throws in GetX).
        if (ctrl == null)
          const GuestMessagesPrompt()
        else
          Obx(() {
            final incoming = ctrl.threads
                .where((t) => t.incomingPending)
                .toList();
            final active = ctrl.threads.where((t) => t.isActive).toList();
            final outgoing = ctrl.threads
                .where((t) => t.isPending && !t.incomingPending)
                .toList();

            return AppAsync<List<dynamic>>(
              loading: ctrl.isLoading.value,
              error: ctrl.errorMessage.value,
              onRetry: ctrl.fetchThreads,
              data: ctrl.threads,
              isEmpty: (list) => list.isEmpty,
              empty: const AppEmpty(
                title: 'No conversations yet',
                message:
                    'Start a chat from a donation (donor) or from your campaign donations (owner).',
              ),
              builder: (_) => Column(
                children: [
                  if (incoming.isNotEmpty) ...[
                    ChatThreadSectionLabel(
                      label: 'Chat requests',
                      count: incoming.length,
                    ),
                    for (final t in incoming)
                      IncomingChatRequestCard(thread: t, ctrl: ctrl),
                    const SizedBox(height: 8),
                  ],
                  if (active.isNotEmpty) ...[
                    ChatThreadSectionLabel(
                      label: 'Conversations',
                      count: active.length,
                    ),
                    for (final t in active) ChatThreadTile(thread: t),
                  ],
                  if (outgoing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ChatThreadSectionLabel(
                      label: 'Waiting for accept',
                      count: outgoing.length,
                    ),
                    for (final t in outgoing)
                      OutgoingPendingChatTile(thread: t),
                  ],
                ],
              ),
            );
          }),
        // OPOS #25284 — staff-mediated group chats. Last, so nothing in it can
        // displace the doors above; guests cannot message at all.
        if (!isGuestMode()) const ChatGroupsSection(),
      ],
    );

    return SectionScaffold(
      assistantRoute: 'messages',
      title: 'Messages',
      subtitle: 'Chat with campaign owners and donors. Support is included.',
      // Pull-to-refresh only where there is something to refresh: a guest has
      // no threads and no groups, so a spinner would promise an update that
      // cannot come.
      child: ctrl == null
          ? list
          : RefreshIndicator(
              // Pulling down refreshes everything the tab lists, groups
              // included.
              onRefresh: () => Future.wait([
                ctrl.fetchThreads(),
                if (groups != null) groups.fetchGroups(),
              ]),
              child: list,
            ),
    );
  }
}
