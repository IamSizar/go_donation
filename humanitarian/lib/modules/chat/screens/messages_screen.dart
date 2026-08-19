import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/support_chat_result.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/bot/screens/bot_chat_screen.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/case_chat_conversation_screen.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

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

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.isRegistered<ChatController>()
        ? Get.find<ChatController>()
        : Get.put(ChatController());

    return SectionScaffold(
      assistantRoute: 'messages',
      title: 'Messages',
      subtitle: 'Chat with campaign owners and donors. Support is included.',
      child: Obx(() {
        final incoming = ctrl.threads.where((t) => t.incomingPending).toList();
        final active = ctrl.threads.where((t) => t.isActive).toList();
        final outgoing = ctrl.threads
            .where((t) => t.isPending && !t.incomingPending)
            .toList();

        return RefreshIndicator(
          onRefresh: ctrl.fetchThreads,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            children: [
              // These three are standing entry points, not content: the bot,
              // support chat and case chats are reachable whether or not the
              // user has any threads. They were previously duplicated across
              // the empty branch and the content branch, which is why the
              // empty state had to re-list them. They now live outside the
              // async region and are written once.
              const _BotAssistantCard(),
              const SizedBox(height: 10),
              // #45 — direct chat with support/tech staff.
              SectionTile(
                icon: Icons.support_agent_rounded,
                title: 'chat_support'.tr,
                subtitle: 'chat_support_desc'.tr,
                color: AppThemeConfig.accent(context),
                onTap: () => openSupportChat(context),
              ),
              // Sits directly beneath the control that failed, so the message
              // is attached to the thing the user just pressed.
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
              // The PERMANENT case, which deliberately looks nothing like the
              // error above: no Retry, because retrying cannot work, and a
              // route to the two support channels that do.
              ValueListenableBuilder<bool>(
                valueListenable: supportChatUnavailable,
                builder: (context, unavailable, _) {
                  if (!unavailable) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: _SupportChatUnavailableNotice(),
                  );
                },
              ),
              const SizedBox(height: 10),
              const _CaseChatsSection(),
              // Only the THREAD list has four states. Its error branch used to
              // replace the whole screen, taking the support and bot entry
              // points down with it - so a failed thread fetch also removed
              // the user's way to contact support about it.
              AppAsync<List<dynamic>>(
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
                      _SectionLabel(
                        label: 'Chat requests',
                        count: incoming.length,
                      ),
                      for (final t in incoming)
                        _IncomingRequestCard(thread: t, ctrl: ctrl),
                      const SizedBox(height: 8),
                    ],
                    if (active.isNotEmpty) ...[
                      _SectionLabel(
                        label: 'Conversations',
                        count: active.length,
                      ),
                      for (final t in active) _ThreadTile(thread: t),
                    ],
                    if (outgoing.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _SectionLabel(
                        label: 'Waiting for accept',
                        count: outgoing.length,
                      ),
                      for (final t in outgoing) _OutgoingPendingTile(thread: t),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// Note #36 — Staff↔Volunteer↔Beneficiary chats. Opens automatically once a
// volunteer's case-linked signup is approved; renders nothing when the user
// has none (most users never will — this only applies to case-linked
// volunteer signups and the case's beneficiary).
class _CaseChatsSection extends StatefulWidget {
  const _CaseChatsSection();

  @override
  State<_CaseChatsSection> createState() => _CaseChatsSectionState();
}

class _CaseChatsSectionState extends State<_CaseChatsSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = const ModuleApi().caseChats();
  }

  /// Re-runs the fetch. The new future replaces the old one, which also clears
  /// the previous error — the FutureBuilder rebuilds from a clean snapshot.
  void _reload() {
    setState(() => _future = const ModuleApi().caseChats());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        // snapshot.hasError is now read. It was not before: the builder went
        // straight to `snapshot.data ?? const []`, so a future that THREW
        // produced an empty list and the section erased itself — a volunteer
        // or beneficiary with live case chats saw no trace of them, and had
        // no way to retry. Rendering nothing is only correct when the fetch
        // SUCCEEDED and returned nothing.
        if (snapshot.hasError) {
          debugPrint('caseChats failed: ${snapshot.error}');
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppErrorState(
              message: 'Could not load your case chats.',
              onRetry: _reload,
            ),
          );
        }
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        // Genuinely empty (or still loading): most users never have a case
        // chat, so this section stays invisible rather than showing a
        // skeleton or an empty state for something they will never use.
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(label: 'case_chats_label', count: items.length),
              for (final item in items) _CaseChatTile(thread: item),
            ],
          ),
        );
      },
    );
  }
}

