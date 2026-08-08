import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../models/app_notification_model.dart';

/// Tapping a notification opens this: the full record, rather than a title and
/// a truncated message.
///
/// Before, a tap only marked the item read and — for three of the notification
/// types — navigated somewhere. Every other type did nothing visible, so a long
/// message could never be read in full. The dialog always shows everything, and
/// still offers the type's destination as an action when there is one.
Future<void> showNotificationDetail(
  BuildContext context,
  AppNotificationModel n, {
  VoidCallback? onOpen,
  String? openLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _NotificationDetailDialog(
      notification: n,
      onOpen: onOpen,
      openLabel: openLabel,
    ),
  );
}

class _NotificationDetailDialog extends StatelessWidget {
  const _NotificationDetailDialog({
    required this.notification,
    this.onOpen,
    this.openLabel,
  });

  final AppNotificationModel notification;
  final VoidCallback? onOpen;
  final String? openLabel;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final created = n.createdAt;
    return AlertDialog(
      backgroundColor: AppThemeConfig.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        n.localizedTitle,
        style: TextStyle(
          color: AppThemeConfig.text(context),
          fontWeight: FontWeight.w800,
          fontSize: 17,
          height: 1.3,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category + date sit together as the record's context line.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pill(label: n.categoryLabel),
                if (created != null)
                  Text(
                    DateFormat('yyyy-MM-dd · HH:mm').format(created.toLocal()),
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (n.localizedMessage.trim().isNotEmpty)
              Text(
                n.localizedMessage,
                style: TextStyle(
                  color: AppThemeConfig.text(context),
                  fontSize: 14.5,
                  height: 1.55,
                ),
              )
            else
              Text(
                'No details'.tr,
                style: TextStyle(color: AppThemeConfig.mutedText(context)),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        if (onOpen != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onOpen!();
            },
            child: Text(openLabel ?? 'Open'.tr),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'.tr),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppThemeConfig.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppThemeConfig.primary,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
