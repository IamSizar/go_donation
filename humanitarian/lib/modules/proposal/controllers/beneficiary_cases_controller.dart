import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

/// Read-only feed of beneficiary cases shown to donors / public.
/// Polls slowly because the data changes when admin adds new published
/// cases — not minute-to-minute.
class BeneficiaryCasesController extends GetxController
    with RealtimePollingMixin {
  final isLoading = false.obs;
  final cases = <Map<String, dynamic>>[].obs;
  final errorMessage = RxnString();

  @override
  Duration get pollInterval => const Duration(seconds: 20);

  @override
  Future<void> realtimePoll() => fetchCases(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchCases();
    startPolling();
  }

  Future<void> fetchCases({bool silent = false}) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final rows = await const ModuleApi().beneficiaryCases();
      cases.assignAll(rows);
    } catch (_) {
      if (!silent) {
        cases.clear();
        errorMessage.value =
            'Unable to load beneficiary cases from the server.'.tr;
      }
    } finally {
      if (!silent) isLoading.value = false;
    }
  }
}

/// The beneficiary's own cases. Real-time polling here is the critical
/// one — when admin approves / rejects a submitted case, the beneficiary
/// should see the status change live and get a snackbar.
class MyBeneficiaryCasesController extends GetxController
    with RealtimePollingMixin {
  final isLoading = false.obs;
  final cases = <Map<String, dynamic>>[].obs;
  final errorMessage = RxnString();

  // Snapshot of case status by id, used to detect admin transitions.
  Map<String, String> _lastStatusSnapshot = {};

  @override
  Future<void> realtimePoll() => fetchCases(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchCases();
    startPolling();
  }

  Future<void> fetchCases({bool silent = false}) async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    if (userId.trim().isEmpty) {
      cases.clear();
      errorMessage.value = 'Please sign in again to load your cases.'.tr;
      return;
    }

    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final uri = Uri.parse(
        beneficiaryCasesUrl,
      ).replace(queryParameters: {'user_id': userId});
      final rows = await const ModuleApi().getItems(uri.toString());
      cases.assignAll(rows);
      _detectAndAnnounceTransitions();
    } catch (_) {
      if (!silent) {
        cases.clear();
        errorMessage.value = 'Unable to load your beneficiary cases.'.tr;
      }
      // Silent polls preserve the last good case list on transient errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  void _detectAndAnnounceTransitions() {
    final transitions = detectStatusTransitions<Map<String, dynamic>>(
      items: cases,
      keyOf: (m) => (m['id'] ?? '').toString(),
      statusOf: (m) => (m['status'] ?? '').toString().toLowerCase(),
      previous: _lastStatusSnapshot,
    );
    _lastStatusSnapshot = {
      for (final m in cases)
        (m['id'] ?? '').toString():
            (m['status'] ?? '').toString().toLowerCase(),
    };
    for (final t in transitions) {
      final msg = _messageForCaseTransition(t.toStatus);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'Case update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  /// User-facing copy for known beneficiary case transitions. Add
  /// keys here as the admin workflow grows.
  String? _messageForCaseTransition(String to) {
    switch (to) {
      case 'approved':
        return 'Your case was approved.'.tr;
      case 'rejected':
        return 'Your case was rejected.'.tr;
      case 'pending_review':
      case 'under_review':
        return 'Your case is being reviewed.'.tr;
      case 'archived':
        return 'Your case was archived.'.tr;
      case 'closed':
        return 'Your case has been closed.'.tr;
      default:
        return null;
    }
  }
}
