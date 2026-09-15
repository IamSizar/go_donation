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
  // Note #36 — the "Responsible Staff Member" who has claimed this thread,
  // if any (null = unclaimed, any admin may still reply as "Support").
  final String? assignedStaffName;

  /// Migration 117 — the staff-controlled lifecycle: open | paused | ended.
  /// Read by the invite answers (OPOS #26433), which stop offering Accept on a
  /// closed thread. Defaults to open, so an older server leaves Accept working.
  final String lifecycle;

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
    required this.assignedStaffName,
    this.lifecycle = 'open',
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
      // Only the server's trimmed name, or '' — no fallback words here
      // (OPOS #26483). The screen names an unnamed other party in the
      // reader's language through `chatThreadOtherName`.
      otherName: (m['other_name'] ?? '').toString().trim(),
      otherPhone: m['other_phone']?.toString(),
      lastMessage: m['last_message']?.toString(),
      lastMessageAt: DateTime.tryParse((m['last_message_at'] ?? '').toString()),
      unreadCount: int.tryParse('${m['unread_count'] ?? 0}') ?? 0,
      assignedStaffName:
          (m['assigned_staff_name'] as String?)?.trim().isEmpty == true
          ? null
          : m['assigned_staff_name'] as String?,
      lifecycle: (m['lifecycle'] ?? 'open').toString(),
    );
  }
}

class ChatMessage {
  final int id;
  final int threadId;
  final int senderUserId;
  final int senderRole; // 0 support/admin, 1 donor, 2 beneficiary, 3 volunteer
  /// The sender's name as the server sent it, trimmed. Empty when the server
  /// sent none: a staff account with no profile name, or a name the sender's
  /// privacy settings hide from this viewer.
  ///
  /// Deliberately no fallback word here (OPOS #26435). An English "Support"
  /// baked in at parse time reached Arabic screens; the model stays
  /// independent of the reader's language, and the screen names an unnamed
  /// sender through `chatSenderName`.
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
    return ChatMessage(
      id: int.tryParse('${m['id']}') ?? 0,
      threadId: int.tryParse('${m['thread_id']}') ?? 0,
      senderUserId: int.tryParse('${m['sender_user_id']}') ?? 0,
      senderRole: int.tryParse('${m['sender_role'] ?? 0}') ?? 0,
      senderName: (m['sender_name'] ?? '').toString().trim(),
      body: (m['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
    );
  }
}
