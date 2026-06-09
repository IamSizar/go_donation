import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

class SponsorshipsController extends GetxController
    with RealtimePollingMixin {
  final isLoading = false.obs;
  final isCancelling = false.obs;
  final items = <Map<String, dynamic>>[].obs;
  final errorMessage = RxnString();

  // Snapshot of sponsorship status by id, used to detect admin-side
  // transitions between polls (active → cancelled etc.).
  Map<String, String> _lastStatusSnapshot = {};

  @override
  void onInit() {
    super.onInit();
    fetchSponsorships();
    startPolling();
  }

  @override
  Future<void> realtimePoll() => fetchSponsorships(silent: true);

  /// When `silent: true`, doesn't flip the loading spinner — used by the
  /// real-time polling tick so the UI doesn't shimmer every 5 seconds.
  Future<void> fetchSponsorships({bool silent = false}) async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) {
      items.clear();
      errorMessage.value = 'Please sign in again.'.tr;
      return;
    }

    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().sponsorships(userId: userId);
      items.assignAll(rows);
      _detectAndAnnounceTransitions();
    } catch (_) {
      if (!silent) {
        items.clear();
        errorMessage.value = 'Unable to load sponsorships.'.tr;
      }
      // Silent mode keeps the previous data on screen so a dropped
      // poll doesn't blank the donor's sponsorship list.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Diff against the previous snapshot to surface admin-driven status
  /// changes. First poll has an empty snapshot so initial-state rows
  /// don't fire any toasts.
  void _detectAndAnnounceTransitions() {
    final transitions = detectStatusTransitions<Map<String, dynamic>>(
      items: items,
      keyOf: (m) => (m['id'] ?? '').toString(),
      statusOf: (m) => (m['status'] ?? '').toString().toLowerCase(),
      previous: _lastStatusSnapshot,
    );
    _lastStatusSnapshot = {
      for (final m in items)
        (m['id'] ?? '').toString():
            (m['status'] ?? '').toString().toLowerCase(),
    };
    for (final t in transitions) {
      final msg = _messageForSponsorshipTransition(t.fromStatus, t.toStatus);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'Sponsorship update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  String? _messageForSponsorshipTransition(String from, String to) {
    switch (to) {
      case 'active':
      case 'approved':
        return 'Your sponsorship was approved.'.tr;
      case 'cancelled':
        return 'Your sponsorship was cancelled.'.tr;
      case 'paused':
        return 'Your sponsorship has been paused.'.tr;
      case 'completed':
        return 'Your sponsorship has been completed.'.tr;
      default:
        return null;
    }
  }

  Future<bool> cancelSponsorship(int sponsorshipId) async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0 || sponsorshipId <= 0) {
      errorMessage.value = 'Sponsorship not found.'.tr;
      return false;
    }

    isCancelling.value = true;
    try {
      await const ModuleApi().cancelSponsorship(
        sponsorshipId: sponsorshipId,
        userId: userId,
      );
      await fetchSponsorships();
      return true;
    } catch (_) {
      errorMessage.value = 'Could not cancel sponsorship.'.tr;
      return false;
    } finally {
      isCancelling.value = false;
    }
  }
}
