import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:get/get.dart';

/// #21 — loads the sponsorships that BENEFIT the logged-in beneficiary (their
/// case is being sponsored) for the "My Entitlements" screen.
class BeneficiaryEntitlementsController extends GetxController {
  final entitlements = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  int get _uid =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await const ModuleApi().sponsorshipsAsBeneficiary(_uid);
      entitlements.assignAll(rows);
    } catch (_) {
      entitlements.clear();
      errorMessage.value = 'Unable to load your entitlements.'.tr;
    } finally {
      isLoading.value = false;
    }
  }

  int get activeCount =>
      entitlements.where((e) => (e['status'] ?? '') == 'active').length;

  /// The entitlement with the earliest upcoming (or overdue) next_due_date.
  Map<String, dynamic>? get nextDue {
    Map<String, dynamic>? best;
    DateTime? bestDate;
    for (final e in entitlements) {
      final d = DateTime.tryParse((e['next_due_date'] ?? '').toString());
      if (d == null) continue;
      if (bestDate == null || d.isBefore(bestDate)) {
        bestDate = d;
        best = e;
      }
    }
    return best;
  }
}
