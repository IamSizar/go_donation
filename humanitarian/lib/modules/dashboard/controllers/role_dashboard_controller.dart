import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class RoleDashboardController extends GetxController with RealtimePollingMixin {
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
      // The summary's `role_key` is the server's answer to "what is this
      // account", and until now it lived only in the observable above — which
      // this screen's body reads and nothing else does. Every other role gate
      // in the app reads `role_id` out of SharedPreferences, and that copy was
      // only ever written when the USER acted (registration, sign-in, choosing
      // a type). A role granted by staff therefore never reached it: a device
      // was found holding role_id "1" for an account the server reports as 2,
      // so Services, Kafala, Settings and the assistant all behaved as donor
      // for a beneficiary.
      //
      // Writing it back here is not a new source of truth, it is the same one
      // reaching further: this runs on the load AND on the silent 10s poll, so
      // a role change lands within one poll of the home screen being open.
      await applyServerRoleKeyToSharedPreferences(roleKey.value);
      final nextSummary = response['summary'];
      summary.assignAll(
        nextSummary is Map
            ? Map<String, dynamic>.from(nextSummary)
            : const <String, dynamic>{},
      );
    } catch (e) {
      if (!silent) {
        // A sentence, not `e.toString()`. That put "Exception: Request failed
        // (500)" on the home screen of a humanitarian app — a stack-trace
        // fragment where a human explanation belongs (rule 5.7). The cause is
        // logged instead, so support can still trace it.
        errorMessage.value = 'Could not load your dashboard.';
        debugPrint('dashboardSummary failed: $e');
      }
      // Silent polls keep the previous summary cards visible on errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }
}
