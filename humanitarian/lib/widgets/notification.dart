import 'package:flutter/material.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/widgets/notification_tile.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';

class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<NotificationsController>()
        ? Get.find<NotificationsController>()
        : Get.put(NotificationsController());

    return SectionScaffold(
      title: 'Notifications',
      subtitle:
          'Stay updated with campaign alerts, sponsorship news, and reminders.',
      child: Obx(() {
        final items = controller.unreadNotifications;
        // Four hand-written branches replaced by AppAsync, which renders
        // exactly ONE state. Each branch here built its own shell - a bare
        // Center for loading, a one-item ListView for the error, a centred
        // sentence for empty - so the three states shared no geometry and the
        // list appeared to jump as it settled. The empty state was also a
        // bare sentence with no illustration or action.
        return AppAsync<List<AppNotificationModel>>(
          loading: controller.isLoading.value,
          error: controller.errorMessage.value,
          onRetry: controller.refreshNotifications,
          data: items,
          isEmpty: (list) => list.isEmpty,
          empty: AppEmpty(
            title: 'Notifications'.tr,
            message: 'No unread notifications.'.tr,
          ),
          builder: (list) => RefreshIndicator(
            onRefresh: controller.refreshNotifications,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notification = list[index];
                return NotificationTile(
                  notification: notification,
                  onTap: () => controller.openNotification(notification),
                  onDismissed: () => controller.markAsRead(notification),
                );
              },
            ),
          ),
        );
      }),
    );
  }
}
