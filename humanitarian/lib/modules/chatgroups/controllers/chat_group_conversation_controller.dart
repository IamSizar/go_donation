// ChatGroupConversationController — owns one open staff-mediated group chat
// (OPOS #25284 Phase 5), for masked and team groups alike.
//
// The server already resolves every message's `sender_label` to the right
// display text for the group's kind (an alias in a masked group, a real name
// in a team group), so nothing here branches on kind.
//
// Modeled on ChatThreadController (modules/chat/controllers/chat_controller.dart)
// — a 3-second silent poll and the same lifecycle handling — but built around
// five facts of the chat-groups API that the 1:1 chat does not share:
//   * The transcript is PAGED oldest-first (100 per request at most). Opening
//     walks every page; a poll asks only for messages after the newest one on
//     screen and appends them.
//   * The read cursor only moves when POST /read is sent the newest id seen.
//   * The server NAMES the refusals a member can hit — contact details in a
//     supervised chat, a chat staff have closed — so a send explains them.
//   * Requests are slow where this app is used, so loads run one at a time,
//     and nothing is applied once the screen has closed.
//   * A group can vanish under the member: staff delete or archive it (404),
//     or remove the member (403), and every later request is refused the same
//     way. That is a terminal state ([isUnavailable]), not a retryable error.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/api_status_exception.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// How often an open conversation refreshes. Matches ChatThreadController.
const Duration chatGroupConversationPollInterval = Duration(seconds: 3);

/// Messages requested per page — the server's maximum, so opening a long
/// conversation takes as few requests as possible.
const int chatGroupMessagePageSize = 100;

/// The server's code for a send refused because staff paused or ended the chat.
const String _chatClosedCode = 'chat_lifecycle_closed';

/// What one load brought back: the messages newer than those on screen, and
/// the last response, which carries the conversation's current lifecycle.
typedef _NewerMessages = ({
  List<ChatGroupMessage> messages,
  Map<String, dynamic> lastResponse,
});

/// Owns the transcript, lifecycle and composer state of one chat group.
class ChatGroupConversationController extends GetxController {
  /// [api] and [onIncomingMessage] are injectable so tests can observe the
  /// controller without a network or a speaker; production uses the defaults.
  ChatGroupConversationController(
    this.groupId, {
    ModuleApi api = const ModuleApi(),
    void Function()? onIncomingMessage,
  }) : _api = api,
       _onIncomingMessage = onIncomingMessage ?? _playIncomingChime;

  /// The group this controller shows.
  final int groupId;

  /// The API the conversation is read from and written to.
  final ModuleApi _api;

  /// Called once when a load brings a message someone else sent.
  final void Function() _onIncomingMessage;

  /// The transcript, oldest first.
  final messages = <ChatGroupMessage>[].obs;

  /// True only while a visible (non-silent) load is in flight.
  final isLoading = false.obs;

  /// True from the moment a send starts until the sent message is on screen
  /// (or the send has failed). A second send is refused meanwhile.
  final isSending = false.obs;

  /// Staff-controlled state: open | paused | ended. Defaults to open, so a
  /// response we could not read leaves a healthy chat usable.
  final lifecycle = ChatLifecycle.open.obs;

  /// The staff member's own words for a pause or end, or null.
  final lifecycleReason = RxnString();

  /// Localized load failure ("what failed, then what to do next"), or null.
  final errorMessage = RxnString();

  /// True once the server has said this group is gone FOR THIS MEMBER: staff
  /// deleted or archived it (404), or removed the member from it (403).
  ///
  /// TERMINAL. Polling stops and nothing sets it back, because no retry can
  /// bring the group back — which is exactly why it is kept apart from
  /// [errorMessage], whose screen state always offers Retry.
  final isUnavailable = false.obs;

  /// Localized reason the last send did not go through, or null. Kept apart
  /// from [errorMessage] so a failed send never looks like a failed load.
  final sendError = RxnString();

  /// The background poll; cancelled when the controller closes.
  Timer? _poll;

  /// True once a load has succeeded, so a later message counts as news.
  bool _hasLoaded = false;

  /// Newest message id the server has accepted as read. Only moves forward,
  /// and only when the POST succeeds, so a failure is retried next poll.
  int _lastMarkedReadId = 0;

  /// The tail of the load queue — each load starts after the previous ends.
  Future<void> _loadChain = Future<void>.value();

  /// How many loads are queued or running.
  int _loadsInFlight = 0;

