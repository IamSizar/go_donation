import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_notification_model.dart';

class NotificationsController extends GetxController {
  final notifications = <AppNotificationModel>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();
  final selectedReadStatus = 'all'.obs;
  final selectedCategory = 'all'.obs;
  final selectedType = 'all'.obs;

  int get unreadCount =>
      notifications.where((notification) => !notification.isRead).length;

  List<AppNotificationModel> get unreadNotifications => notifications
      .where((notification) => !notification.isRead)
      .toList(growable: false);

  List<String> get availableTypes {
    final values =
        notifications
            .map((notification) => notification.notificationType.trim())
            .where((type) => type.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  List<AppNotificationModel> get filteredNotifications {
    return notifications
        .where((notification) {
          final matchesRead = switch (selectedReadStatus.value) {
            'read' => notification.isRead,
            'unread' => !notification.isRead,
            _ => true,
          };
          final matchesCategory =
              selectedCategory.value == 'all' ||
              notification.normalizedCategory == selectedCategory.value;
          final matchesType =
              selectedType.value == 'all' ||
              notification.notificationType == selectedType.value;
          return matchesRead && matchesCategory && matchesType;
        })
        .toList(growable: false);
  }

  // Phase 25 — auto-refresh polling so notifications fired by admin
  // (approve / mark completed / etc.) appear in the inbox within ~5s
  // without a manual pull. The chime / haptic only fires when at least
  // one NEW notification id appeared since the previous poll, so an
  // unchanged refresh is silent.
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 5);
  Set<String> _seenIds = {};

  @override
  void onInit() {
    super.onInit();
    refreshNotifications();
    // Start the periodic poll. We don't await the initial refresh — the
    // first tick fires after _pollInterval, which is fine.
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentRefresh());
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.onClose();
  }

  /// Same as refreshNotifications but without flipping isLoading (no
  /// spinner), and detects newly-arrived rows for a gentle haptic so
  /// the volunteer feels the update happen even if the snackbar from
  /// the volunteer-hub poll already fired.
  Future<void> _silentRefresh() async {
    final beforeIds = Set<String>.from(_seenIds);
    try {
      // silent: no spinner, no list-clear on failure, and the list is only
      // reassigned when its contents actually changed — so an unchanged poll
      // is a true no-op (no rebuild, no flicker).
      await refreshNotifications(silent: true);
    } catch (_) {
      // Silent fail — preserve previous state. Next tick retries.
      return;
    }
    final nowIds = notifications.map((n) => n.id).toSet();
    final newOnes = nowIds.difference(beforeIds);
    _seenIds = nowIds;
    // Skip haptic + chime on the very first poll — those are
    // pre-existing rows, not "new arrivals" from the volunteer's
    // perspective. Phase 27.1: paired sound (AppSound.notification) so
    // the chime actually plays now, fixing the dead "chime" comment.
    if (beforeIds.isNotEmpty && newOnes.isNotEmpty) {
      AppSound.notification();
      AppHaptics.gentle();
    }
  }

  /// Fetches the latest notifications.
  ///
  /// When [silent] is true (the periodic poll), the loading spinner is NOT
  /// shown, a failed request leaves the current list untouched, and the
  /// observable list is only reassigned when its contents actually changed —
  /// so a poll that returns the same data is a genuine no-op and the list never
  /// flickers or "reloads". The non-silent path (first load / pull-to-refresh)
  /// keeps the spinner and clears on error as before.
  Future<void> refreshNotifications({bool silent = false}) async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    final roleId = sharedPreferences.getString('role_id') ?? '';
    final query = <String, String>{
      if (userId.isNotEmpty) 'user_id': userId,
      if (roleId.isNotEmpty) 'role_id': roleId,
    };
    final uri = Uri.parse(appNotificationsUrl).replace(queryParameters: query);
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().getItems(uri.toString());
      final fetched = rows
          .map(
            (row) => AppNotificationModel(
              id: (row['id'] ?? '').toString(),
              title: (row['title'] ?? 'Notification').toString(),
              titleAr: (row['title_ar'] ?? '').toString(),
              titleSorani: (row['title_sorani'] ?? '').toString(),
              titleBadini: (row['title_badini'] ?? '').toString(),
              message: (row['body'] ?? '').toString(),
              messageAr: (row['body_ar'] ?? '').toString(),
              messageSorani: (row['body_sorani'] ?? '').toString(),
              messageBadini: (row['body_badini'] ?? '').toString(),
              notificationType: (row['notification_type'] ?? '').toString(),
              notificationCategory: (row['notification_category'] ?? '')
                  .toString(),
              priority: int.tryParse((row['priority'] ?? '0').toString()) ?? 0,
              isRead: (row['is_read'] ?? '0').toString() == '1',
              createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
              readAt: DateTime.tryParse((row['read_at'] ?? '').toString()),
              actionUrl: (row['action_url'] ?? '').toString(),
              relatedEntityType: (row['related_entity_type'] ?? '').toString(),
              relatedEntityId: (row['related_entity_id'] ?? '').toString(),
            ),
          )
          .toList()
        ..sort(_compareNotifications);

