import 'package:flutter_application_1/api/module_api.dart';
import 'package:get/get.dart';

class PartnersController extends GetxController {
  final partners = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchPartners();
  }

  Future<void> fetchPartners() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await const ModuleApi().partners();
      partners.assignAll(rows);
    } catch (_) {
      partners.clear();
      errorMessage.value = 'Unable to load partners.'.tr;
    } finally {
      isLoading.value = false;
    }
  }
}
