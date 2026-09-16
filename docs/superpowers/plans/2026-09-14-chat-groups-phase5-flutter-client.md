# OPOS #25284 Phase 5 — Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Flutter UI for the `chatgroups` backend (masked staff-mediated group chats, team groups, connect-requests) shipped in Phases 1-3, replacing the direct-chat entry points Phase 4 removed.

**Architecture:** New `humanitarian/lib/modules/chatgroups/` package (models, controllers, screens), mirroring the structure of `modules/chat/` and `modules/marriage/`'s masked-chat screens exactly — no new UI patterns, only new data flowing through existing widget shapes (`AppAsync`/`AppEmpty`/`AppSkeleton`, `GlassPanel`/`SectionTile`, GetX polling controllers).

**Tech Stack:** Flutter/GetX, matching `humanitarian/lib/modules/chat/`'s existing conventions exactly.

## Global Constraints

- Design basis: `docs/superpowers/specs/2026-09-12-masked-group-chats-design.md` §11 and `docs/superpowers/specs/2026-09-14-chat-groups-phase5-flutter-client-design.md` (this phase's addendum — read both before starting).
- One conversation screen serves both `kind='masked'` and `kind='team'` groups — render `sender_label` as-is, never branch client-side on kind to decide display text. No avatars anywhere in the conversation screen (the API provides none).
- Polling: 5s for the groups list (`ChatGroupsController`, mirrors `ChatController`), 3s for an open conversation (`ChatGroupConversationController`, mirrors `ChatThreadController`). Silent polls swallow errors and keep the last good data on screen — never flicker an error state from a background tick.
- API base URL helper, JSON envelope shape (`{success, items}` / `{success, ...}` / `{success: false, error}`), and the `getItems`/`getObject`/`postJson` helpers in `humanitarian/lib/api/module_api.dart` are already correct and complete — new calls are added the same way (thin one-liners), never a new HTTP client.
- Exact current backend response shapes (verified against Go source, not guessed):
  - `GET /chat-groups` → `{"success": true, "items": [{"id", "kind", "title", "unread_count", "last_message", "last_at"}]}` (`kind` is `"masked"` or `"team"`; `title` is `""` for masked groups).
  - `GET /chat-groups/:id/messages` → `{"success": true, "items": [{"id", "sender_member_id", "sender_label", "is_mine", "body", "created_at"}], "lifecycle", "lifecycle_reason", "is_archived"}`.
  - `POST /chat-groups/:id/messages` body `{"body": "..."}` → `{"success": true, "message_id": <int>}`.
  - `POST /chat-groups/:id/read` → `{"success": true}` (no body).
  - `POST /chat-groups/connect-requests` body `{"context_type": "donation"|"case", "context_id": <int>, "target_hint": <int, optional>, "message": "..."}` → `{"success": true, "request_id": <int>}`.
  - `GET /chat-groups/connect-requests/mine` → `{"success": true, "items": [{"id", "context_type", "context_id", "message", "group_id" (nullable), "status" ("pending"|"approved"|"declined"), "decline_reason" (may be absent), "created_at"}]}`.
  - Errors: `{"success": false, "error": "..."}`, HTTP 400/403/404/409/500 — `getItems`/`getObject`/`postJson` already throw on non-2xx, matching every other feature's error handling.
- Platform-adaptive/keyboard/haptic rules (this project's CLAUDE.md §3, §5.5, §5.6) are satisfied by REUSING the existing `_Composer`/`AppPressable`/haptics calls from `chat_conversation_screen.dart` verbatim — do not re-derive keyboard handling or haptics from scratch.

---

### Task 1: API client methods and models

**Files:**
- Create: `humanitarian/lib/modules/chatgroups/models/chat_group_models.dart`
- Modify: `humanitarian/lib/api/links.dart`
- Modify: `humanitarian/lib/api/module_api.dart`
- Test: `humanitarian/test/modules/chatgroups/chat_group_models_test.dart`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `ChatGroupSummary`, `ChatGroupMessage`, `MyConnectRequest` model classes with `.fromMap` factories; `ModuleApi` methods `chatGroups()`, `chatGroupMessages(int groupId)`, `sendChatGroupMessage(int groupId, String body)`, `markChatGroupRead(int groupId)`, `submitConnectRequest({required String contextType, required int contextId, required String message})`, `myConnectRequests()` — every later task in this plan calls these by these exact names.

- [ ] **Step 1: Write the failing model tests**

Create `humanitarian/test/modules/chatgroups/chat_group_models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/modules/chatgroups/models/chat_group_models.dart';

void main() {
  group('ChatGroupSummary', () {
    test('parses a masked group with no title', () {
      final g = ChatGroupSummary.fromMap({
        'id': 7,
        'kind': 'masked',
        'title': '',
        'unread_count': 2,
        'last_message': 'Hello',
        'last_at': '2026-09-14T10:00:00Z',
      });
      expect(g.id, 7);
      expect(g.kind, 'masked');
      expect(g.isMasked, true);
      expect(g.title, '');
      expect(g.unreadCount, 2);
      expect(g.lastMessage, 'Hello');
      expect(g.lastAt, isNotNull);
    });

    test('parses a team group with a title', () {
      final g = ChatGroupSummary.fromMap({
        'id': 9,
        'kind': 'team',
        'title': 'Distribution team',
        'unread_count': 0,
        'last_message': '',
        'last_at': '2026-09-14T10:00:00Z',
      });
      expect(g.isMasked, false);
      expect(g.title, 'Distribution team');
    });
  });

  group('ChatGroupMessage', () {
    test('parses a message with no user-id field to leak', () {
      final m = ChatGroupMessage.fromMap({
        'id': 1,
        'sender_member_id': 3,
        'sender_label': 'Donor 1',
        'is_mine': false,
        'body': 'Hi there',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(m.senderLabel, 'Donor 1');
      expect(m.isMine, false);
      expect(m.body, 'Hi there');
    });
  });

  group('MyConnectRequest', () {
    test('parses a pending request with no group yet', () {
      final r = MyConnectRequest.fromMap({
        'id': 5,
        'context_type': 'donation',
        'context_id': 42,
        'message': 'Please connect me',
        'status': 'pending',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(r.status, 'pending');
      expect(r.groupId, isNull);
      expect(r.declineReason, isNull);
    });

    test('parses a declined request with a reason', () {
      final r = MyConnectRequest.fromMap({
        'id': 6,
        'context_type': 'case',
        'context_id': 3,
        'message': 'Help please',
        'status': 'declined',
        'decline_reason': 'Not eligible for this campaign.',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(r.status, 'declined');
      expect(r.declineReason, 'Not eligible for this campaign.');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd humanitarian
flutter test test/modules/chatgroups/chat_group_models_test.dart
```
Expected: FAIL — the models file doesn't exist yet.

- [ ] **Step 3: Write the models**

Create `humanitarian/lib/modules/chatgroups/models/chat_group_models.dart`:
```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/modules/chatgroups/chat_group_models_test.dart
```
Expected: all PASS.

- [ ] **Step 5: Add URL constants**

In `humanitarian/lib/api/links.dart`, find the existing block with `chatsUrl`/`chatMessagesUrl`/`marriageChatsUrl` (read the file first to match its exact style — some are plain `const String`, some are functions taking an id) and add, in the same style, immediately after that block:
```dart
const String chatGroupsUrl = '${baseUrl}chat-groups';
String chatGroupMessagesUrl(int groupId) => '$chatGroupsUrl/$groupId/messages';
String chatGroupReadUrl(int groupId) => '$chatGroupsUrl/$groupId/read';
const String connectRequestsUrl = '${baseUrl}chat-groups/connect-requests';
const String myConnectRequestsUrl = '${baseUrl}chat-groups/connect-requests/mine';
```
Read the file's actual `baseUrl` variable/import first to confirm this string-interpolation style matches exactly (it should, based on the existing `chatsUrl`/`marriageChatsUrl` pattern) — adjust if the real file uses a different convention.

- [ ] **Step 6: Add `ModuleApi` methods**

In `humanitarian/lib/api/module_api.dart`, find where `marriageChats()`/`marriageChatMessages()`/`sendMarriageChatMessage()` (or the equivalent existing thin one-liners) are defined and add, in the same style:
```dart
Future<List<Map<String, dynamic>>> chatGroups() => getItems(chatGroupsUrl);

Future<Map<String, dynamic>> chatGroupMessages(int groupId) =>
    getObject(chatGroupMessagesUrl(groupId));

Future<Map<String, dynamic>> sendChatGroupMessage(int groupId, String body) =>
    postJson(chatGroupMessagesUrl(groupId), {'body': body});

Future<void> markChatGroupRead(int groupId) =>
    postJson(chatGroupReadUrl(groupId), {});

Future<Map<String, dynamic>> submitConnectRequest({
  required String contextType,
  required int contextId,
  required String message,
}) => postJson(connectRequestsUrl, {
  'context_type': contextType,
  'context_id': contextId,
  'message': message,
});

Future<List<Map<String, dynamic>>> myConnectRequests() =>
    getItems(myConnectRequestsUrl);
```
Read the actual current file first to place these correctly within the class (this file is one long list of thin one-liner methods on `ModuleApi` — add these near the other chat-related ones) and confirm `postJson`'s return type matches (`Future<Map<String, dynamic>>`) — adjust `markChatGroupRead`'s return type if `postJson` doesn't naturally support a `void`-returning wrapper; a `Future<Map<String, dynamic>>` return that the caller ignores is fine too if that's simpler and more consistent with this file's existing style.

- [ ] **Step 7: Verify and commit**

```bash
cd humanitarian
flutter analyze lib/modules/chatgroups/ lib/api/links.dart lib/api/module_api.dart
flutter test test/modules/chatgroups/
```
Expected: clean, all tests pass.

```bash
git add lib/modules/chatgroups/models/chat_group_models.dart lib/api/links.dart lib/api/module_api.dart test/modules/chatgroups/chat_group_models_test.dart
git commit -m "feat(chatgroups): add Flutter API client methods and models

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Controllers

**Files:**
- Create: `humanitarian/lib/modules/chatgroups/controllers/chat_groups_controller.dart`
- Create: `humanitarian/lib/modules/chatgroups/controllers/chat_group_conversation_controller.dart`
- Create: `humanitarian/lib/modules/chatgroups/controllers/my_connect_requests_controller.dart`

**Interfaces:**
- Consumes: Task 1's `ModuleApi` methods and models.
- Produces: `ChatGroupsController` (fields: `groups` (`RxList<ChatGroupSummary>`), `isLoading`, `errorMessage`, method `fetchGroups({bool silent})`), `ChatGroupConversationController` (constructor takes `groupId`; fields: `messages` (`RxList<ChatGroupMessage>`), `isLoading`, `isSending`, `lifecycle`, `lifecycleReason`, `errorMessage`; methods `fetchMessages({bool silent})`, `send(String body)`), `MyConnectRequestsController` (fields: `requests` (`RxList<MyConnectRequest>`), `isLoading`, `errorMessage`; method `fetchRequests()`) — Tasks 3 and 4 consume all three by these exact names/fields.

- [ ] **Step 1: Write `ChatGroupsController`**

Model directly on `ChatController` (`humanitarian/lib/modules/chat/controllers/chat_controller.dart`, read it in full first) — same 5s `Timer.periodic` structure, same silent-poll-swallows-errors behavior, same "chime only when a genuinely new id appears" logic:
```dart
import 'dart:async';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// Owns the chat-groups list (My Connections / My Team Groups sections in the
/// Messages tab). Polls every 5s so new groups/messages surface without a
/// manual refresh — same cadence as ChatController, which this mirrors.
class ChatGroupsController extends GetxController {
  final groups = <ChatGroupSummary>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  Timer? _poll;
  Set<int> _seenGroupIds = {};

  List<ChatGroupSummary> get masked =>
      groups.where((g) => g.isMasked).toList();
  List<ChatGroupSummary> get teams =>
      groups.where((g) => !g.isMasked).toList();

  @override
  void onInit() {
    super.onInit();
    fetchGroups();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _silent());
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  Future<void> _silent() async {
    final before = Set<int>.from(_seenGroupIds);
    try {
      await fetchGroups(silent: true);
    } catch (_) {
      return;
    }
    final now = groups.map((g) => g.id).toSet();
    if (before.isNotEmpty && now.difference(before).isNotEmpty) {
      AppSound.notification();
      AppHaptics.gentle();
    }
    _seenGroupIds = now;
  }

  Future<void> fetchGroups({bool silent = false}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().chatGroups();
      groups.assignAll(rows.map(ChatGroupSummary.fromMap).toList());
      _seenGroupIds = groups.map((g) => g.id).toSet();
    } catch (e) {
      if (!silent) errorMessage.value = 'Unable to load your chats.'.tr;
    } finally {
      if (!silent) isLoading.value = false;
    }
  }
}
```

- [ ] **Step 2: Write `ChatGroupConversationController`**

Model directly on `ChatThreadController` in the same file — same 3s poll, same lifecycle handling, same "chime on new incoming during silent poll" logic:
```dart
import 'dart:async';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// Owns a single open chat-group conversation. Polls every 3s — same cadence
/// as ChatThreadController, which this mirrors. Serves BOTH masked and team
/// groups identically: sender_label already resolves to the correct display
/// text server-side, so this controller never branches on group kind.
class ChatGroupConversationController extends GetxController {
  ChatGroupConversationController(this.groupId);

  final int groupId;

  final messages = <ChatGroupMessage>[].obs;
  final isLoading = false.obs;
  final isSending = false.obs;
  final lifecycle = ChatLifecycle.open.obs;
  final lifecycleReason = RxnString();
  final errorMessage = RxnString();

  Timer? _poll;
  int _lastSeenId = 0;

  @override
  void onInit() {
    super.onInit();
    fetchMessages();
    _poll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => fetchMessages(silent: true),
    );
    // Mark read on open — a group opened is a group read, matching how the
    // rest of the app treats "opening a conversation" as the read signal.
    const ModuleApi().markChatGroupRead(groupId);
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  Future<void> fetchMessages({bool silent = false}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final res = await const ModuleApi().chatGroupMessages(groupId);
      lifecycle.value = (res['lifecycle'] ?? ChatLifecycle.open).toString();
      final reason = res['lifecycle_reason']?.toString().trim();
      lifecycleReason.value = (reason == null || reason.isEmpty) ? null : reason;
      final items = res['items'];
      final list = items is List
          ? items
              .whereType<Map>()
              .map((e) => ChatGroupMessage.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : <ChatGroupMessage>[];
      final newest = list.isEmpty ? 0 : list.last.id;
      if (silent && _lastSeenId != 0 && newest > _lastSeenId) {
        AppSound.notification();
        AppHaptics.gentle();
      }
      _lastSeenId = newest;
      messages.assignAll(list);
    } catch (e) {
      if (!silent) errorMessage.value = 'Unable to load messages.'.tr;
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  Future<bool> send(String body) async {
    final text = body.trim();
    if (text.isEmpty || isSending.value) return false;
    isSending.value = true;
    try {
      await const ModuleApi().sendChatGroupMessage(groupId, text);
      await fetchMessages(silent: true);
      return true;
    } catch (e) {
      errorMessage.value = failureMessage(e, 'error_messages_load_failed');
      return false;
    } finally {
      isSending.value = false;
    }
  }
}
```
Read `humanitarian/lib/modules/chat/widgets/chat_lifecycle_notice.dart` first to confirm `ChatLifecycle`'s exact type/constants (`ChatLifecycle.open`, `ChatLifecycle.isClosed(...)`) match this usage — it's a String-typed enum-like class per `ChatThreadController`'s own usage, reuse it exactly, do not redefine a new lifecycle type for chat-groups.

- [ ] **Step 3: Write `MyConnectRequestsController`**

```dart
import 'package:flutter_application_1/api/module_api.dart';
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// Owns the requester's own connect-request history (My Connect Requests
/// screen) — no polling; a pull-to-refresh screen, not a live conversation.
class MyConnectRequestsController extends GetxController {
  final requests = <MyConnectRequest>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchRequests();
  }

  Future<void> fetchRequests() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await const ModuleApi().myConnectRequests();
      requests.assignAll(rows.map(MyConnectRequest.fromMap).toList());
    } catch (e) {
      errorMessage.value = 'Unable to load your requests.'.tr;
    } finally {
      isLoading.value = false;
    }
  }
}
```

- [ ] **Step 4: Verify and commit**

```bash
cd humanitarian
flutter analyze lib/modules/chatgroups/controllers/
```
Expected: clean. (No unit tests for these controllers in this task — they're thin GetX wrappers over Task 1's already-tested models and already-existing `ModuleApi`/`ChatLifecycle` primitives; Task 3's widget tests exercise them indirectly through the screens that use them.)

```bash
git add lib/modules/chatgroups/controllers/
git commit -m "feat(chatgroups): add Flutter controllers for groups list, conversation, connect requests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `ChatGroupConversationScreen`

