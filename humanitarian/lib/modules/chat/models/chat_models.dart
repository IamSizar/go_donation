// Models for the donor ↔ campaign-owner chat.

class ChatThread {
  final int id;
  final String status; // pending | active | declined
  final int? campaignId;
  final String? campaignTitle;
  final int initiatedBy;
  final String myRole; // donor | owner
  final bool incomingPending; // pending AND I must accept
  final int otherUserId;
  final String otherName;
  final String? otherPhone;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const ChatThread({
    required this.id,
    required this.status,
    required this.campaignId,
    required this.campaignTitle,
    required this.initiatedBy,
    required this.myRole,
    required this.incomingPending,
    required this.otherUserId,
    required this.otherName,
    required this.otherPhone,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  factory ChatThread.fromMap(Map<String, dynamic> m) {
    return ChatThread(
      id: int.tryParse('${m['id']}') ?? 0,
      status: (m['status'] ?? 'pending').toString(),
      campaignId: m['campaign_id'] == null
          ? null
          : int.tryParse('${m['campaign_id']}'),
      campaignTitle: m['campaign_title']?.toString(),
      initiatedBy: int.tryParse('${m['initiated_by']}') ?? 0,
      myRole: (m['my_role'] ?? '').toString(),
      incomingPending: m['incoming_pending'] == true,
      otherUserId: int.tryParse('${m['other_user_id']}') ?? 0,
      otherName: (m['other_name'] ?? 'User').toString().trim().isEmpty
          ? 'User #${m['other_user_id']}'
          : (m['other_name']).toString(),
      otherPhone: m['other_phone']?.toString(),
      lastMessage: m['last_message']?.toString(),
      lastMessageAt: DateTime.tryParse((m['last_message_at'] ?? '').toString()),
      unreadCount: int.tryParse('${m['unread_count'] ?? 0}') ?? 0,
    );
  }
}

class ChatMessage {
  final int id;
  final int threadId;
  final int senderUserId;
  final int senderRole; // 0 support/admin, 1 donor, 2 beneficiary, 3 volunteer
  final String senderName;
  final String body;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  bool get isSupport => senderRole == 0;

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    final rawName = (m['sender_name'] ?? '').toString().trim();
    return ChatMessage(
      id: int.tryParse('${m['id']}') ?? 0,
      threadId: int.tryParse('${m['thread_id']}') ?? 0,
      senderUserId: int.tryParse('${m['sender_user_id']}') ?? 0,
      senderRole: int.tryParse('${m['sender_role'] ?? 0}') ?? 0,
      senderName: rawName.isEmpty
          ? (int.tryParse('${m['sender_role'] ?? 0}') == 0 ? 'Support' : 'User')
          : rawName,
      body: (m['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
    );
  }
}
