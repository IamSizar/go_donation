import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:flutter_application_1/modules/donations/models/donation_history_models.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class MyDonationsController extends GetxController
    with RealtimePollingMixin {
  final isLoading = false.obs;
  final errorMessage = RxnString();
  final summary = DonationHistorySummary.empty.obs;
  final items = <DonationHistoryEntry>[].obs;

  // Snapshot of donation status by id, used to detect admin-side
  // transitions (e.g. pending → confirmed) between polls and pop a
  // snackbar so the donor sees the update happen live.
  Map<String, String> _lastStatusSnapshot = {};

  @override
  void onInit() {
    super.onInit();
    fetchHistory();
    startPolling();
  }

  @override
  Future<void> realtimePoll() => fetchHistory(silent: true);

  /// POST `user_id` (preferred by API). Requires logged-in `id_user` in prefs.
  /// When `silent: true`, doesn't flip the loading spinner — used by the
  /// real-time polling tick so the UI doesn't shimmer every 5 seconds.
  Future<void> fetchHistory({bool silent = false}) async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) {
      errorMessage.value = 'Please sign in to see your donations.'.tr;
      summary.value = DonationHistorySummary.empty;
      items.clear();
      return;
    }

    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }

    try {
      final response = await http.post(
        Uri.parse(myDonationsHistoryUrl),
        headers: withApiAuthHeaders(),
        body: {
          'user_id': '$userId',
          if (apiAuthTokenFieldValue() != null)
            'access_token': apiAuthTokenFieldValue()!,
        },
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        errorMessage.value = 'Invalid response from server.'.tr;
        summary.value = DonationHistorySummary.empty;
        items.clear();
        return;
      }

      if (decoded is! Map) {
        errorMessage.value = 'Invalid response from server.'.tr;
        summary.value = DonationHistorySummary.empty;
        items.clear();
        return;
      }

      final map = decoded;

      if (response.statusCode == 400) {
        errorMessage.value =
            map['error']?.toString() ?? 'Missing or invalid user.'.tr;
        summary.value = DonationHistorySummary.empty;
        items.clear();
        return;
      }

      if (map['success'] != true) {
        errorMessage.value =
            map['error']?.toString() ?? 'Could not load donations.'.tr;
        if (map['summary'] is Map) {
          summary.value = DonationHistorySummary.fromJson(
            map['summary'] as Map,
          );
        } else {
          summary.value = DonationHistorySummary.empty;
        }
        if (map['items'] is List) {
          items.assignAll(
            (map['items'] as List).whereType<Map>().map(
              (e) => DonationHistoryEntry.fromJson(e),
            ),
          );
        } else {
          items.clear();
        }
        return;
      }

      final summaryJson = map['summary'];
      if (summaryJson is Map) {
        summary.value = DonationHistorySummary.fromJson(summaryJson);
      } else {
        summary.value = DonationHistorySummary.empty;
      }

      final list = map['items'];
      if (list is List) {
        items.assignAll(
          list.whereType<Map>().map((e) => DonationHistoryEntry.fromJson(e)),
        );
      } else {
        items.clear();
      }

      errorMessage.value = null;

      // Phase 27 — diff against the previous snapshot to surface
      // admin-driven status changes (confirmed / cancelled / delivered)
      // with a gentle snackbar + haptic. First poll has an empty
      // snapshot so initial-state rows don't fire any toasts.
      _detectAndAnnounceTransitions();
    } catch (_) {
      if (!silent) {
        errorMessage.value =
            'Could not reach the server. Check your connection.'.tr;
        summary.value = DonationHistorySummary.empty;
        items.clear();
      }
      // In silent mode we keep the previous state on the screen — a
      // dropped poll shouldn't blank out the donor's donations list.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Compute the diff between the previous snapshot and the current
  /// items list, snackbar+haptic for each transition, then update the
  /// snapshot for the next poll. We key by `reference` ("#12" etc.)
  /// because the model doesn't preserve the raw id — that's stable
  /// enough since references are server-issued and immutable.
  void _detectAndAnnounceTransitions() {
    final transitions = detectStatusTransitions<DonationHistoryEntry>(
      items: items,
      keyOf: (d) => d.reference,
      statusOf: (d) => d.status.name, // success | pending | failed
      previous: _lastStatusSnapshot,
    );
    _lastStatusSnapshot = {
      for (final d in items) d.reference: d.status.name,
    };

    for (final t in transitions) {
      final msg = _messageForDonationTransition(t.fromStatus, t.toStatus, t.key);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'Donation update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  /// Localized snackbar copy for each known donation transition. Return
  /// null to suppress noise (e.g. admin re-saved the same status).
  String? _messageForDonationTransition(String from, String to, String ref) {
    switch (to) {
      case 'success':
        return 'Donation $ref was confirmed. Thank you!'.tr;
      case 'failed':
        return 'Donation $ref could not be confirmed.'.tr;
      case 'pending':
        // Backward transitions (success → pending) are unusual but valid
        // — admin "unconfirmed" the row. Still surface it.
        return 'Donation $ref is back under review.'.tr;
      default:
        return null;
    }
  }
}