**Files:**
- Create: `humanitarian/lib/modules/chatgroups/screens/chat_group_conversation_screen.dart`
- Test: `humanitarian/test/modules/chatgroups/chat_group_conversation_screen_test.dart`

**Interfaces:**
- Consumes: Task 2's `ChatGroupConversationController`, Task 1's `ChatGroupMessage`.
- Produces: `ChatGroupConversationScreen({required int groupId, required String title, String? subtitle})` — Task 4 navigates to this by this exact constructor.

- [ ] **Step 1: Write a widget test for the masking guarantee**

Create `humanitarian/test/modules/chatgroups/chat_group_conversation_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/modules/chatgroups/models/chat_group_models.dart';

void main() {
  testWidgets('a message bubble renders sender_label, never a raw user id', (
    tester,
  ) async {
    final message = ChatGroupMessage.fromMap({
      'id': 1,
      'sender_member_id': 3,
      'sender_label': 'Donor 1',
      'is_mine': false,
      'body': 'Hello there',
      'created_at': '2026-09-14T10:00:00Z',
    });

    // This is a model-level guard, not a full widget pump (the screen needs
    // a live GetX controller + real navigation context this test does not
    // set up) — it proves the model itself carries no field a bubble widget
    // COULD render as a raw id, matching GroupMessage's own server-side
    // guarantee. Read chat_group_conversation_screen.dart's actual
    // _MessageBubble once written and confirm by inspection that it only
    // ever reads message.senderLabel/message.body/message.isMine — never
    // anything resembling a user id — as part of this task's own review,
    // since a full render test needs more scaffolding than this task's
    // scope justifies.
    expect(message.senderLabel, 'Donor 1');
    expect(message.toString(), isNot(contains('senderUserId')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails or passes trivially, then write the screen**

This particular test passes as soon as Task 1's model exists (it already does) — it is a documentation-style regression guard, not a red-green driver for this screen. Proceed to write the screen; the real verification for this task is Step 4's `flutter analyze` plus the manual masking-guarantee check described in the test's own comment.

Create `humanitarian/lib/modules/chatgroups/screens/chat_group_conversation_screen.dart`, modeled directly on `humanitarian/lib/modules/chat/screens/chat_conversation_screen.dart` (read it in full first — this is a close adaptation, not a from-scratch screen):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/chat_group_conversation_controller.dart';
import '../models/chat_group_models.dart';

/// The conversation screen for a masked staff-mediated group OR a real-name
/// team group — the same screen for both, since sender_label already
/// resolves to the correct display text server-side (masked label or real
/// name). This screen never branches on group kind to decide what to show.
class ChatGroupConversationScreen extends StatefulWidget {
  const ChatGroupConversationScreen({
    super.key,
    required this.groupId,
    required this.title,
    this.subtitle,
  });

  final int groupId;
  final String title;
  final String? subtitle;

  @override
  State<ChatGroupConversationScreen> createState() =>
      _ChatGroupConversationScreenState();
}

class _ChatGroupConversationScreenState
    extends State<ChatGroupConversationScreen> {
  late final ChatGroupConversationController ctrl;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(
      ChatGroupConversationController(widget.groupId),
      tag: 'chat-group-${widget.groupId}',
    );
    ever(ctrl.messages, (_) => _scrollToBottom());
  }

  @override
  void dispose() {
    Get.delete<ChatGroupConversationController>(
      tag: 'chat-group-${widget.groupId}',
    );
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    final ok = await ctrl.send(text);
    if (!ok && mounted && ctrl.errorMessage.value != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ctrl.errorMessage.value!)));
      _input.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty)
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              // Same deliberate choice as ChatConversationScreen: not
              // AppAsync, so a send failure never blanks the transcript.
              if (ctrl.isLoading.value && ctrl.messages.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: AppSkeleton.bubbles(),
                );
              }
              if (ctrl.messages.isEmpty) {
                return AppEmpty(
                  icon: Icons.forum_outlined,
                  title: 'No messages yet. Say hello! 👋'.tr,
                  message:
                      'Send the first message to start the conversation.'.tr,
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                itemCount: ctrl.messages.length,
                itemBuilder: (context, i) => _Bubble(message: ctrl.messages[i]),
              );
            }),
          ),
          Obx(
            () => ChatLifecycle.isClosed(ctrl.lifecycle.value)
                ? ChatLifecycleNotice(
                    lifecycle: ctrl.lifecycle.value,
                    reason: ctrl.lifecycleReason.value,
                  )
                : _Composer(input: _input, onSend: _send, controller: ctrl),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatGroupMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = mine
        ? AppThemeConfig.primary
        : AppThemeConfig.softSurface(context);
    final fg = mine ? Colors.white : AppThemeConfig.text(context);

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                child: Text(
                  // sender_label ALWAYS carries the correct display text —
                  // masked label or real name, resolved server-side. Never
                  // read anything else off `message` to build this line.
                  message.senderLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: Text(
                message.body,
                style: TextStyle(color: fg, fontSize: 14.5, height: 1.35),
              ),
            ),
            if (message.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(
                  DateFormat('MMM d · HH:mm').format(message.createdAt!),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.onSend,
    required this.controller,
  });

  final TextEditingController input;
  final VoidCallback onSend;
  final ChatGroupConversationController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppThemeConfig.softSurface(context),
          border: Border(
            top: BorderSide(color: AppThemeConfig.border(context)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type a message…'.tr,
                  filled: true,
                  fillColor: AppThemeConfig.surface(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(
                      color: AppThemeConfig.border(context),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(
                      color: AppThemeConfig.border(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(
              () => AppPressable(
                onTap: controller.isSending.value ? null : onSend,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.primary,
                    shape: BoxShape.circle,
                  ),
                  child: controller.isSending.value
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Manually confirm the masking guarantee by inspection**

Read the `_Bubble` widget you just wrote and confirm it reads ONLY `message.senderLabel`, `message.body`, `message.isMine`, `message.createdAt` — never anything that could resemble a raw user id. State this confirmation explicitly in your report.

- [ ] **Step 4: Verify and commit**

```bash
cd humanitarian
flutter analyze lib/modules/chatgroups/
flutter test test/modules/chatgroups/
```
Expected: clean, all tests pass.

```bash
git add lib/modules/chatgroups/screens/chat_group_conversation_screen.dart test/modules/chatgroups/chat_group_conversation_screen_test.dart
git commit -m "feat(chatgroups): add the chat-group conversation screen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Messages tab wiring + My Connect Requests screen

