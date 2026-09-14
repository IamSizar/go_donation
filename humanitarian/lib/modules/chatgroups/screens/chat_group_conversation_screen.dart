// ChatGroupConversationScreen — the conversation screen for a staff-mediated
// group chat (OPOS #25284 Phase 5 Task 3).
//
// ONE screen serves both kinds of group: masked (members see each other only
// as aliases) and team (real names). The server resolves every sender's label
// for the group's kind, so this screen never branches on kind and cannot show
// more than the server chose to send.
//
// Top to bottom: the app bar; the transcript, in exactly one of its states —
// a skeleton while the first load runs, an error with Retry if it fails, a
// designed empty state, or the messages; then the footer — the composer, or,
// once staff have paused or ended the chat, the lifecycle notice in its place.
//
// The transcript is a REVERSED list, anchored at its newest message. New
// messages appear without scrolling anyone, a member reading older messages
// stays where they are while the 3-second poll runs, and when the keyboard
// opens the newest message stays in view.
//
// State lives in ChatGroupConversationController; this screen only renders it
// and forwards taps. Tapping outside a field dismisses the keyboard app-wide
// (DismissKeyboardOnTap in main.dart), and dragging the transcript does too.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:get/get.dart';

import '../controllers/chat_group_conversation_controller.dart';
import '../widgets/chat_group_composer.dart';
import '../widgets/chat_group_message_bubble.dart';

/// One chat group's conversation.
class ChatGroupConversationScreen extends StatefulWidget {
  /// Opens group [groupId]. [title] and [subtitle] arrive already localized.
  const ChatGroupConversationScreen({
    super.key,
    required this.groupId,
    required this.title,
    this.subtitle,
    this.api = const ModuleApi(),
  });

  /// The group to show.
  final int groupId;

  /// The app-bar title, already localized by the caller.
  final String title;

  /// An optional second app-bar line, already localized by the caller.
  final String? subtitle;

  /// Injectable so widget tests can answer without a network.
  final ModuleApi api;

  @override
  State<ChatGroupConversationScreen> createState() =>
      _ChatGroupConversationScreenState();
}

/// Renders one group's conversation and owns the member's draft.
class _ChatGroupConversationScreenState
    extends State<ChatGroupConversationScreen> {
  /// This screen's GetX tag — unique per screen INSTANCE, not per group.
  ///
  /// GetX ignores a `Get.put` for a tag that is already registered, so a tag
  /// per group would hand a second screen on the same group (a notification
  /// tap over an open chat) the first screen's controller, and closing the
  /// second screen would delete it out from under the first.
  late final String _tag =
      'chat-group-${widget.groupId}-${identityHashCode(this)}';

  /// Owns the transcript for this screen.
  late final ChatGroupConversationController _ctrl;

  /// The member's draft.
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = Get.put(
      ChatGroupConversationController(widget.groupId, api: widget.api),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    Get.delete<ChatGroupConversationController>(tag: _tag);
    _input.dispose();
    super.dispose();
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  /// Sends the draft. The box empties at once so the member can keep typing;
  /// if the send fails, the message is put back and the reason is shown —
  /// retyping a message is a cost they should never have to pay.
  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    final sent = await _ctrl.send(text);
    if (sent || !mounted) return;
    _restoreUnsent(text);
    final reason = _ctrl.sendError.value;
    if (reason == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
  }

  /// Puts an [unsent] message back in the box, ahead of anything typed while
  /// it was in flight, with the cursor at the end — neither may be lost.
  void _restoreUnsent(String unsent) {
    final draft = _input.text;
    final restored = draft.trim().isEmpty ? unsent : '$unsent\n$draft';
    _input.value = TextEditingValue(
      text: restored,
      selection: TextSelection.collapsed(offset: restored.length),
    );
  }

  // ─── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _AppBarTitle(title: widget.title, subtitle: widget.subtitle),
      ),
      body: Column(
        children: [
          Expanded(child: Obx(_buildTranscript)),
          Obx(_buildFooter),
        ],
      ),
    );
  }

  /// Exactly one transcript state. A load error replaces the transcript only
  /// while nothing has loaded: once messages are on screen they stay readable,
  /// and the background poll keeps trying.
  Widget _buildTranscript() {
    final messages = _ctrl.messages;
    final error = _ctrl.errorMessage.value;
    if (messages.isEmpty && _ctrl.isLoading.value) {
      // The skeleton carries its own padding (see AppAsync's docs).
      return AppSkeleton.bubbles();
    }
    if (messages.isEmpty && error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppErrorState(message: error, onRetry: _ctrl.fetchMessages),
      );
    }
    if (messages.isEmpty) return _buildEmpty();
    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: messages.length,
      // Reversed: index 0 is the bottom of the list, so the newest message.
      itemBuilder: (context, index) => ChatGroupMessageBubble(
        message: messages[messages.length - 1 - index],
      ),
    );
  }

  /// The empty state. An open chat invites the first message; a chat staff
  /// have already closed says so instead, since nothing can be sent into it.
  Widget _buildEmpty() {
    if (ChatLifecycle.isClosed(_ctrl.lifecycle.value)) {
      return const AppEmpty(
        icon: Icons.forum_outlined,
        title: 'chat_group_closed_empty_title',
        message: 'chat_group_closed_empty_message',
      );
    }
    return const AppEmpty(
      icon: Icons.forum_outlined,
      title: 'No messages yet. Say hello! 👋',
      message: 'Send the first message to start the conversation.',
    );
  }

  /// The composer — or, once staff have paused or ended the chat, the notice
  /// explaining why nothing more can be sent.
  Widget _buildFooter() {
    final lifecycle = _ctrl.lifecycle.value;
    if (ChatLifecycle.isClosed(lifecycle)) {
      return ChatLifecycleNotice(
        lifecycle: lifecycle,
        reason: _ctrl.lifecycleReason.value,
      );
    }
    return ChatGroupComposer(
      input: _input,
      onSend: _send,
      isSending: _ctrl.isSending.value,
    );
  }
}

/// The app bar's title, with an optional muted second line.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.title, this.subtitle});

  /// The main line.
  final String title;

  /// The muted second line; hidden when empty.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final second = subtitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (second.isNotEmpty)
          Text(
            second,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.meta,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
      ],
    );
  }
}
