import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:get/get.dart';

class PartnersController extends GetxController {
  final partners = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  int get _uid =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  @override
  void onInit() {
    super.onInit();
    fetchPartners();
  }

  Future<void> fetchPartners() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await const ModuleApi().partners(userId: _uid);
      partners.assignAll(rows);
    } catch (_) {
      partners.clear();
      errorMessage.value = 'Unable to load partners.'.tr;
    } finally {
      isLoading.value = false;
    }
  }

  /// #27 — submit a rating; reconciles the card with the server aggregate.
  Future<void> submitRating(Map<String, dynamic> partner, int stars) async {
    final id = int.tryParse('${partner['id']}') ?? 0;
    if (id == 0) return;
    try {
      final res = await const ModuleApi().ratePartner(id, stars);
      partner['my_rating'] = (res['my_rating'] as num?)?.toInt() ?? stars;
      partner['avg_rating'] = (res['avg_rating'] as num?)?.toDouble();
      partner['rating_count'] = (res['rating_count'] as num?)?.toInt() ?? 0;
      partners.refresh();
      Get.snackbar('Thanks'.tr, 'Your rating was saved.'.tr);
    } catch (_) {
      Get.snackbar('Error'.tr, 'Could not save your rating.'.tr);
    }
  }
}
