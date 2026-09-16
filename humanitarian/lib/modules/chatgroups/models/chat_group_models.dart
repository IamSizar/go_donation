// Models for OPOS #25284's staff-mediated masked/team group chats.

class ChatGroupSummary {
  final int id;
  final String kind; // "masked" | "team"
  final String title; // "" for masked groups
  final int unreadCount;
  final String lastMessage;
  final DateTime? lastAt;

  const ChatGroupSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.unreadCount,
    required this.lastMessage,
    required this.lastAt,
  });

  bool get isMasked => kind == 'masked';

  factory ChatGroupSummary.fromMap(Map<String, dynamic> m) {
    return ChatGroupSummary(
      id: int.tryParse('${m['id']}') ?? 0,
      kind: (m['kind'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      unreadCount: int.tryParse('${m['unread_count'] ?? 0}') ?? 0,
      lastMessage: (m['last_message'] ?? '').toString(),
      lastAt: DateTime.tryParse((m['last_at'] ?? '').toString()),
    );
  }
}

// GroupMessage has no user-id field server-side by design (a masked member's
// real identity cannot be leaked through a type that cannot hold one) — this
// client model mirrors that shape exactly. Never add a userId field here.
class ChatGroupMessage {
  final int id;
  final int senderMemberId;
  final String senderLabel;
  final bool isMine;
  final String body;
  final DateTime? createdAt;

  const ChatGroupMessage({
    required this.id,
    required this.senderMemberId,
    required this.senderLabel,
    required this.isMine,
    required this.body,
    required this.createdAt,
  });

  factory ChatGroupMessage.fromMap(Map<String, dynamic> m) {
    return ChatGroupMessage(
      id: int.tryParse('${m['id']}') ?? 0,
      senderMemberId: int.tryParse('${m['sender_member_id']}') ?? 0,
      senderLabel: (m['sender_label'] ?? '').toString(),
      isMine: m['is_mine'] == true,
      body: (m['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
    );
  }
}

class MyConnectRequest {
  final int id;
  final String contextType; // "donation" | "case"
  final int contextId;
  final String message;
  final int? groupId;
  final String status; // "pending" | "approved" | "declined"
  final String? declineReason;
  final DateTime? createdAt;

  const MyConnectRequest({
    required this.id,
    required this.contextType,
    required this.contextId,
    required this.message,
    required this.groupId,
    required this.status,
    required this.declineReason,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDeclined => status == 'declined';

  factory MyConnectRequest.fromMap(Map<String, dynamic> m) {
    final reason = m['decline_reason']?.toString().trim();
    return MyConnectRequest(
      id: int.tryParse('${m['id']}') ?? 0,
      contextType: (m['context_type'] ?? '').toString(),
      contextId: int.tryParse('${m['context_id']}') ?? 0,
      message: (m['message'] ?? '').toString(),
      groupId: m['group_id'] == null ? null : int.tryParse('${m['group_id']}'),
      status: (m['status'] ?? 'pending').toString(),
      declineReason: (reason == null || reason.isEmpty) ? null : reason,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
    );
  }
}
