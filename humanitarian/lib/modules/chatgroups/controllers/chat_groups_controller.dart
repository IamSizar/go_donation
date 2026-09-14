// ChatGroupsController — owns the signed-in member's staff-mediated group
// chats (OPOS #25284 Phase 5) for the Messages tab's "My Connections" (masked
// groups) and "My Team Groups" (team groups) sections.
//
// It follows ChatController (modules/chat/controllers/chat_controller.dart):
// a 5-second silent poll, and the rule that a background tick never shows an
// error. It differs in three deliberate ways, each pinned by a test:
//   * Loads run one at a time. A request can take 12 seconds on the
//     connections this app is used on, so overlapping polls could apply an
//     older list over a newer one; a tick that finds a load running skips.
//   * Nothing is applied, and nothing chimes, once the screen has closed.
//   * The new-group chime also fires for the member's very FIRST group — that
//     is the moment staff approve a connect request, the one that matters most.
//     Only the list being shown for the first time stays quiet.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// How often the groups list refreshes in the background. Matches
/// ChatController, so both halves of the Messages tab update together.
const Duration chatGroupsPollInterval = Duration(seconds: 5);

/// Owns the member's chat groups and keeps them fresh while the Messages tab
/// is open.
class ChatGroupsController extends GetxController {
  /// [api] and [onNewGroup] are injectable so tests can observe the controller
  /// without a network or a speaker; production code uses the defaults.
  ChatGroupsController({
    ModuleApi api = const ModuleApi(),
    void Function()? onNewGroup,
  }) : _api = api,
       _onNewGroup = onNewGroup ?? _playNewGroupChime;

  /// The API the groups are read from.
  final ModuleApi _api;

  /// Called once when a load brings a group that was not on screen before.
  final void Function() _onNewGroup;

  /// Every group the member belongs to, in the order the server returns them.
  final groups = <ChatGroupSummary>[].obs;

  /// True only while a visible (non-silent) load is in flight.
  final isLoading = false.obs;

  /// A localized "what failed, then what to do next" sentence, or null.
  final errorMessage = RxnString();

  /// The background poll; cancelled when the controller closes.
  Timer? _poll;

  /// True once a load has succeeded, so a later new group counts as news.
  bool _hasLoaded = false;

  /// The tail of the load queue — each load starts after the previous ends.
  Future<void> _loadChain = Future<void>.value();

  /// How many loads are queued or running.
  int _loadsInFlight = 0;

  /// Masked, alias-only groups — the "My Connections" section.
  List<ChatGroupSummary> get masked => groups.where((g) => g.isMasked).toList();

  /// Real-name team groups — the "My Team Groups" section.
  List<ChatGroupSummary> get teams => groups.where((g) => !g.isMasked).toList();

  @override
  void onInit() {
    super.onInit();
    fetchGroups();
    _poll = Timer.periodic(
      chatGroupsPollInterval,
      (_) => fetchGroups(silent: true),
    );
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  /// Loads the member's groups.
  ///
  /// A visible load ([silent] false) shows the spinner and, when it fails, a
  /// localized error the screen renders with a Retry button. A silent load —
  /// the background poll — keeps whatever is already on screen and reports
  /// nothing, and is skipped outright when another load is already running:
  /// that load will bring the same news.
  Future<void> fetchGroups({bool silent = false}) {
    if (silent && _loadsInFlight > 0) return Future<void>.value();
    return _serialized(() => _load(silent: silent));
  }

  /// Queues [load] behind any load already running, so responses are applied
  /// in the order they were requested.
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

  /// One load: fetch, then apply — unless the screen closed while waiting.
  Future<void> _load({required bool silent}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await _api.chatGroups();
      if (isClosed) return;
      final fresh = rows.map(ChatGroupSummary.fromMap).toList();
      _chimeOnNewGroup(fresh);
      groups.assignAll(fresh);
      _hasLoaded = true;
    } catch (e) {
      // Only a visible failure is logged: the silent poll would otherwise
      // write the same line every five seconds while the phone is offline.
      if (!silent && !isClosed) {
        debugPrint('[chat-groups] loading groups failed: $e');
        errorMessage.value = failureMessage(e, 'error_chat_groups_load_failed');
      }
    } finally {
      if (!silent && !isClosed) isLoading.value = false;
    }
  }

  /// Chimes when [fresh] holds a group that is not on screen yet. The first
  /// successful load is the list appearing, not news, so it stays quiet.
  void _chimeOnNewGroup(List<ChatGroupSummary> fresh) {
    if (!_hasLoaded) return;
    final shown = groups.map((g) => g.id).toSet();
    if (fresh.any((g) => !shown.contains(g.id))) _onNewGroup();
  }

  /// The production chime: the shared notification sound and a gentle tap,
  /// both of which respect the app-wide mute setting.
  static void _playNewGroupChime() {
    AppSound.notification();
    AppHaptics.gentle();
  }
}
