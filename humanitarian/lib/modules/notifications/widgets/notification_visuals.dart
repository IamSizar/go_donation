// notification_visuals.dart — the colour and icon a notification card is
// drawn in, chosen from the notification's category and type.
//
// WHY THIS IS ITS OWN FILE
// It was the private _NotificationVisuals at the bottom of
// notification_tile.dart. Moving the chat request actions out (OPOS #26473)
// still left that file over the project's 500-line limit, and this mapping is
// a pure lookup with no widget state, so it was the next cohesive piece to
// split off. The mapping itself did not change.
//
// HOW A CARD'S LOOK IS CHOSEN
//   • colour and `isPinned` come from the normalized CATEGORY (urgent,
//     payment, campaign, system, reminder, or the general default);
//   • the icon starts as the category's and is refined by the notification
//     TYPE, so a chat request and a donation look different inside one
//     category.
//
// Consumers: NotificationTile and its private _IconBadge / _CategoryChip
// (notification_tile.dart).
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';

import '../models/app_notification_model.dart';

/// Per-type/category visual styling: a colour and an icon. Colour comes from
/// the category (urgent/payment/…) while
/// the icon is refined by the concrete notification *type* so a chat request,
/// a donation and a campaign update each look distinct even within a category.
///
/// Build one with [NotificationVisuals.of]; the constructor is private so the
/// mapping below stays the only source of a card's look.
class NotificationVisuals {
  const NotificationVisuals._({
    required this.color,
    required this.icon,
    required this.isPinned,
  });

  /// The category colour: the card's spine, icon badge, chips, unread dot and
  /// unread wash.
  final Color color;

  /// The icon shown in the badge and in the category chip.
  final IconData icon;

  /// Whether a READ card keeps a hint of [color] in its border (urgent and
  /// payment), so high-stakes alerts never fully fade out.
  final bool isPinned;

  /// Resolves the look of [n] in the current theme; [context] supplies the
  /// theme's semantic colours. Never fails: an unknown category gets the
  /// general default and an unknown type keeps the category icon.
  factory NotificationVisuals.of(BuildContext context, AppNotificationModel n) {
    final base = _byCategory(context, n.normalizedCategory);
    final icon = _iconForType(n.notificationType) ?? base.icon;
    return NotificationVisuals._(
      color: base.color,
      icon: icon,
      isPinned: base.isPinned,
    );
  }

  static NotificationVisuals _byCategory(
    BuildContext context,
    String category,
  ) {
    switch (category) {
      case 'urgent':
        return NotificationVisuals._(
          color: AppThemeConfig.consequence(context),
          icon: Icons.priority_high_rounded,
          isPinned: true,
        );
      case 'payment':
        return NotificationVisuals._(
          color: AppThemeConfig.accent(context),
          icon: Icons.payments_rounded,
          isPinned: true,
        );
      case 'campaign':
        return NotificationVisuals._(
          color: AppThemeConfig.accent(context),
          icon: Icons.campaign_rounded,
          isPinned: false,
        );
      case 'system':
        return NotificationVisuals._(
          color: AppThemeConfig.subtleText(context),
          icon: Icons.settings_suggest_rounded,
          isPinned: false,
        );
      case 'reminder':
        return NotificationVisuals._(
          color: AppThemeConfig.pending(context),
          icon: Icons.event_available_rounded,
          isPinned: false,
        );
      default:
        return NotificationVisuals._(
          color: AppThemeConfig.accent(context),
          icon: Icons.notifications_active_rounded,
          isPinned: false,
        );
    }
  }

  /// Refine the icon by the concrete notification type. Returns null to keep
  /// the category default.
  static IconData? _iconForType(String type) {
    final t = type.trim().toLowerCase();
    if (t.contains('chat') || t.contains('message')) {
      return Icons.forum_rounded;
    }
    if (t.contains('donation') || t.contains('payment')) {
      return Icons.volunteer_activism_rounded;
    }
    if (t.contains('sponsor') || t.contains('kafala')) {
      return Icons.diversity_1_rounded;
    }
    if (t.contains('project') || t.contains('campaign')) {
      return Icons.campaign_rounded;
    }
    if (t == 'media_post' || t == 'news' || t == 'activity') {
      return Icons.article_rounded;
    }
    if (t.contains('partner')) {
      return Icons.handshake_rounded;
    }
    if (t.contains('support') || t.contains('ticket')) {
      return Icons.support_agent_rounded;
    }
    if (t.contains('marriage')) {
      return Icons.favorite_rounded;
    }
    if (t.contains('volunteer') || t.contains('mission')) {
      return Icons.assignment_turned_in_rounded;
    }
    if (t.contains('reminder') || t.contains('due')) {
      return Icons.event_available_rounded;
    }
    if (t.contains('approve') || t.contains('accepted')) {
      return Icons.verified_rounded;
    }
    if (t.contains('reject') || t.contains('declined')) {
      return Icons.cancel_rounded;
    }
    return null;
  }
}
