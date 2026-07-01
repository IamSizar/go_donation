import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/bot/screens/bot_chat_screen.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// The "Messages" tab — lists all of a user's chat threads.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.isRegistered<ChatController>()
        ? Get.find<ChatController>()
        : Get.put(ChatController());

    return SectionScaffold(
      title: 'Messages',
      subtitle: 'Chat with campaign owners and donors. Support is included.',
      child: Obx(() {
        if (ctrl.isLoading.value && ctrl.threads.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (ctrl.errorMessage.value != null && ctrl.threads.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SectionTile(
                icon: Icons.refresh_rounded,
                title: 'Messages',
                subtitle: ctrl.errorMessage.value!,
                color: Colors.orange,
                onTap: ctrl.fetchThreads,
              ),
            ],
          );
        }
        if (ctrl.threads.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              _BotAssistantCard(),
              SectionTile(
                icon: Icons.forum_outlined,
                title: 'No conversations yet',
                subtitle:
                    'Start a chat from a donation (donor) or from your campaign donations (owner).',
                color: Colors.indigo,
              ),
            ],
          );
        }

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
              const _BotAssistantCard(),
              if (incoming.isNotEmpty) ...[
                _SectionLabel(label: 'Chat requests', count: incoming.length),
                for (final t in incoming) _IncomingRequestCard(thread: t, ctrl: ctrl),
                const SizedBox(height: 8),
              ],
              if (active.isNotEmpty) ...[
                _SectionLabel(label: 'Conversations', count: active.length),
                for (final t in active) _ThreadTile(thread: t),
              ],
              if (outgoing.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionLabel(label: 'Waiting for accept', count: outgoing.length),
                for (final t in outgoing) _OutgoingPendingTile(thread: t),
              ],
            ],
          ),
        );
      }),
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
          Text('($count)', style: TextStyle(fontSize: 12, color: AppThemeConfig.mutedText(context))),
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
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(15)),
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
    final roleLabel = thread.myRole == 'donor' ? 'Campaign owner' : 'Contributor';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Get.to(() => ChatConversationScreen(
                threadId: thread.id,
                title: thread.otherName,
                subtitle: thread.campaignTitle ?? roleLabel.tr,
              )),
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
                              style: TextStyle(fontSize: 11, color: AppThemeConfig.mutedText(context)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        thread.lastMessage ?? '${roleLabel.tr} · ${thread.campaignTitle ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: thread.unreadCount > 0
                              ? AppThemeConfig.text(context)
                              : AppThemeConfig.mutedText(context),
                          fontWeight: thread.unreadCount > 0 ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (thread.unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: AppThemeConfig.primary, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    child: Center(
                      child: Text(
                        '${thread.unreadCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
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
            _Avatar(name: thread.otherName, color: Colors.amber.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.otherName,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppThemeConfig.text(context)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Waiting for them to accept your chat request…'.tr,
                    style: TextStyle(fontSize: 12.5, color: AppThemeConfig.mutedText(context)),
                  ),
                ],
              ),
            ),
            Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade700, size: 20),
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
        Get.to(() => ChatConversationScreen(
              threadId: thread.id,
              title: thread.otherName,
              subtitle: thread.campaignTitle,
            ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _decline(BuildContext context) async {
    try {
      await ctrl.decline(thread.id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = (thread.myRole == 'donor' ? 'campaign owner' : 'donor').tr;
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
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppThemeConfig.text(context)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'wants to chat with you (@role)'.trParams({'role': roleLabel}),
                        style: TextStyle(fontSize: 12.5, color: AppThemeConfig.mutedText(context)),
                      ),
                      if (thread.campaignTitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '“${thread.campaignTitle}”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppThemeConfig.mutedText(context)),
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
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.shade600.withValues(alpha: 0.10),
                Colors.indigo.shade400.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
                color: Colors.deepPurple.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.shade600,
                      Colors.indigo.shade400,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Support Assistant',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.deepPurple.shade700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ask me anything — I\'ll guide you through the app',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.deepPurple.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