      // Only touch the observable list when something actually changed. This is
      // what stops the every-5s rebuild: an unchanged poll skips assignAll, so
      // Obx never fires and the ListView is left exactly as it is.
      if (!_sameNotifications(notifications, fetched)) {
        notifications.assignAll(fetched);
      }
      if (!silent) errorMessage.value = null;
    } catch (e) {
      if (silent) {
        // Keep the existing list, stay quiet; let _silentRefresh skip its
        // new-arrival chime by surfacing the failure.
        rethrow;
      }
      notifications.clear();
      errorMessage.value = 'Unable to load notifications.'.tr;
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Stable ordering: unread urgent/payment first, then sort weight, then newest.
  int _compareNotifications(AppNotificationModel a, AppNotificationModel b) {
    final aPinned =
        !a.isRead &&
        (a.normalizedCategory == 'urgent' ||
            a.normalizedCategory == 'payment');
    final bPinned =
        !b.isRead &&
        (b.normalizedCategory == 'urgent' ||
            b.normalizedCategory == 'payment');
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    final weightCompare = b.sortWeight.compareTo(a.sortWeight);
    if (weightCompare != 0) return weightCompare;
    final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  }

  /// True when both lists render identically — same rows, same order, same
  /// read state / content. Used to skip needless list reassignment on polls.
  bool _sameNotifications(
    List<AppNotificationModel> current,
    List<AppNotificationModel> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (_signature(current[i]) != _signature(next[i])) return false;
    }
    return true;
  }

  String _signature(AppNotificationModel n) =>
      '${n.id}|${n.isRead}|${n.priority}|${n.title}|${n.message}'
      '|${n.createdAt?.millisecondsSinceEpoch ?? 0}';

  /// Phase 27.1 — mark every currently-unread notification as read in a
  /// single sweep. Optimistic UI update so the hero card flips to "all
  /// caught up" instantly; rolls back any individual row that fails.
  Future<void> markAllAsRead() async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    if (userId.isEmpty) return;

    final pending = notifications
        .where((n) => !n.isRead)
        .toList(growable: false);
    if (pending.isEmpty) return;

    // Snapshot for rollback. We update the rx list first so the UI feels
    // instant, then fire the POST per row. If a request fails, restore
    // just that row's previous state.
    final originalById = {for (final n in pending) n.id: n};
    final now = DateTime.now();
    for (final n in pending) {
      final i = notifications.indexWhere((item) => item.id == n.id);
      if (i >= 0) {
        notifications[i] = n.copyWith(isRead: true, readAt: now);
      }
    }
    notifications.refresh();

    final failures = <AppNotificationModel>[];
    for (final n in pending) {
      try {
        await const ModuleApi().postJson(appNotificationsUrl, {
          'action': 'mark_read',
          'id': n.id,
          'user_id': userId,
        });
      } catch (_) {
        failures.add(originalById[n.id]!);
      }
    }

    if (failures.isNotEmpty) {
      // Restore the rows that didn't reach the server so subsequent polls
      // don't permanently desync. The polling refresh would self-heal too,
      // but doing it eagerly avoids a 5s window of wrong state.
      for (final orig in failures) {
        final i = notifications.indexWhere((item) => item.id == orig.id);
        if (i >= 0) notifications[i] = orig;
      }
      notifications.refresh();
      errorMessage.value =
          '${failures.length} could not be marked. Try again.'.tr;
    }
  }

  Future<void> markAsRead(AppNotificationModel notification) async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    if (userId.isEmpty || notification.isRead) return;

    final index = notifications.indexWhere(
      (item) => item.id == notification.id,
    );
    if (index < 0) return;
    final updated = notification.copyWith(isRead: true, readAt: DateTime.now());
    notifications[index] = updated;
    notifications.refresh();
    try {
      await const ModuleApi().postJson(appNotificationsUrl, {
        'action': 'mark_read',
        'id': notification.id,
        'user_id': userId,
      });
    } catch (_) {
      notifications[index] = notification;
      notifications.refresh();
      errorMessage.value = 'Unable to mark notification as read.'.tr;
    }
  }

  void setReadStatus(String value) {
    selectedReadStatus.value = value;
  }

  void setCategory(String value) {
    selectedCategory.value = value;
  }

  void setType(String value) {
    selectedType.value = value;
  }

  Future<void> openNotification(AppNotificationModel notification) async {
    await markAsRead(notification);
    if (notification.hasActionUrl) {
      final uri = Uri.tryParse(notification.actionUrl.trim());
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    switch (notification.notificationType) {
      case 'media_post':
      case 'news':
      case 'activity':
        Get.to(() => const NewsActivitiesScreen());
        break;
      case 'partner':
        Get.to(() => const PartnersScreen());
        break;
      case 'support_ticket':
        Get.to(() => const SupportTicketFormScreen());
        break;
      default:
        break;
    }
  }
}
