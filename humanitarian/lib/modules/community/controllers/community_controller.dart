import 'package:flutter_application_1/api/module_api.dart';
import 'package:get/get.dart';

class CommunityController extends GetxController {
  final isLoading = false.obs;
  final entries = <Map<String, dynamic>>[].obs;
  final errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchEntries();
  }

  Future<void> fetchEntries() async {
    isLoading.value = true;
    errorMessage.value = null;

    try {
      final rows = await const ModuleApi().communityDirectory();
      entries.assignAll(rows);
    } catch (_) {
      entries.clear();
      errorMessage.value =
          'Unable to load directory entries from the server.'.tr;
    } finally {
      isLoading.value = false;
    }
  }
}
