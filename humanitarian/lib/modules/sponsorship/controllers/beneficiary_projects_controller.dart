import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

class BeneficiaryProjectsController extends GetxController
    with RealtimePollingMixin {
  final projects = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  // Snapshot of project status by id, for diff detection between polls.
  Map<String, String> _lastStatusSnapshot = {};

  @override
  Future<void> realtimePoll() => fetchProjects(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchProjects();
    startPolling();
  }

  Future<void> fetchProjects({bool silent = false}) async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    if (userId.trim().isEmpty) {
      projects.clear();
      errorMessage.value = 'Please sign in again to load your projects.'.tr;
      return;
    }

    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final uri = Uri.parse(
        submitBeneficiaryProjectUrl,
      ).replace(queryParameters: {'user_id': userId});
      final rows = await const ModuleApi().getItems(uri.toString());
      projects.assignAll(rows);
      _detectAndAnnounceTransitions();
    } catch (_) {
      if (!silent) {
        projects.clear();
        errorMessage.value = 'Unable to load your projects.'.tr;
      }
      // Silent polls preserve the previous project list on transient errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Diff project status snapshots; snackbar + haptic on each transition.
  void _detectAndAnnounceTransitions() {
    final transitions = detectStatusTransitions<Map<String, dynamic>>(
      items: projects,
      keyOf: (m) => (m['id'] ?? '').toString(),
      statusOf: (m) => (m['status'] ?? '').toString().toLowerCase(),
      previous: _lastStatusSnapshot,
    );
    _lastStatusSnapshot = {
      for (final m in projects)
        (m['id'] ?? '').toString():
            (m['status'] ?? '').toString().toLowerCase(),
    };
    for (final t in transitions) {
      final msg = _messageForProjectTransition(t.toStatus);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'Project update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  String? _messageForProjectTransition(String to) {
    switch (to) {
      case 'approved':
      case 'published':
        return 'Your project request was approved.'.tr;
      case 'rejected':
        return 'Your project request was rejected.'.tr;
      case 'in_progress':
      case 'active':
        return 'Your project is now in progress.'.tr;
      case 'completed':
        return 'Your project has been marked complete.'.tr;
      case 'on_hold':
        return 'Your project was placed on hold.'.tr;
      default:
        return null;
    }
  }
}
