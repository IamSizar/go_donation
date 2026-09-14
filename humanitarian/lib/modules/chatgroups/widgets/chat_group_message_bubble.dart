// ChatGroupMessageBubble — one message in a staff-mediated group chat
// (OPOS #25284 Phase 5), drawn by ChatGroupConversationScreen.
//
// What it shows, and deliberately nothing else:
//   * the sender's label exactly as the server resolved it — an alias in a
//     masked group, a real name in a team group, "Support" for staff. The
//     model carries no user id, so there is nothing else a bubble could leak;
//   * the message body;
//   * when it was sent, in the reader's language.
//
// Everything is directional, so the member's own messages sit at the reading
// END of the line: on the right in English, on the left in Arabic and Kurdish.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:intl/intl.dart';

import '../models/chat_group_models.dart';

/// The widest a bubble may grow, as a share of the screen width: room for a
/// short paragraph, while the two sides of the conversation stay visibly apart.
const double _maxWidthFraction = 0.76;

/// One message — label, body and time — aligned by who sent it.
class ChatGroupMessageBubble extends StatelessWidget {
  /// Draws [message].
  const ChatGroupMessageBubble({super.key, required this.message});

  /// The message to draw.
  final ChatGroupMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final createdAt = message.createdAt;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * _maxWidthFraction,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Only the other side is named — a member knows who they are.
              if (!mine) _SenderLabel(label: message.senderLabel),
              _BubbleBody(text: message.body, mine: mine),
              if (createdAt != null) _SentAt(time: createdAt),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sender's server-resolved label, above someone else's message.
class _SenderLabel extends StatelessWidget {
  const _SenderLabel({required this.label});

  /// The alias, real name or "Support", exactly as the server sent it.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpace.xxs,
        end: AppSpace.xxs,
        bottom: AppSpace.xxs,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppType.meta,
          fontWeight: AppType.wLabel,
          color: AppThemeConfig.mutedText(context),
        ),
      ),
    );
  }
}

/// The filled bubble holding the text. The bottom corner on the sender's side
/// is squared off, so the bubble points at who wrote it in either direction.
class _BubbleBody extends StatelessWidget {
  const _BubbleBody({required this.text, required this.mine});

  /// The message body.
  final String text;

  /// True for the member's own message, which takes the accent fill.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(AppRadius.md);
    const squared = Radius.circular(AppSpace.xxs);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        // accent/onAccent is the theme's contrast-checked pair, in light and
        // dark mode alike.
        color: mine
            ? AppThemeConfig.accent(context)
            : AppThemeConfig.softSurface(context),
        borderRadius: BorderRadiusDirectional.only(
          topStart: round,
          topEnd: round,
          bottomStart: mine ? round : squared,
          bottomEnd: mine ? squared : round,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppType.body,
          height: AppType.leadDense,
          color: mine
              ? AppThemeConfig.onAccent(context)
              : AppThemeConfig.text(context),
        ),
      ),
    );
  }
}

/// When the message was sent, in the reader's language.
///
/// `Intl.defaultLocale` is pinned to the app's language at startup and on
/// every switch (AppLocaleService.syncDateFormatLocale), so a bare skeleton is
/// already correct in every locale the app ships — unlike the fixed
/// `'MMM d · HH:mm'` pattern the 1:1 chat uses, which prints English month
/// names on an Arabic screen.
class _SentAt extends StatelessWidget {
  const _SentAt({required this.time});

  /// The moment the server stored the message (UTC).
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: AppSpace.xxs,
        start: AppSpace.xxs,
        end: AppSpace.xxs,
      ),
      child: Text(
        DateFormat.MMMd().add_jm().format(time.toLocal()),
        style: TextStyle(
          fontSize: AppType.label,
          color: AppThemeConfig.mutedText(context),
        ),
      ),
    );
  }
}
