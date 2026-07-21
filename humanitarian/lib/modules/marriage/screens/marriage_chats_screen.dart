import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
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
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_chats_title'.tr,
      subtitle: 'marriage_chats_subtitle'.tr,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                    children: [
                      Center(
                        child: Text(
                          snapshot.hasError
                              ? 'marriage_chats_load_failed'.tr
                              : 'marriage_chats_empty'.tr,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ThreadTile(thread: items[i]),
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
        onTap: () => Get.to(() => MarriageChatConversationScreen(
              threadId: id,
              otherLabel: otherLabel,
              myRole: myRole,
              initialStatus: status,
            )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(otherLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
