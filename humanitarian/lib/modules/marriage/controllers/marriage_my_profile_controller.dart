import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

// Note #18 — mirrors BeneficiaryProjectsController (sponsorship module):
// same polling + status-transition-snackbar pattern, applied to the
// current user's OWN marriage profile so they see it move from
// "submitted" to "active"/"rejected"/etc without having to ask staff.
class MarriageMyProfileController extends GetxController
    with RealtimePollingMixin {
  final profiles = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  Map<String, String> _lastStatusSnapshot = {};

  @override
  Future<void> realtimePoll() => fetchProfiles(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchProfiles();
    startPolling();
  }

  Future<void> fetchProfiles({bool silent = false}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().getItems(myMarriageProfileUrl);
      profiles.assignAll(rows);
      _detectAndAnnounceTransitions();
    } catch (_) {
      if (!silent) {
        profiles.clear();
        errorMessage.value = 'marriage_my_profile_load_failed'.tr;
      }
      // Silent polls preserve the previous list on transient errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  void _detectAndAnnounceTransitions() {
    final transitions = detectStatusTransitions<Map<String, dynamic>>(
      items: profiles,
      keyOf: (m) => (m['id'] ?? '').toString(),
      statusOf: (m) => (m['status'] ?? '').toString().toLowerCase(),
      previous: _lastStatusSnapshot,
    );
    _lastStatusSnapshot = {
      for (final m in profiles)
        (m['id'] ?? '').toString(): (m['status'] ?? '').toString().toLowerCase(),
    };
    for (final t in transitions) {
      final msg = _messageForTransition(t.toStatus);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'marriage_status_update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  String? _messageForTransition(String to) {
    switch (to) {
      case 'under_review':
        return 'marriage_now_under_review'.tr;
      case 'active':
        return 'marriage_now_active'.tr;
      case 'matched':
        return 'marriage_now_matched'.tr;
      case 'rejected':
        return 'marriage_now_rejected'.tr;
      case 'paused':
        return 'marriage_now_paused'.tr;
      case 'closed':
        return 'marriage_now_closed'.tr;
      default:
        return null;
    }
  }
}