  @override
  void onInit() {
    super.onInit();
    fetchMessages();
    _poll = Timer.periodic(
      chatGroupConversationPollInterval,
      (_) => fetchMessages(silent: true),
    );
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  /// Loads every message newer than those on screen, then marks the newest
  /// one read.
  ///
  /// A visible load ([silent] false) shows the spinner and, on failure, a
  /// localized [errorMessage]. A silent load — the background poll — keeps
  /// the transcript on screen and reports nothing, and is skipped outright
  /// when another load is already running: that load brings the same news.
  ///
  /// Either kind of load that learns the group is gone for this member sets
  /// [isUnavailable] instead of an error, and the poll stops.
  Future<void> fetchMessages({bool silent = false}) {
    if (silent && _loadsInFlight > 0) return Future<void>.value();
    return _serialized(() => _load(silent: silent));
  }

  /// Queues [load] behind any load already running, so responses are applied
  /// in the order they were requested and never overwrite a newer one.
  Future<void> _serialized(Future<void> Function() load) {
    _loadsInFlight++;
    final next = _loadChain
        .then((_) => load())
        .whenComplete(() => _loadsInFlight--);
    // [_load] reports failures through errorMessage and never throws. Should
    // one ever escape, the caller still receives it through [next]; it is only
    // kept off the chain, where it would stop every later load from running.
    _loadChain = next.catchError((Object _) {});
    return next;
  }

  /// One load: fetch, apply unless the screen closed meanwhile, mark read.
  Future<void> _load({required bool silent}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final newer = await _fetchNewerMessages();
      if (isClosed) return;
      _apply(newer);
      // Any successful load — a silent poll included — settles an earlier
      // failure: a "could not load" banner must not sit over a transcript
      // that has since loaded.
      errorMessage.value = null;
    } catch (e) {
      // Checked before the silent/visible split: a member removed mid-chat
      // learns it from a silent poll, and must end up exactly where a member
      // who opened an already-deleted group does.
      if (_isGoneForMember(e)) {
        _markUnavailable(e);
        return;
      }
      // Only a visible failure is logged; the silent poll would repeat the
      // same line every three seconds while the phone is offline.
      if (!silent && !isClosed) {
        debugPrint('[chat-groups] loading group $groupId failed: $e');
        errorMessage.value = failureMessage(e, 'error_messages_load_failed');
      }
      return;
    } finally {
      if (!silent && !isClosed) isLoading.value = false;
    }
    await _markNewestRead();
  }

  /// True when [error] is the server saying this group no longer exists FOR
  /// THIS MEMBER: 404 once staff deleted or archived it, 403 once they removed
  /// the member. Read from the status itself — never parsed out of a message.
  /// A 401 is not "gone": session_expiry.dart already signs that member out.
  static bool _isGoneForMember(Object error) =>
      error is ApiStatusException &&
      (error.statusCode == 403 || error.statusCode == 404);

  /// Enters the terminal "no longer available" state: no error (an error is
  /// what puts a Retry on screen) and no more polling, since every later
  /// request would be refused the same way. Logged here, once, because the
  /// poll that would have repeated the line is cancelled with it.
  void _markUnavailable(Object error) {
    if (isClosed) return;
    debugPrint('[chat-groups] group $groupId is no longer available: $error');
    isUnavailable.value = true;
    errorMessage.value = null;
    _poll?.cancel();
  }

  /// Walks the pages after the newest message on screen until a short page
  /// ends the history. All or nothing: if any page fails the load fails, and
  /// the next poll starts again from what is actually shown. The server only
  /// returns ids above `after_id`, so every full page moves the cursor on.
  Future<_NewerMessages> _fetchNewerMessages() async {
    var afterId = _newestId(messages);
    final collected = <ChatGroupMessage>[];
    while (true) {
      final response = await _api.chatGroupMessages(
        groupId,
        afterId: afterId,
        limit: chatGroupMessagePageSize,
      );
      final page = _parseMessages(response['items']);
      collected.addAll(page);
      if (page.length < chatGroupMessagePageSize || isClosed) {
        return (messages: collected, lastResponse: response);
      }
      afterId = _newestId(page);
    }
  }

