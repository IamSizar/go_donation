// chat_lifecycle_notice.dart — what a participant sees INSTEAD of the message
// box when staff have paused or ended their conversation.
//
// WHY THIS EXISTS AT ALL
// The server refuses a message in a paused or ended thread (migration 117).
// Leaving the composer on screen would let a user type a paragraph, press
// send, and receive a snackbar — a dead end that tells them nothing about why
// or whether it will ever work again. So the composer is replaced by an
// explanation carrying the three things a person needs: what happened, why
// (the staff member's own reason, when they gave one), and what to expect
// next.
//
// Shared by all three participant-facing chats (donor↔owner, marriage,
// case-volunteer). The staff↔staff chat lives only in the dashboard.
//
// This is presentation only. It is NOT the rule — the rule is server-side, in
// internal/chatlifecycle. Hiding a text field is a courtesy, not enforcement.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

/// The lifecycle a thread can be in, as the API reports it.
///
/// `open` is the default everywhere: a response from an older server, or one
/// that failed to read the state, must leave the chat working rather than
/// silently locking a conversation that is fine.
class ChatLifecycle {
  const ChatLifecycle._();

  static const String open = 'open';
  static const String paused = 'paused';
  static const String ended = 'ended';

  /// True when the composer must be replaced by [ChatLifecycleNotice].
  static bool isClosed(String value) => value == paused || value == ended;
}

/// The banner shown in place of the composer.
///
/// [lifecycle] is `paused` or `ended`; [reason] is the staff member's own
/// words, shown verbatim when present. Renders nothing for an open chat, so a
/// caller can place it unconditionally.
class ChatLifecycleNotice extends StatelessWidget {
  const ChatLifecycleNotice({
    super.key,
    required this.lifecycle,
    this.reason,
  });

  final String lifecycle;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    if (!ChatLifecycle.isClosed(lifecycle)) return const SizedBox.shrink();

    final paused = lifecycle == ChatLifecycle.paused;
    // Paused is temporary, so it reads as a hold (amber); ended is settled,
    // so it reads as neutral information rather than as a failure. Neither is
    // an error colour: nothing has gone wrong for the user.
    final tint = paused ? const Color(0xFFB26A00) : AppThemeConfig.mutedText(context);
    final title = paused
        ? 'This conversation has been paused by our team.'.tr
        : 'This conversation has been closed by our team.'.tr;
    final body = paused
        ? 'You can still read it. New messages can\'t be sent while it is paused.'
              .tr
        : 'You can still read the whole conversation, but no new messages can be sent.'
              .tr;
    final trimmedReason = reason?.trim();

    return Container(
      width: double.infinity,
      // Logical padding, so the notice mirrors correctly in Arabic and
      // Kurdish without a second layout.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: tint.withValues(alpha: 0.28)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              paused ? Icons.pause_circle_outline : Icons.lock_outline_rounded,
              size: 20,
              color: tint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                  // The staff member's reason, when there is one. Shown after
                  // the generic explanation rather than instead of it, so the
                  // notice still makes sense when nobody wrote a reason.
                  if (trimmedReason != null && trimmedReason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${'Reason'.tr}: $trimmedReason',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontStyle: FontStyle.italic,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
