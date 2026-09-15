// chat_request_actions.dart — the inline Accept / Decline row on a
// `chat_request` notification card.
//
// WHY THIS IS ITS OWN FILE
// It lived at the bottom of notification_tile.dart, which had grown to 704
// lines against the project's 500-line limit (OPOS #26473). It was already a
// self-contained StatefulWidget whose only input is the thread id, so it moved
// here unchanged. The app has no part / part-of libraries, so it is a public
// widget rather than a library-private one; its State stays private.
//
// THE GUEST GUARD LIVES AT THE CALL SITE, NOT HERE (OPOS #26448)
// Building this widget registers ChatController when none exists, and
// ChatController fetches GET /api/chats at once and polls it every 5 seconds.
// NotificationTile therefore builds it only when `!isGuestMode()`. Any new
// host must apply the same guard: the server refuses a guest's accept and
// decline (RequireNotGuest), and for a guest the poll only fetches a list the
// server always leaves empty.
//
// Consumers: NotificationTile (notification_tile.dart) only.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:get/get.dart';

/// Accept / Decline buttons shown inline on a `chat_request` notification.
///
/// Uses [Obx] to reactively read the thread's status from [ChatController].
/// This means the done-state persists across notification-list rebuilds:
/// if the thread is already `active` (accepted) or `declined`, the buttons
/// never reappear even when the notification list re-polls.
///
/// Accepting opens [ChatConversationScreen] for the thread. A failed accept
/// shows the error in a SnackBar and re-enables the buttons; a failed decline
/// only re-enables them.
///
/// Never build this for a guest: it registers [ChatController] when none is
/// registered, which starts that controller's /api/chats poll. See the file
/// header and NotificationTile's call site (OPOS #26448).
class ChatRequestActions extends StatefulWidget {
  /// Creates the Accept / Decline row for the chat thread [threadId].
  const ChatRequestActions({super.key, required this.threadId});

  /// The chat thread the request is about — the notification's
  /// `relatedEntityId`, already parsed as an int by the caller.
  final int threadId;

  @override
  State<ChatRequestActions> createState() => _ChatRequestActionsState();
}

class _ChatRequestActionsState extends State<ChatRequestActions> {
  bool _busy = false;

  // Local "done" is only used as instant feedback during the API call,
  // before the next fetchThreads() result arrives.
  bool _localDone = false;
  String? _localResult;

  // The put below starts ChatController's /api/chats fetch and 5-second poll,
  // which is why NotificationTile never builds this widget for a guest
  // (OPOS #26448). Do not host it anywhere without that guard.
  ChatController get _ctrl => Get.isRegistered<ChatController>()
      ? Get.find<ChatController>()
      : Get.put(ChatController());

  // ─── Actions ───

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _ctrl.accept(widget.threadId);
      if (!mounted) return;
      setState(() {
        _localDone = true;
        _localResult = 'Accepted';
        _busy = false;
      });
      Get.to(
        () =>
            ChatConversationScreen(threadId: widget.threadId, title: 'Chat'.tr),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _ctrl.decline(widget.threadId);
      if (!mounted) return;
      setState(() {
        _localDone = true;
        _localResult = 'Declined';
        _busy = false;
      });
    } catch (e) {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── UI Builders ───

  Widget _buildDone(String result) {
    return Row(
      children: [
        Icon(
          result == 'Accepted'
              ? Icons.check_circle_rounded
              : Icons.cancel_rounded,
          size: 16,
          color: result == 'Accepted'
              ? AppThemeConfig.accent(context)
              : AppThemeConfig.consequence(context),
        ),
        const SizedBox(width: 6),
        Text(
          result.tr,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppThemeConfig.mutedText(context),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : _decline,
            child: Text('Decline'.tr),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : _accept,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('Accept'.tr),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Obx reacts to ChatController.threads changes, so this widget
    // automatically updates when accept/decline completes (fetchThreads
    // refreshes the list) — and also stays correct across notification
    // list rebuilds because it reads persisted singleton state.
    return Obx(() {
      // Look up the thread's current status from the singleton controller.
      ChatThread? thread;
      for (final t in _ctrl.threads) {
        if (t.id == widget.threadId) {
          thread = t;
          break;
        }
      }

      if (thread != null && thread.status == 'active') {
        return _buildDone('Accepted');
      }
      if (thread != null && thread.status == 'declined') {
        return _buildDone('Declined');
      }

      // Thread not yet in list (controller may not have fetched yet) or
      // still pending — fall back to local state for instant feedback
      // during the in-flight API call.
      if (_localDone) return _buildDone(_localResult ?? '');

      return _buildButtons();
    });
  }
}
