import 'package:flutter_application_1/api/module_api.dart';
import 'package:get/get.dart';

class MediaPostsController extends GetxController {
  final posts = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchPosts();
  }

  Future<void> fetchPosts() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await const ModuleApi().mediaPosts();
      posts.assignAll(rows);
    } catch (_) {
      posts.clear();
      errorMessage.value = 'Unable to load news and activities.'.tr;
    } finally {
      isLoading.value = false;
    }
  }
}
