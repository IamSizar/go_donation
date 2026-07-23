import 'dart:async';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:get/get.dart';

import '../models/chat_models.dart';

/// Owns the thread list (the Messages tab). Polls every 5s so accepted
/// requests and new messages surface without a manual refresh.
class ChatController extends GetxController {
  final threads = <ChatThread>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  Timer? _poll;
  Set<int> _seenThreadIds = {};

  int get totalUnread =>
      threads.fold(0, (sum, t) => sum + t.unreadCount) +
      threads.where((t) => t.incomingPending).length;

  @override
  void onInit() {
    super.onInit();
    fetchThreads();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _silent());
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  Future<void> _silent() async {
    final before = Set<int>.from(_seenThreadIds);
    try {
      await fetchThreads(silent: true);
    } catch (_) {
      return;
    }
    final now = threads.map((t) => t.id).toSet();
    // Chime when a new thread (e.g. an accepted request becoming active) shows.
    if (before.isNotEmpty && now.difference(before).isNotEmpty) {
      AppSound.notification();
      AppHaptics.gentle();
    }
    _seenThreadIds = now;
  }

  Future<void> fetchThreads({bool silent = false}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().getItems(chatsUrl);
      threads.assignAll(rows.map(ChatThread.fromMap).toList());
      _seenThreadIds = threads.map((t) => t.id).toSet();
    } catch (e) {
      if (!silent) errorMessage.value = 'Unable to load your chats.'.tr;
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Opens or finds a chat. Returns the thread id, its status, and whether it
  /// already existed (already==true + status active → just open it; otherwise
  /// it's a fresh pending request awaiting the other party's accept).
  Future<({int threadId, String status, bool already})> requestChat({
    int? donationId,
    int? donorUserId,
    int? campaignId,
  }) async {
    final body = <String, dynamic>{};
    if (donationId != null) body['donation_id'] = donationId;
    if (donorUserId != null) body['donor_user_id'] = donorUserId;
    if (campaignId != null) body['campaign_id'] = campaignId;
    final res = await const ModuleApi().postJson(chatRequestUrl, body);
    await fetchThreads(silent: true);
    return (
      threadId: int.tryParse('${res['thread_id']}') ?? 0,
      status: (res['status'] ?? 'pending').toString(),
      already: res['already'] == true,
    );
  }

  /// Opens (or reuses) a direct chat with the configured support/tech staff
  /// account (#45) — powers "Message the staff team" entry points across
  /// sections (Marriage and similar).
  Future<({int threadId, String status, bool already})> requestSupportChat() async {
    final res = await const ModuleApi().postJson(chatSupportUrl, {});
    await fetchThreads(silent: true);
    return (
      threadId: int.tryParse('${res['thread_id']}') ?? 0,
      status: (res['status'] ?? 'pending').toString(),
      already: res['already'] == true,
    );
  }

  Future<void> accept(int threadId) async {
    await const ModuleApi().postJson(chatAcceptUrl(threadId), {});
    await fetchThreads(silent: true);
  }

  Future<void> decline(int threadId) async {
    await const ModuleApi().postJson(chatDeclineUrl(threadId), {});
    await fetchThreads(silent: true);
  }
}

/// Owns a single open conversation. Polls messages every 3s.
class ChatThreadController extends GetxController {
  ChatThreadController(this.threadId);

  final int threadId;

  final messages = <ChatMessage>[].obs;
  final isLoading = false.obs;
  final isSending = false.obs;
  final status = 'active'.obs;
  final errorMessage = RxnString();

  Timer? _poll;
  int _lastSeenId = 0;

  @override
  void onInit() {
    super.onInit();
    fetchMessages();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => fetchMessages(silent: true));
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
      final res = await const ModuleApi().getObject(chatMessagesUrl(threadId));
      status.value = (res['status'] ?? 'active').toString();
      final items = res['items'];
      final list = items is List
          ? items
              .whereType<Map>()
              .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : <ChatMessage>[];
      // Chime on a genuinely new incoming message during a silent poll.
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
      final res = await const ModuleApi().postJson(chatMessagesUrl(threadId), {'body': text});
      final m = res['message'];
      if (m is Map) {
        messages.add(ChatMessage.fromMap(Map<String, dynamic>.from(m)));
        _lastSeenId = messages.last.id;
      }
      return true;
    } catch (e) {
      errorMessage.value = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isSending.value = false;
    }
  }
}
