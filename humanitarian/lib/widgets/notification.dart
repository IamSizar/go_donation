import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/widgets/notification_tile.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

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
        final error = controller.errorMessage.value;

        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (error != null) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            children: [
              SectionTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notifications',
                subtitle: error,
                color: Colors.amber,
                onTap: controller.refreshNotifications,
              ),
            ],
          );
        }

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No unread notifications.'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppThemeConfig.mutedText(context),
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.refreshNotifications,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final notification = items[index];
              return NotificationTile(
                notification: notification,
                onTap: () => controller.openNotification(notification),
                onDismissed: () => controller.markAsRead(notification),
              );
            },
          ),
        );
      }),
    );
  }
}
