import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../models/app_notification_model.dart';

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
    final style = _NotificationVisuals.fromCategory(
      notification.normalizedCategory,
    );
    final child = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppThemeConfig.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: style.isPinned
                ? style.color.withValues(alpha: 0.65)
                : AppThemeConfig.border(context),
          ),
          boxShadow: [
            BoxShadow(
              color: AppThemeConfig.shadow(context),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(style.icon, color: style.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.localizedTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppThemeConfig.text(context),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (!notification.isRead) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (notification.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(notification.createdAt!.toLocal()),
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _NotificationTag(
                        label: notification.categoryLabel.tr,
                        color: style.color,
                      ),
                      if (notification.priority > 0)
                        _NotificationTag(
                          label: 'Priority @priority'.trParams({
                            'priority': notification.priority.toString(),
                          }),
                          color: Colors.teal,
                        ),
                      if (notification.hasActionUrl)
                        _NotificationTag(
                          label: 'Open link'.tr,
                          color: Colors.blue,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.localizedMessage,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      height: 1.45,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onDismissed == null) return child;

    return Dismissible(
      key: ValueKey('notification-${notification.id}'),
      direction: DismissDirection.horizontal,
      background: _ReadBackground(alignment: Alignment.centerLeft),
      secondaryBackground: _ReadBackground(alignment: Alignment.centerRight),
      onDismissed: (_) => onDismissed?.call(),
      child: child,
    );
  }
}

class _ReadBackground extends StatelessWidget {
  const _ReadBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.mark_email_read_rounded, color: Colors.green.shade700),
    );
  }
}

class _NotificationTag extends StatelessWidget {
  const _NotificationTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NotificationVisuals {
  const _NotificationVisuals({
    required this.color,
    required this.icon,
    required this.isPinned,
  });

  final Color color;
  final IconData icon;
  final bool isPinned;

  factory _NotificationVisuals.fromCategory(String category) {
    switch (category) {
      case 'urgent':
        return _NotificationVisuals(
          color: Colors.red.shade700,
          icon: Icons.priority_high_rounded,
          isPinned: true,
        );
      case 'payment':
        return _NotificationVisuals(
          color: Colors.green.shade700,
          icon: Icons.payments_rounded,
          isPinned: true,
        );
      case 'campaign':
        return _NotificationVisuals(
          color: Colors.indigo.shade600,
          icon: Icons.campaign_rounded,
          isPinned: false,
        );
      case 'system':
        return _NotificationVisuals(
          color: Colors.blueGrey.shade700,
          icon: Icons.settings_rounded,
          isPinned: false,
        );
      case 'reminder':
        return _NotificationVisuals(
          color: Colors.amber.shade800,
          icon: Icons.event_available_rounded,
          isPinned: false,
        );
      default:
        return _NotificationVisuals(
          color: AppThemeConfig.primary,
          icon: Icons.notifications_active_rounded,
          isPinned: false,
        );
    }
  }
}
