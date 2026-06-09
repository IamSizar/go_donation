import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

class RoleDashboardController extends GetxController
    with RealtimePollingMixin {
  RoleDashboardController({ModuleApi? api}) : _api = api ?? const ModuleApi();

  final ModuleApi _api;

  final isLoading = false.obs;
  final errorMessage = RxnString();
  final roleKey = 'guest'.obs;
  final summary = <String, dynamic>{}.obs;

  int get userId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  String get roleId => sharedPreferences.getString('role_id') ?? '';

  // The home dashboard aggregates counts + totals — slower-moving than
  // individual status changes, so 10s is plenty to feel "live" without
  // hammering the dashboard summary endpoint.
  @override
  Duration get pollInterval => const Duration(seconds: 10);

  @override
  Future<void> realtimePoll() => fetchSummary(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchSummary();
    startPolling();
  }

  Future<void> fetchSummary({bool silent = false}) async {
    if (userId <= 0) {
      summary.assignAll(const <String, dynamic>{});
      roleKey.value = 'guest';
      errorMessage.value = 'Please sign in again.';
      return;
    }

    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final response = await _api.dashboardSummary(userId: userId);
      roleKey.value = (response['role_key'] ?? 'guest').toString();
      final nextSummary = response['summary'];
      summary.assignAll(
        nextSummary is Map
            ? Map<String, dynamic>.from(nextSummary)
            : const <String, dynamic>{},
      );
    } catch (e) {
      if (!silent) {
        errorMessage.value = e.toString();
      }
      // Silent polls keep the previous summary cards visible on errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }
}
