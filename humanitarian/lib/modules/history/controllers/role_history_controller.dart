import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

class RoleHistoryController extends GetxController
    with RealtimePollingMixin {
  final isLoading = false.obs;
  final errorMessage = RxnString();
  final role = ''.obs;
  final summary = <String, dynamic>{}.obs;
  final items = <Map<String, dynamic>>[].obs;
  final kindOptions = <String>[].obs;
  final statusOptions = <String>[].obs;
  final selectedKind = 'all'.obs;
  final selectedStatus = 'all'.obs;
  final selectedDateRange = 'all'.obs;

  int get _userId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  // History feeds new rows when the admin posts actions — 10s feels
  // live enough without spamming the aggregated history endpoint.
  @override
  Duration get pollInterval => const Duration(seconds: 10);

  @override
  Future<void> realtimePoll() => fetchHistory(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchHistory();
    startPolling();
  }

  Future<void> fetchHistory({bool silent = false}) async {
    if (_userId <= 0) {
      errorMessage.value = 'Please sign in again to load your history.'.tr;
      items.clear();
      summary.clear();
      return;
    }

    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }
    try {
      final data = await const ModuleApi().roleHistory(userId: _userId);
      role.value = (data['role'] ?? '').toString();
      summary.assignAll(Map<String, dynamic>.from(data['summary'] as Map? ?? {}));
      items.assignAll(
        ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)),
      );
      kindOptions.assignAll(
        ((data['kind_options'] as List?) ?? const ['all'])
            .map((item) => item.toString())
            .toSet()
            .toList(),
      );
      statusOptions.assignAll(
        ((data['status_options'] as List?) ?? const ['all'])
            .map((item) => item.toString())
            .toSet()
            .toList(),
      );
      if (!kindOptions.contains(selectedKind.value)) {
        selectedKind.value = 'all';
      }
      if (!statusOptions.contains(selectedStatus.value)) {
        selectedStatus.value = 'all';
      }
    } catch (e) {
      if (!silent) {
        items.clear();
        summary.clear();
        errorMessage.value = e.toString();
      }
      // Silent polls preserve the previous history view on transient errors.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  List<Map<String, dynamic>> get filteredItems {
    final now = DateTime.now();
    return items.where((item) {
      final kind = (item['kind'] ?? '').toString();
      if (selectedKind.value != 'all' && selectedKind.value != kind) {
        return false;
      }

      final status = (item['status'] ?? '').toString();
      if (selectedStatus.value != 'all' && selectedStatus.value != status) {
        return false;
      }

      if (selectedDateRange.value == 'all') {
        return true;
      }

      final rawDate = (item['occurred_at'] ?? '').toString().trim();
      final parsed = DateTime.tryParse(rawDate.replaceFirst(' ', 'T')) ??
          DateTime.tryParse(rawDate);
      if (parsed == null) {
        return false;
      }

      final difference = now.difference(parsed).inDays;
      return switch (selectedDateRange.value) {
        '30d' => difference <= 30,
        '90d' => difference <= 90,
        _ => true,
      };
    }).toList(growable: false);
  }

  String get title => switch (role.value) {
        'donor' => 'Contribution history',
        'volunteer' => 'Volunteer history',
        'beneficiary' => 'Recipient history',
        _ => 'My history',
      };

  String get subtitle => switch (role.value) {
        'donor' =>
          'Review donations, sponsorships, payment status, and references in one place.',
        'volunteer' =>
          'Review mission signups, application status, attendance, and completed work.',
        'beneficiary' =>
          'Review your cases, help requests, support tickets, and status changes.',
        _ => 'Review your recent platform activity in one place.',
      };

  void setKind(String value) => selectedKind.value = value;

  void setStatus(String value) => selectedStatus.value = value;

  void setDateRange(String value) => selectedDateRange.value = value;
}