  /// Appends the messages not already shown, chimes if someone else sent one
  /// after the first load, and takes the lifecycle from the latest response.
  void _apply(_NewerMessages newer) {
    final shownIds = messages.map((m) => m.id).toSet();
    final added = newer.messages
        .where((m) => !shownIds.contains(m.id))
        .toList();
    if (_hasLoaded && added.any((m) => !m.isMine)) _onIncomingMessage();
    // RxList.addAll notifies every listener even when handed nothing, and the
    // poll runs every three seconds — so only touch the list when something
    // actually arrived.
    if (added.isNotEmpty) messages.addAll(added);
    _hasLoaded = true;

    final response = newer.lastResponse;
    lifecycle.value = (response['lifecycle'] ?? ChatLifecycle.open).toString();
    final reason = response['lifecycle_reason']?.toString().trim();
    lifecycleReason.value = (reason == null || reason.isEmpty) ? null : reason;
  }

  /// Turns the response's `items` into messages, skipping anything malformed.
  List<ChatGroupMessage> _parseMessages(Object? items) {
    if (items is! List) return <ChatGroupMessage>[];
    return items
        .whereType<Map>()
        .map((e) => ChatGroupMessage.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// The highest message id in [list], or 0 when it is empty.
  int _newestId(List<ChatGroupMessage> list) =>
      list.fold<int>(0, (newest, m) => m.id > newest ? m.id : newest);

  // ─── Read cursor ──────────────────────────────────────────────────────────

  /// Tells the server the member has seen everything up to the newest message
  /// on screen. Skipped when nothing is newer than the last accepted cursor,
  /// so a quiet conversation does not POST every three seconds.
  Future<void> _markNewestRead() async {
    final newest = _newestId(messages);
    if (newest <= _lastMarkedReadId || isClosed) return;
    try {
      await _api.markChatGroupRead(groupId, lastReadMessageId: newest);
      if (newest > _lastMarkedReadId) _lastMarkedReadId = newest;
    } catch (e) {
      // Not shown to the member: they did see the messages, and a lagging
      // cursor only delays their unread badge clearing. The next poll retries
      // because _lastMarkedReadId did not advance.
      debugPrint('[chat-groups] marking group $groupId read failed: $e');
    }
  }

  // ─── Sending ──────────────────────────────────────────────────────────────

  /// Sends [body], trimmed, and resolves once the stored message is on screen.
  ///
  /// Returns false — sending nothing — when the text is blank or a send is
  /// already in flight, and false with a localized [sendError] when the send
  /// fails; the screen should then keep the member's typed text.
  Future<bool> send(String body) async {
    final text = body.trim();
    if (text.isEmpty || isSending.value) return false;
    isSending.value = true;
    sendError.value = null;
    try {
      final refusal = await _post(text);
      if (refusal != null) {
        sendError.value = refusal;
        return false;
      }
      // The response carries only the new id, so refresh to show the stored
      // message. Queued behind any running load and never skipped. A failed
      // refresh does not make a stored message unsent — the next poll shows it.
      await _serialized(() => _load(silent: true));
      return true;
    } finally {
      if (!isClosed) isSending.value = false;
    }
  }

  /// Posts [text]. Returns null once it is stored, or the localized reason it
  /// was not.
  Future<String?> _post(String text) async {
    try {
      await _api.sendChatGroupMessage(groupId, text);
      return null;
    } on ApiCodedException catch (e) {
      debugPrint('[chat-groups] group $groupId refused a message: $e');
      if (e.code == _chatClosedCode) {
        // Staff paused or ended the chat after it was opened: refresh so the
        // lifecycle notice replaces the composer.
        await _serialized(() => _load(silent: true));
      }
      return _refusalMessage(e.code);
    } catch (e) {
      debugPrint('[chat-groups] sending to group $groupId failed: $e');
      return failureMessage(e, 'error_message_send_failed');
    }
  }

  /// Localized copy for a refusal the server named.
  ///
  /// A `switch` rather than a key built from the code, because GetX returns
  /// the key itself when a translation is missing: a code added server-side
  /// later would otherwise print `chat_group_send_whatever` on screen. An
  /// unknown code gets the generic failure, which is vague but true.
  static String _refusalMessage(String code) => switch (code) {
    'contact_details_blocked' => 'chat_group_send_contact_blocked'.tr,
    _chatClosedCode => 'chat_group_send_closed'.tr,
    _ => failureMessageFor(
      offline: false,
      whatFailedKey: 'error_message_send_failed',
    ),
  };

  /// The production chime: the shared notification sound and a gentle tap,
  /// both of which respect the app-wide mute setting.
  static void _playIncomingChime() {
    AppSound.notification();
    AppHaptics.gentle();
  }
}
