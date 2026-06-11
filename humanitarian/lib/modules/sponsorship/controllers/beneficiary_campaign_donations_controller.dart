import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:get/get.dart';

class BeneficiaryCampaignDonationsController extends GetxController {
  final isLoading = false.obs;
  final errorMessage = RxnString();

  // List of campaigns, each with a nested 'donations' list.
  final campaigns = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetch();
  }

  Future<void> fetch() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final raw = await const ModuleApi().getObject(beneficiaryCampaignDonationsUrl);
      final list = raw['campaigns'];
      if (list is List) {
        campaigns.assignAll(
          list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      } else {
        campaigns.clear();
      }
    } catch (e) {
      errorMessage.value = 'Could not load campaign donations.'.tr;
    } finally {
      isLoading.value = false;
    }
  }

  int get totalDonations =>
      campaigns.fold(0, (sum, c) => sum + ((c['donations'] as List?)?.length ?? 0));

  double get totalRaised {
    double total = 0;
    for (final c in campaigns) {
      final donations = c['donations'] as List? ?? [];
      for (final d in donations) {
        total += double.tryParse((d['amount'] ?? '0').toString()) ?? 0;
      }
    }
    return total;
  }
}
