import 'package:flutter_application_1/api/history_api.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

class RoleHistoryController extends GetxController with RealtimePollingMixin {
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

  /// K21 — the identity code being looked up, or '' for the caller's own
  /// history.
  ///
  /// Empty is the default and the way back: clearing the box restores your own
  /// timeline, so the lookup can never strand you on somebody else's screen
  /// with no route home.
  final identityCode = ''.obs;

  int get _userId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  /// The signed-in account's own code, or '' when it has none (staff, guests,
  /// or a server too old to report it). Read from preferences, which
  /// `applyUserAccountToSharedPreferences` keeps in step with the server.
  String get ownIdentityCode =>
      sharedPreferences.getString('identity_code')?.trim() ?? '';

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
    final code = identityCode.value;
    if (code.isEmpty && _userId <= 0) {
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
      // K21 — a code names WHOSE history is wanted; without one this is the
      // caller's own, exactly as before.
      final data = code.isEmpty
          ? await const ModuleApi().roleHistory(userId: _userId)
          : await _historyForCode(code, silent: silent);
      if (data == null) return; // _historyForCode has set the message
      role.value = (data['role'] ?? '').toString();
      summary.assignAll(
        Map<String, dynamic>.from(data['summary'] as Map? ?? {}),
      );
      items.assignAll(
        ((data['items'] as List?) ?? const []).whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ),
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

  /// One identity-code lookup, or null when the server refused it.
  ///
  /// The refusal is turned into a SENTENCE here rather than being thrown.
  /// `getObject` reports every non-2xx as `Exception('Request failed (404)')`
  /// and the catch above assigns `e.toString()` into the message the screen
  /// renders — so a plain rethrow would print a status code at the user, which
  /// is nothing they can act on.
  Future<Map<String, dynamic>?> _historyForCode(
    String code, {
    required bool silent,
  }) async {
    final result = await fetchHistoryByCode(code);
    if (result.outcome == HistoryLookupOutcome.ok) return result.data;
    if (!silent) {
      // Cleared, not left stale: the rows on screen belong to whoever was
      // being shown before, and leaving them under a message about a different
      // code would attribute one person's history to another.
      items.clear();
      summary.clear();
      errorMessage.value = result.messageKey!.tr;
    }
    return null;
  }

  List<Map<String, dynamic>> get filteredItems {
    final now = DateTime.now();
    return items
        .where((item) {
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
          final parsed =
              DateTime.tryParse(rawDate.replaceFirst(' ', 'T')) ??
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
        })
        .toList(growable: false);
  }

  /// The screen title, as a TRANSLATION KEY — callers apply `.tr`.
  ///
  /// These must be the canonical English keys, not the en_US *output*. The
  /// donor case previously returned 'Contribution history', which is what the
  /// en_US map renames 'Donation history' TO — so `.tr` looked up a key that
  /// exists in no map and GetX fell back to the raw string, leaving the title
  /// in English on every Arabic and Kurdish build.
  String get title => switch (role.value) {
    'donor' => 'Donation history',
    'volunteer' => 'Volunteer history',
    'beneficiary' => 'Beneficiary history',
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

  /// K21 — points the screen at one identity code, or back at the caller's own
  /// history when [value] is blank. Does not load anything; see
  /// [lookUpIdentityCode].
  void setIdentityCode(String value) {
    final code = value.trim();
    if (code == identityCode.value) return;
    identityCode.value = code;
    // The filters were built from the PREVIOUS timeline's options, and the new
    // one may not offer them; leaving a stale filter selected would show an
    // empty list and blame the filters for it.
    selectedKind.value = 'all';
    selectedStatus.value = 'all';
  }

  /// Looks [value] up and loads whatever it names — the screen's own callback.
  ///
  /// Kept separate from [setIdentityCode] so the choice and the request are one
  /// job each, and so the rule can be exercised without a network.
  Future<void> lookUpIdentityCode(String value) async {
    setIdentityCode(value);
    await fetchHistory();
  }

  void setKind(String value) => selectedKind.value = value;

  void setStatus(String value) => selectedStatus.value = value;

  void setDateRange(String value) => selectedDateRange.value = value;
}
