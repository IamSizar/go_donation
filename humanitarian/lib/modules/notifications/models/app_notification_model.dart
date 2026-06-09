import 'package:flutter_application_1/localization/content_localizer.dart';

class AppNotificationModel {
  const AppNotificationModel({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.titleSorani,
    required this.titleBadini,
    required this.message,
    required this.messageAr,
    required this.messageSorani,
    required this.messageBadini,
    required this.notificationType,
    required this.notificationCategory,
    required this.priority,
    required this.isRead,
    required this.createdAt,
    this.readAt,
    this.actionUrl = '',
    this.relatedEntityType = '',
    this.relatedEntityId = '',
  });

  final String id;
  final String title;
  final String titleAr;
  final String titleSorani;
  final String titleBadini;
  final String message;
  final String messageAr;
  final String messageSorani;
  final String messageBadini;
  final String notificationType;
  final String notificationCategory;
  final int priority;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;
  final String actionUrl;
  final String relatedEntityType;
  final String relatedEntityId;

  AppNotificationModel copyWith({bool? isRead, DateTime? readAt}) {
    return AppNotificationModel(
      id: id,
      title: title,
      titleAr: titleAr,
      titleSorani: titleSorani,
      titleBadini: titleBadini,
      message: message,
      messageAr: messageAr,
      messageSorani: messageSorani,
      messageBadini: messageBadini,
      notificationType: notificationType,
      notificationCategory: notificationCategory,
      priority: priority,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      actionUrl: actionUrl,
      relatedEntityType: relatedEntityType,
      relatedEntityId: relatedEntityId,
    );
  }

  String get localizedTitle {
    return localizedContentFromValues(
      base: title,
      arabic: titleAr,
      sorani: titleSorani,
      badini: titleBadini,
    );
  }

  String get localizedMessage {
    return localizedContentFromValues(
      base: message,
      arabic: messageAr,
      sorani: messageSorani,
      badini: messageBadini,
    );
  }

  String get normalizedCategory {
    final value = notificationCategory.trim().toLowerCase();
    if (value == 'urgent' ||
        value == 'payment' ||
        value == 'campaign' ||
        value == 'system' ||
        value == 'reminder') {
      return value;
    }
    return _categoryFromType(notificationType);
  }

  String get categoryLabel {
    switch (normalizedCategory) {
      case 'urgent':
        return 'Urgent';
      case 'payment':
        return 'Payment';
      case 'campaign':
        return 'Campaign';
      case 'system':
        return 'System';
      case 'reminder':
        return 'Reminder';
      default:
        return 'Normal';
    }
  }

  int get sortWeight {
    final base = switch (normalizedCategory) {
      'urgent' => 600,
      'payment' => 500,
      'campaign' => 400,
      'system' => 300,
      'reminder' => 200,
      _ => 100,
    };
    return base + priority;
  }

  bool get hasActionUrl => actionUrl.trim().isNotEmpty;
  String _categoryFromType(String value) {
    final type = value.trim().toLowerCase();
    if (type.contains('urgent') ||
        type.contains('support') ||
        type.contains('case')) {
      return 'urgent';
    }
    if (type.contains('payment') ||
        type.contains('donation') ||
        type.contains('sponsorship')) {
      return 'payment';
    }
    if (type.contains('campaign') ||
        type.contains('project') ||
        type == 'media_post' ||
        type == 'news' ||
        type == 'activity') {
      return 'campaign';
    }
    if (type.contains('reminder') || type.contains('due')) {
      return 'reminder';
    }
    if (type.contains('system') || type.contains('admin')) {
      return 'system';
    }
    return 'normal';
  }
}