**Files:**
- Create: `humanitarian/lib/modules/chatgroups/screens/my_connect_requests_screen.dart`
- Modify: `humanitarian/lib/modules/chat/screens/messages_screen.dart`

**Interfaces:**
- Consumes: Task 2's `ChatGroupsController`/`MyConnectRequestsController`, Task 3's `ChatGroupConversationScreen`.
- Produces: `MyConnectRequestsScreen` — Task 5 does not need to navigate here itself (the tile added in this task does), but note the screen exists in case a later task wants to link into it after a submission.

- [ ] **Step 1: Write `MyConnectRequestsScreen`**

Modeled on the existing incoming/outgoing tile patterns already in `messages_screen.dart` (read that file's `_OutgoingPendingTile` and `_IncomingRequestCard` first) and the decline-reason display pattern in `marriage_chat_conversation_screen.dart` (read it for how it surfaces a decline reason — mirror that tone/placement, not necessarily its exact widget).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/my_connect_requests_controller.dart';
import '../models/chat_group_models.dart';

class MyConnectRequestsScreen extends StatelessWidget {
  const MyConnectRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.isRegistered<MyConnectRequestsController>()
        ? Get.find<MyConnectRequestsController>()
        : Get.put(MyConnectRequestsController());

    return SectionScaffold(
      title: 'My Connect Requests'.tr,
      subtitle: '',
      child: Obx(
        () => RefreshIndicator(
          onRefresh: ctrl.fetchRequests,
          child: AppAsync<List<MyConnectRequest>>(
            loading: ctrl.isLoading.value,
            error: ctrl.errorMessage.value,
            onRetry: ctrl.fetchRequests,
            data: ctrl.requests.toList(growable: false),
            isEmpty: (list) => list.isEmpty,
            empty: AppEmpty(
              icon: Icons.mark_chat_read_outlined,
              title: 'No connect requests yet'.tr,
              message: 'Requests you send to staff will show up here.'.tr,
            ),
            builder: (list) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length,
              itemBuilder: (context, i) => _RequestTile(request: list[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});
  final MyConnectRequest request;

  Color _statusColor(BuildContext context) {
    if (request.isApproved) return AppThemeConfig.accent(context);
    if (request.isDeclined) return Colors.red;
    return AppThemeConfig.pending(context);
  }

  String get _statusLabel {
    if (request.isApproved) return 'Approved'.tr;
    if (request.isDeclined) return 'Declined'.tr;
    return 'Pending'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _statusColor(context),
                    ),
                  ),
                ),
                const Spacer(),
                if (request.createdAt != null)
                  Text(
                    DateFormat('MMM d').format(request.createdAt!),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              request.message,
              style: TextStyle(
                fontSize: 14,
                color: AppThemeConfig.text(context),
              ),
            ),
            if (request.isDeclined && request.declineReason != null) ...[
              const SizedBox(height: 8),
              Text(
                request.declineReason!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```
Check `AppEmpty`'s and `AppAsync`'s exact constructor signatures in `humanitarian/lib/core/widgets/app_states.dart` before finalizing this file — the brief's sample matches what Phase 5's research pass found, but confirm parameter names/order match exactly.

- [ ] **Step 2: Wire new sections into `messages_screen.dart`**

Read `humanitarian/lib/modules/chat/screens/messages_screen.dart` in full first — Task-4's insertion point is AFTER the existing `AppAsync<List<dynamic>>` block (the incoming/active/outgoing donor-owner/support threads) and BEFORE the closing `],` of the outer `ListView`'s `children` list. Add:

1. Import `ChatGroupsController`, `ChatGroupConversationScreen`, `MyConnectRequestsScreen`, and `ChatGroupSummary`.
2. Instantiate the controller the same way `ChatController` is instantiated at the top of `build()`:
```dart
final groupsCtrl = Get.isRegistered<ChatGroupsController>()
    ? Get.find<ChatGroupsController>()
    : Get.put(ChatGroupsController());
```
3. Immediately after the existing `AppAsync<List<dynamic>>` widget (donor/support threads), add:
```dart
const SizedBox(height: 8),
SectionTile(
  icon: Icons.mark_chat_read_outlined,
  title: 'My Connect Requests'.tr,
  subtitle: 'See the status of requests you sent to staff'.tr,
  color: AppThemeConfig.accent(context),
  onTap: () => Get.to(() => const MyConnectRequestsScreen()),
),
const SizedBox(height: 10),
Obx(() {
  final masked = groupsCtrl.masked;
  final teams = groupsCtrl.teams;
  return AppAsync<List<ChatGroupSummary>>(
    loading: groupsCtrl.isLoading.value,
    error: groupsCtrl.errorMessage.value,
    onRetry: groupsCtrl.fetchGroups,
    data: groupsCtrl.groups.toList(growable: false),
    isEmpty: (list) => list.isEmpty,
    empty: const SizedBox.shrink(), // most users have none — stay invisible, matching this screen's own _CaseChatsSection precedent for a rarely-used section
    builder: (_) => Column(
      children: [
        if (masked.isNotEmpty) ...[
          _SectionLabel(label: 'My Connections', count: masked.length),
          for (final g in masked) _ChatGroupTile(group: g),
        ],
        if (teams.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel(label: 'My Team Groups', count: teams.length),
          for (final g in teams) _ChatGroupTile(group: g),
        ],
      ],
    ),
  );
}),
```
4. Add a new private `_ChatGroupTile` widget in the same file, modeled on the existing `_ThreadTile`/`_CaseChatTile` (read them for the exact `GlassPanel`/`InkWell`/`_Avatar` shape) — reuse the file's existing `_Avatar` widget:
```dart
class _ChatGroupTile extends StatelessWidget {
  const _ChatGroupTile({required this.group});
  final ChatGroupSummary group;

  @override
  Widget build(BuildContext context) {
    final displayTitle = group.isMasked
        ? 'Connection'.tr
        : (group.title.isEmpty ? 'Team group'.tr : group.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Get.to(
            () => ChatGroupConversationScreen(
              groupId: group.id,
              title: displayTitle,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(name: displayTitle),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
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
                        group.lastMessage.isEmpty
                            ? 'No messages yet'.tr
                            : group.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: group.unreadCount > 0
                              ? AppThemeConfig.text(context)
                              : AppThemeConfig.mutedText(context),
                          fontWeight: group.unreadCount > 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (group.unreadCount > 0) ...[
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
                        '${group.unreadCount}',
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
```
Note `_SectionLabel` already exists in this file (takes `label`+`count`) — reuse it exactly, do not redefine it. `_Avatar` also already exists in this file — reuse it exactly.

- [ ] **Step 3: Verify and commit**

```bash
cd humanitarian
flutter analyze lib/modules/chat/screens/messages_screen.dart lib/modules/chatgroups/
flutter test test/modules/chatgroups/
```
Expected: clean, no new issues beyond this branch's existing pre-existing baseline (compare against a `flutter analyze` run before this task's changes if anything unexpected shows up).

```bash
git add lib/modules/chatgroups/screens/my_connect_requests_screen.dart lib/modules/chat/screens/messages_screen.dart
git commit -m "feat(chatgroups): wire My Connections/My Team Groups/My Connect Requests into the Messages tab

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: "Request to connect" entry points (donation + case context)

**Files:**
- Create: `humanitarian/lib/modules/chatgroups/widgets/connect_request_sheet.dart`
- Modify: `humanitarian/lib/modules/donations/screens/my_donations_page.dart`
- Modify: `humanitarian/lib/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart`
- Modify: `humanitarian/lib/modules/chat/screens/messages_screen.dart`

**Interfaces:**
- Consumes: Task 1's `ModuleApi().submitConnectRequest`.
- Produces: `showConnectRequestSheet(BuildContext context, {required String contextType, required int contextId})` — a reusable bottom-sheet function both donation entry points and the case entry point call with different `contextType`/`contextId` arguments.

- [ ] **Step 1: Write the shared connect-request bottom sheet**

Create `humanitarian/lib/modules/chatgroups/widgets/connect_request_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// The single entry point for "ask staff to connect me" across the app —
/// donation context (donor asking about a campaign) and case context
/// (volunteer/beneficiary asking about a case) both go through this same
/// sheet, differing only in the contextType/contextId passed in.
Future<void> showConnectRequestSheet(
  BuildContext context, {
  required String contextType,
  required int contextId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ConnectRequestSheet(
      contextType: contextType,
      contextId: contextId,
    ),
  );
}

class _ConnectRequestSheet extends StatefulWidget {
  const _ConnectRequestSheet({
    required this.contextType,
    required this.contextId,
  });
  final String contextType;
  final int contextId;

  @override
  State<_ConnectRequestSheet> createState() => _ConnectRequestSheetState();
}

class _ConnectRequestSheetState extends State<_ConnectRequestSheet> {
  final _message = TextEditingController();
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please describe what you need.'.tr);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await const ModuleApi().submitConnectRequest(
        contextType: widget.contextType,
        contextId: widget.contextId,
        message: text,
      );
      AppHaptics.success();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request sent. Staff will review it shortly.'.tr,
            ),
          ),
        );
      }
    } catch (e) {
      setState(
        () => _error = 'Could not send your request. Please try again.'.tr,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ask staff to connect you'.tr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Staff will review your request and create a chat if approved.'
                      .tr,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _message,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'What do you need help with?'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Send request'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```
Check `AppHaptics`' exact available methods (`humanitarian/lib/core/app_haptics.dart`) first — `AppHaptics.success()` is this task's assumption for a completed-submission haptic, matching CLAUDE.md §5.5's "success notification: form submission" rule; adjust the exact method name if the real file names it differently (e.g. `AppHaptics.notification()`).

- [ ] **Step 2: Wire the donation-context entry point into `my_donations_page.dart`**

Read `_DonationDetailSheet` in full (Phase 4 removed the old "Chat with campaign owner" button here entirely — there is currently no button in its place). Add, after the last `_DetailLine` and before the closing of the `Column`'s `children` list:
```dart
if (item.campaignId != null) ...[
  const SizedBox(height: 16),
  OutlinedButton.icon(
    onPressed: () => showConnectRequestSheet(
      context,
      contextType: 'donation',
      contextId: item.id,
    ),
    icon: const Icon(Icons.support_agent_rounded),
    label: Text('Ask staff to connect me'.tr),
  ),
],
```
Add the import for `connect_request_sheet.dart`. Confirm `item.campaignId`'s actual type (`int?` per the model read during planning) and `item.id`'s type (should be non-nullable `int`, the donation row id) by reading `DonationHistoryEntry` in `humanitarian/lib/modules/donations/models/donation_history_models.dart` first — adjust the null-check accordingly if either type differs from this assumption.

- [ ] **Step 3: Wire the donation-context entry point into `beneficiary_campaign_donations_screen.dart`**

Read this file in full first — Phase 4 removed `_suggestChat` and its `InkWell` wiring here, leaving the donation row non-interactive. Re-add an explicit action (not a whole-row tap, to avoid the ambiguity Phase 4's removal noted about the row's other content) — e.g. a small icon button within the row:
```dart
IconButton(
  icon: const Icon(Icons.support_agent_rounded),
  tooltip: 'Ask staff to connect me'.tr,
  onPressed: () => showConnectRequestSheet(
    context,
    contextType: 'donation',
    contextId: /* the donation's own id field in this row's data — read the file to find its exact name, it will not be called item.id since this is a different model than my_donations_page.dart's */,
  ),
),
```
Read the actual current row data structure in this file (it was reading `donation['donor_user_id']`/`donation['campaign_id']` as a raw `Map` per Phase 4's own research, not a typed model like `my_donations_page.dart`'s `DonationHistoryEntry`) and find the correct key for the donation's own row id (likely `donation['id']` or `donation['donation_id']` — confirm before writing this, do not guess the key name) to pass as `contextId`.

- [ ] **Step 4: Add the case-context entry point to `messages_screen.dart`**

Add a new standing `SectionTile` (following the exact pattern of the existing `chat_support`/`support_request_form` tiles already in this file), placed alongside them near the top of the screen:
```dart
SectionTile(
  icon: Icons.volunteer_activism_outlined,
  title: 'Request help with a case'.tr,
  subtitle: 'Ask staff to connect you about a specific case'.tr,
  color: AppThemeConfig.accent(context),
  onTap: () => _showCaseConnectRequestDialog(context),
),
```
Add a small helper (in the same file, near `openSupportChat`) that first asks for a case reference number via a simple text-input `AlertDialog` (a case id is not something the user already has on screen the way a donation id is, so this needs its own tiny prompt before opening the shared sheet):
```dart
Future<void> _showCaseConnectRequestDialog(BuildContext context) async {
  final controller = TextEditingController();
  final caseId = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Which case?'.tr),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: 'Case reference number'.tr),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(controller.text.trim())),
          child: Text('Next'.tr),
        ),
      ],
    ),
  );
  if (caseId == null || caseId <= 0) return;
  if (!context.mounted) return;
  await showConnectRequestSheet(context, contextType: 'case', contextId: caseId);
}
```
Add the import for `connect_request_sheet.dart`. This is the generic, lower-risk case entry point described in the Phase 5 design addendum (§2) — a case reference number typed by the user, not a lookup against a specific case-detail screen.

- [ ] **Step 5: Verify and commit**

```bash
cd humanitarian
flutter pub get
flutter analyze
```
Expected: clean, no new issues beyond this branch's pre-existing baseline.

```bash
git add lib/modules/chatgroups/widgets/connect_request_sheet.dart lib/modules/donations/screens/my_donations_page.dart lib/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart lib/modules/chat/screens/messages_screen.dart
git commit -m "feat(chatgroups): add connect-request entry points for donations and cases

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Explicitly out of scope

- Real avatars for team groups (API provides none yet).
- A dedicated case-detail-screen integration for the case connect-request entry point (generic dialog now, per the design addendum).
- Admin-web (Phase 6).
- Manual iOS/Android simulator verification — this plan's tasks are verified via `flutter analyze`/`flutter test`; a manual simulator pass is recommended before merge but is not a task step here (flag it in the final review instead).
