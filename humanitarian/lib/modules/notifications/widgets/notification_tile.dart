// notification_tile.dart — one card in the notification list: a type-aware
// alert tile with swipe-to-read and, for a signed-in member's chat request,
// inline Accept / Decline.
//
// MODULE MAP (split by OPOS #26473 to stay under the 500-line limit)
//   • notification_tile.dart    — NotificationTile, its relative-time stamp,
//     and the card's small private pieces (icon badge, chips, swipe
//     background).
//   • notification_visuals.dart — NotificationVisuals: category and type to
//     colour, icon and pinned state.
//   • chat_request_actions.dart — ChatRequestActions: the Accept / Decline
//     row, which this file builds only when `!isGuestMode()` (OPOS #26448).
//
// Hosted by NotificationsScreen (screens/notifications_screen.dart) and by
// lib/widgets/notification.dart.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../models/app_notification_model.dart';
import 'chat_request_actions.dart';
import 'notification_visuals.dart';

/// A redesigned, type-aware alert card.
///
/// Every notification reads at a glance from its category/type:
///   • a colored left accent bar + gradient icon badge in the category colour,
///   • an icon chosen from the notification *type* (chat, donation, campaign…),
///   • a distinct unread state (tinted background, coloured border, bold title)
///     vs. a calm read state (plain surface, muted),
///   • a compact relative time ("now", "5m", "3h", "2d", then the date).
///
/// Swipe-to-read and the inline chat Accept/Decline are preserved.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismissed,
  });

  final AppNotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final style = NotificationVisuals.of(context, notification);
    final unread = !notification.isRead;

    final surface = AppThemeConfig.surface(context);
    // Unread cards get a faint wash of the category colour so the eye lands on
    // them first; read cards stay neutral.
    final cardColor = unread
        ? Color.alphaBlend(style.color.withValues(alpha: 0.06), surface)
        : surface;
    final borderColor = unread
        ? style.color.withValues(alpha: 0.45)
        // Pinned categories (urgent / payment) keep a hint of their colour even
        // after they're read, so high-stakes alerts never fully fade out.
        : (style.isPinned
              ? style.color.withValues(alpha: 0.30)
              : AppThemeConfig.border(context));

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: unread
                    ? style.color.withValues(alpha: 0.14)
                    : AppThemeConfig.shadow(context),
                blurRadius: unread ? 16 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Full-height coloured spine = instant type cue. Rendered as a
                // clipped child because a non-uniform border can't have a radius.
                Container(width: 4, color: style.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBadge(style: style, dimmed: !unread),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title + unread dot + relative time
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      notification.localizedTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: unread
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: AppThemeConfig.text(context),
                                        fontSize: 15.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  if (unread) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 9,
                                      height: 9,
                                      margin: const EdgeInsets.only(top: 5),
                                      decoration: BoxDecoration(
                                        color: style.color,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: style.color.withValues(
                                              alpha: 0.5,
                                            ),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Category chip · priority · link · time
                              Row(
                                children: [
                                  _CategoryChip(
                                    style: style,
                                    notification: notification,
                                  ),
                                  if (notification.priority > 0) ...[
                                    const SizedBox(width: 6),
                                    _MiniChip(
                                      icon: Icons.flag_rounded,
                                      label: notification.priority.toString(),
                                      color: AppThemeConfig.accent(context),
                                    ),
                                  ],
                                  if (notification.hasActionUrl) ...[
                                    const SizedBox(width: 6),
                                    _MiniChip(
                                      icon: Icons.open_in_new_rounded,
                                      label: 'Link'.tr,
                                      color: AppThemeConfig.accent(context),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (notification.createdAt != null)
                                    // Flexible because the stamp is a word now
                                    // and not two characters: with three chips
                                    // beside it on a narrow phone the Row can
                                    // run out of room, and ellipsizing is the
                                    // correct answer there rather than a
                                    // yellow overflow stripe.
                                    Flexible(
                                      child: Text(
                                        _relativeTime(
                                          notification.createdAt!.toLocal(),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppThemeConfig.mutedText(
                                            context,
                                          ),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                notification.localizedMessage,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppThemeConfig.mutedText(context),
                                  height: 1.45,
                                  fontSize: 13.5,
                                ),
                              ),
                              // Inline Accept/Decline for incoming chat requests.
                              //
                              // OPOS #26448 — never for a guest. The actions
                              // read ChatController through an Obx and put one
                              // when none is registered, and ChatController
                              // fetches /api/chats at once and polls it every
                              // 5 seconds. So merely drawing them started that
                              // poll for a guest, for a list the server always
                              // leaves empty (GuestGetsEmptyList). #100 took
                              // the controller away from a guest's dashboard
                              // and Messages tab; this was the door left open.
                              //
                              // Hidden rather than gated behind a sign-in
                              // prompt, as ConnectRequestButton hides for a
                              // guest: the server refuses a guest's accept and
                              // decline (RequireNotGuest), and signing in lands
                              // on a different account the invite is not
                              // addressed to. The notification still shows and
                              // still taps through.
                              //
                              // isGuestMode() is checked last, so a tile that
                              // is not a chat request never reads preferences.
                              if (notification.notificationType ==
                                      'chat_request' &&
                                  int.tryParse(notification.relatedEntityId) !=
                                      null &&
                                  !isGuestMode()) ...[
                                const SizedBox(height: 12),
                                ChatRequestActions(
                                  threadId: int.parse(
                                    notification.relatedEntityId,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onDismissed == null) return child;

    return Dismissible(
      key: ValueKey('notification-${notification.id}'),
      direction: DismissDirection.horizontal,
      background: _ReadBackground(alignment: AlignmentDirectional.centerStart),
      secondaryBackground: _ReadBackground(
        alignment: AlignmentDirectional.centerEnd,
      ),
      onDismissed: (_) => onDismissed?.call(),
      child: child,
    );
  }
}

/// Compact relative time, in the reader's language; falls back to an absolute
/// date.
///
/// WHY THE UNITS ARE NO LONGER "m" / "h" / "d"
/// This used to read "Language-neutral short units so it works in every locale
/// without extra translation keys". That argument was worth taking seriously —
/// a timestamp is glanced at, not read, and short is a real virtue in a Row
/// that already carries two or three chips. It was wrong on both halves.
///
///   • Not neutral. m/h/d are abbreviations of ENGLISH words. Arabic has no
///     convention in which a bare Latin "h" means ساعة, so an Arabic reader
///     had to know English to read the stamp. A client walking the app found
///     «5h» sitting in an otherwise fully Arabic list.
///   • Not "without extra keys". The first branch of this very function
///     already returns `'now'.tr`, translated in all four locales, and the
///     last already returns Arabic month names — `DateFormat` with no locale
///     argument reads `Intl.defaultLocale`, which AppLocaleService pins to
///     'ar' for Arabic and both Kurdish variants on startup and on every
///     language switch. The function was locale-aware at both ends; the three
///     middle lines were the only English left in it.
///
/// The cost paid for that is three keys (one of which already existed) and a
/// slightly wider stamp — «٥ ساعة» against "5h". The Row absorbs it: the
/// `Text` is Flexible, so it ellipsizes instead of overflowing when the chips
/// beside it are long.
///
/// Kurdish is deliberately not invented and falls back to English, which is
/// what those readers already had. The keys are in TRANSLATION_REQUEST.md.
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inSeconds < 45) return 'now'.tr;
  if (diff.inMinutes < 60) {
    return '@count minutes'.trParams({'count': '${diff.inMinutes}'});
  }
  if (diff.inHours < 24) {
    return '@count hours'.trParams({'count': '${diff.inHours}'});
  }
  if (diff.inDays < 7) {
    return '@count days'.trParams({'count': '${diff.inDays}'});
  }
  return DateFormat('MMM d').format(dt);
}

/// Gradient icon badge in the category colour.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.style, required this.dimmed});

  final NotificationVisuals style;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        // A flat fill. This was a two-stop LinearGradient, but four of the six
        // category styles set both stops to the same colour, so the gradient
        // was only ever real for 'urgent' — where it blended two semantic
        // tokens (consequence into pending) and muddied both.
        color: dimmed ? style.color.withValues(alpha: 0.55) : style.color,
        borderRadius: BorderRadius.circular(13),
        boxShadow: dimmed
            ? null
            : [
                BoxShadow(
                  color: style.color.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Icon(style.icon, color: Colors.white, size: 22),
    );
  }
}

/// The category pill — small icon + localized label in the category colour.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.style, required this.notification});

  final NotificationVisuals style;
  final AppNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.color),
          const SizedBox(width: 4),
          Text(
            notification.categoryLabel.tr,
            style: TextStyle(
              color: style.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny pill for priority / link affordances.
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadBackground extends StatelessWidget {
  const _ReadBackground({required this.alignment});

  /// AlignmentGeometry, not Alignment, so callers can pass a directional
  /// value — the swipe-to-read background must sit on the leading edge, which
  /// is the right-hand side in Arabic and Kurdish.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        Icons.mark_email_read_rounded,
        color: AppThemeConfig.accent(context),
      ),
    );
  }
}