class _CaseChatTile extends StatelessWidget {
  const _CaseChatTile({required this.thread});
  final Map<String, dynamic> thread;

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse('${thread['id']}') ?? 0;
    final otherName = (thread['other_name'] ?? '').toString().trim();
    final title = otherName.isNotEmpty ? otherName : 'User'.tr;
    final caseCode = (thread['case_code'] ?? '').toString();
    final lastMessage = (thread['last_message'] ?? '').toString();
    final unread = int.tryParse('${thread['unread_count'] ?? 0}') ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Get.to(
            () => CaseChatConversationScreen(
              threadId: id,
              title: title,
              subtitle: caseCode,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(name: title, color: AppThemeConfig.accent(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lastMessage.isNotEmpty ? lastMessage : caseCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread > 0) ...[
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
                        '$unread',
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.color});
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

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});
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
              title: thread.otherName,
              subtitle: thread.campaignTitle ?? roleLabel.tr,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(name: thread.otherName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              thread.otherName,
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

class _OutgoingPendingTile extends StatelessWidget {
  const _OutgoingPendingTile({required this.thread});
  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Avatar(
              name: thread.otherName,
              color: AppThemeConfig.pending(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.otherName,
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

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({required this.thread, required this.ctrl});
  final ChatThread thread;
  final ChatController ctrl;

  Future<void> _accept(BuildContext context) async {
    try {
      await ctrl.accept(thread.id);
      if (context.mounted) {
        Get.to(
          () => ChatConversationScreen(
            threadId: thread.id,
            title: thread.otherName,
            subtitle: thread.campaignTitle,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
          SnackBar(content: Text('Could not decline this chat request.'.tr)),
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
                _Avatar(name: thread.otherName, color: AppThemeConfig.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        thread.otherName,
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
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _accept(context),
                    child: Text('Accept'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Support-bot entry card ───────────────────────────────────────────────────

/// A card pinned at the top of the Messages screen that opens the support bot.
class _BotAssistantCard extends StatelessWidget {
  const _BotAssistantCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 8),
      child: InkWell(
        onTap: () => Get.to(() => const BotChatScreen()),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeConfig.accent(context).withValues(alpha: 0.10),
            border: Border.all(
              color: Colors.deepPurple.withValues(alpha: 0.22),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppThemeConfig.accent(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: AppThemeConfig.onAccent(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Support Assistant'.tr,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppThemeConfig.accent(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ask me anything — I\'ll guide you through the app'.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronForward(context),
                color: AppThemeConfig.accent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when no staff account is configured to receive support chats.
///
/// Says what happened, then hands over the channels that work. It is not an
/// error state: nothing has gone wrong from the user's side, there is nothing
/// for them to retry, and the thing they actually wanted — to reach support —
/// is still entirely possible.
class _SupportChatUnavailableNotice extends StatelessWidget {
  const _SupportChatUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        border: Border.all(color: AppThemeConfig.border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat_support_unavailable_title'.tr,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'chat_support_unavailable_body'.tr,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
          const SizedBox(height: 12),
          // Full-width so it reads as the way forward rather than a footnote.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Get.to(() => const TechnicalSupportScreen()),
              child: Text('chat_support_unavailable_action'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
