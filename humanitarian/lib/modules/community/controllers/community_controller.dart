import 'package:flutter_application_1/api/module_api.dart';
import 'package:get/get.dart';

class CommunityController extends GetxController {
  final isLoading = false.obs;
  final entries = <Map<String, dynamic>>[].obs;
  final errorMessage = RxnString();

  // #29 — City Guide sectors (admin-managed filter chips) + the currently
  // selected sector slug (null = show all).
  final sectors = <Map<String, dynamic>>[].obs;
  final selectedSector = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchEntries();
    fetchSectors();
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

  // #29 — best-effort: a failure just leaves the filter row empty, so the
  // directory still works without sectors.
  Future<void> fetchSectors() async {
    try {
      final rows = await const ModuleApi().citySectors();
      sectors.assignAll(rows);
    } catch (_) {
      sectors.clear();
    }
  }

  void selectSector(String? slug) {
    selectedSector.value = slug;
  }

  // Entries filtered by the selected sector (#29). An entry matches when its
  // `sectors` array contains the selected slug. No selection → all entries.
  List<Map<String, dynamic>> get filteredEntries {
    final slug = selectedSector.value;
    if (slug == null || slug.isEmpty) return entries.toList();
    return entries.where((e) {
      final raw = e['sectors'];
      if (raw is List) {
        return raw.map((s) => s.toString()).contains(slug);
      }
      return false;
    }).toList();
  }
}
