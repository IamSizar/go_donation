// Test double for the chat-groups slice of ModuleApi (OPOS #25284 Phase 5),
// shared by the chat-groups controller and screen tests.
//
// Only the chat-groups methods are overridden; everything else is the real
// ModuleApi. Each overridden method records its calls and then either throws
// the error set on the fake or answers from the fixture set on it, so every
// branch a test cares about is driven by its own explicit value.
//
// It behaves like the server where the controllers depend on it:
//   * messages are paged exactly as ListMessagesForMember pages them — ids
//     above `after_id`, oldest first, at most `limit` (1..100, else 50);
//   * a sent message is stored, so the next page request returns it;
//   * an answer is decided when the request ARRIVES, not when it is released
//     from a gate — so a held request really does come back stale.
//
// The row builders mirror the JSON the Go handlers serialize, every field
// included.
import 'dart:async';

import 'package:flutter_application_1/api/module_api.dart';

/// A ModuleApi whose chat-groups endpoints answer from in-memory fixtures.
class FakeChatGroupsApi extends ModuleApi {
  FakeChatGroupsApi();

  // ─── GET /chat-groups ─────────────────────────────────────────────────────

  /// Rows returned by [chatGroups] when [groupsError] is null.
  List<Map<String, dynamic>> groups = const [];

  /// When set, [chatGroups] throws this instead of returning [groups].
  Exception? groupsError;

  /// How many times [chatGroups] has been called.
  int groupsCalls = 0;

  /// When set, [chatGroups] waits for it before answering, holding the load
  /// in flight.
  Completer<void>? groupsGate;

  @override
  Future<List<Map<String, dynamic>>> chatGroups() async {
    groupsCalls++;
    final error = groupsError;
    final answer = groups;
    final gate = groupsGate;
    if (gate != null) await gate.future;
    if (error != null) throw error;
    return answer;
  }

  // ─── GET /chat-groups/connect-requests/mine ───────────────────────────────

  /// Rows returned by [myConnectRequests] when [requestsError] is null.
  List<Map<String, dynamic>> requests = const [];

  /// When set, [myConnectRequests] throws this instead of returning [requests].
  Exception? requestsError;

  /// How many times [myConnectRequests] has been called.
  int requestsCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> myConnectRequests() async {
    requestsCalls++;
    final error = requestsError;
    if (error != null) throw error;
    return requests;
  }

  // ─── GET /chat-groups/:id/messages ────────────────────────────────────────

  /// The group's whole stored history, oldest first — what the server holds.
  List<Map<String, dynamic>> transcript = [];

  /// The staff-controlled lifecycle every messages response carries.
  String lifecycle = 'open';

  /// The staff member's reason every messages response carries.
  String lifecycleReason = '';

  /// When set, [chatGroupMessages] throws this instead of answering.
  Exception? messagesError;

  /// When set, [chatGroupMessages] waits for it before answering.
  Completer<void>? messagesGate;

  /// Every page request, in order, with the paging the controller asked for.
  final messageRequests = <({int afterId, int? limit})>[];

  /// How many page requests have been made.
  int get messagesCalls => messageRequests.length;

  /// The most page requests that were ever in flight at the same moment.
  int maxConcurrentMessageRequests = 0;

  int _openMessageRequests = 0;

  @override
  Future<Map<String, dynamic>> chatGroupMessages(
    int groupId, {
    int afterId = 0,
    int? limit,
  }) async {
    messageRequests.add((afterId: afterId, limit: limit));
    _openMessageRequests++;
    if (_openMessageRequests > maxConcurrentMessageRequests) {
      maxConcurrentMessageRequests = _openMessageRequests;
    }
    try {
      final error = messagesError;
      final requested = limit ?? 0;
      final pageSize = (requested <= 0 || requested > 100) ? 50 : requested;
      final page = transcript
          .where((m) => (m['id'] as int) > afterId)
          .take(pageSize)
          .toList();
      final answer = conversationBody(
        page,
        lifecycle: lifecycle,
        lifecycleReason: lifecycleReason,
      );
      final gate = messagesGate;
      if (gate != null) await gate.future;
      if (error != null) throw error;
      return answer;
    } finally {
      _openMessageRequests--;
    }
  }

