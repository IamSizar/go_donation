import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_chat_conversation_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Note #35 — list of the current user's staff-mediated marriage chat
/// threads (as requester or as profile owner). Neither role ever sees the
/// other party's real identity here — `other_label` is either the target
/// profile's own (already-public) code, or a generic placeholder.
class MarriageChatsScreen extends StatefulWidget {
  const MarriageChatsScreen({super.key});

  @override
  State<MarriageChatsScreen> createState() => _MarriageChatsScreenState();
}

class _MarriageChatsScreenState extends State<MarriageChatsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = const ModuleApi().marriageChats();
  }

  Future<void> _refresh() async {
    setState(() => _future = const ModuleApi().marriageChats());
    try {
      await _future;
    } catch (_) {
      // Deliberately not surfaced here: the FutureBuilder above reads
      // snapshot.hasError and renders the error state with its retry. This
      // await exists only so the pull-to-refresh spinner waits for the fetch,
      // and without the guard a failed retry would also throw out of this
      // callback as an unhandled async error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_chats_title'.tr,
      subtitle: 'marriage_chats_subtitle'.tr,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          // The failure copy was previously rendered as a bare centred line
          // inside the empty branch: the user was told the load failed, but
          // handed no way out — a dead-end error screen, which the four-state
          // rule counts as a bug. It now routes through AppAsync so the same
          // message arrives with a working retry that re-runs the fetch.
          if (snapshot.hasError) {
            debugPrint('marriageChats failed: ${snapshot.error}');
          }
          return AppAsync<List<Map<String, dynamic>>>(
            loading: snapshot.connectionState == ConnectionState.waiting,
            // Retry clears the error implicitly: _refresh replaces _future, so
            // the next snapshot starts clean.
            error: snapshot.hasError ? 'marriage_chats_load_failed'.tr : null,
            onRetry: _refresh,
            data: snapshot.data ?? const <Map<String, dynamic>>[],
            isEmpty: (threads) => threads.isEmpty,
            empty: AppEmpty(
              icon: Icons.forum_rounded,
              title: 'marriage_chats_title'.tr,
              message: 'marriage_chats_empty'.tr,
            ),
            builder: (threads) => RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                itemCount: threads.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _ThreadTile(thread: threads[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});
  final Map<String, dynamic> thread;

  @override
  Widget build(BuildContext context) {
    final id = thread['id'] as int;
    final status = (thread['status'] ?? '').toString();
    final myRole = (thread['my_role'] ?? '').toString();
    final otherLabelRaw = (thread['other_label'] ?? '').toString();
    final otherLabel = otherLabelRaw == 'interested_member'
        ? 'marriage_chat_interested_member'.tr
        : otherLabelRaw;
    final lastMessage = (thread['last_message'] ?? '').toString();

    return GlassPanel(
      child: InkWell(
        onTap: () => Get.to(
          () => MarriageChatConversationScreen(
            threadId: id,
            otherLabel: otherLabel,
            myRole: myRole,
            initialStatus: status,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    otherLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            if (lastMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(lastMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'active'
        ? Colors.green
        : status == 'pending'
        ? Colors.orange
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'marriage_chat_status_$status'.tr,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