  // ─── POST /chat-groups/:id/messages ───────────────────────────────────────

  /// Every body that was successfully sent, in order.
  final sentBodies = <String>[];

  /// When set, [sendChatGroupMessage] throws this and stores nothing.
  Exception? sendError;

  /// When set, [sendChatGroupMessage] waits for it before answering.
  Completer<void>? sendGate;

  /// Succeeds like the server does: the message is appended to [transcript],
  /// so the next page request finds it, and the response carries only the
  /// new id.
  @override
  Future<Map<String, dynamic>> sendChatGroupMessage(
    int groupId,
    String body,
  ) async {
    final gate = sendGate;
    if (gate != null) await gate.future;
    final error = sendError;
    if (error != null) throw error;
    sentBodies.add(body);
    final newId = transcript.isEmpty ? 1 : (transcript.last['id'] as int) + 1;
    transcript = [
      ...transcript,
      messageRow(id: newId, senderLabel: 'You', body: body, isMine: true),
    ];
    return <String, dynamic>{'success': true, 'message_id': newId};
  }

  // ─── POST /chat-groups/:id/read ───────────────────────────────────────────

  /// Every read cursor that was successfully sent, in order.
  final markedRead = <({int groupId, int lastReadMessageId})>[];

  /// When set, [markChatGroupRead] throws this and records nothing.
  Exception? markReadError;

  @override
  Future<void> markChatGroupRead(
    int groupId, {
    required int lastReadMessageId,
  }) async {
    final error = markReadError;
    if (error != null) throw error;
    markedRead.add((groupId: groupId, lastReadMessageId: lastReadMessageId));
  }
}

/// One item of `GET /chat-groups`, shaped exactly as the Go handler writes it.
/// [title] is empty for masked groups, which is what the server sends.
Map<String, dynamic> groupRow({
  required int id,
  required String kind,
  String title = '',
  int unreadCount = 0,
  String lastMessage = '',
}) {
  return <String, dynamic>{
    'id': id,
    'kind': kind,
    'title': title,
    'unread_count': unreadCount,
    'last_message': lastMessage,
    'last_at': '2026-09-14T10:00:00Z',
  };
}

/// One item of `GET /chat-groups/connect-requests/mine`. `group_id` and
/// `decline_reason` are `omitempty` server-side, so they are left out of the
/// map entirely when null — exactly as the real response omits them.
Map<String, dynamic> connectRequestRow({
  required int id,
  required String status,
  String contextType = 'donation',
  int contextId = 42,
  String message = 'Please connect me',
  int? groupId,
  String? declineReason,
}) {
  return <String, dynamic>{
    'id': id,
    'context_type': contextType,
    'context_id': contextId,
    'message': message,
    'group_id': ?groupId,
    'status': status,
    'decline_reason': ?declineReason,
    'created_at': '2026-09-14T10:00:00Z',
  };
}

/// The `GET /chat-groups/:id/messages` response body: one page of the
/// transcript, oldest first, plus the conversation's lifecycle.
Map<String, dynamic> conversationBody(
  List<Map<String, dynamic>> items, {
  String lifecycle = 'open',
  String lifecycleReason = '',
  bool isArchived = false,
}) {
  return <String, dynamic>{
    'success': true,
    'items': items,
    'lifecycle': lifecycle,
    'lifecycle_reason': lifecycleReason,
    'is_archived': isArchived,
  };
}

/// One message as the server serializes it. There is deliberately no user-id
/// field: a masked member's identity cannot leak through a shape that has
/// nowhere to carry it.
Map<String, dynamic> messageRow({
  required int id,
  required String senderLabel,
  required String body,
  int senderMemberId = 3,
  bool isMine = false,
}) {
  return <String, dynamic>{
    'id': id,
    'sender_member_id': senderMemberId,
    'sender_label': senderLabel,
    'is_mine': isMine,
    'body': body,
    'created_at': '2026-09-14T10:00:00Z',
  };
}

/// [count] messages from another member, ids 1..[count], oldest first.
List<Map<String, dynamic>> numberedMessages(int count) => [
  for (var id = 1; id <= count; id++)
    messageRow(id: id, senderLabel: 'Donor 1', body: 'Message $id'),
];
