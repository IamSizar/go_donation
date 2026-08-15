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

  // C2 — the chip row is an async region and now has the states to prove it.
  // It previously had none: a failure and an empty taxonomy both ended as an
  // empty list, and the row simply was not built. The map immediately below
  // it did show an error with a retry, so on a bad connection the same screen
  // reported a failure in one half and pretended nothing had happened in the
  // other.
  final sectorsLoading = false.obs;
  final sectorsError = RxnString();

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

  /// Loads the admin-managed sector taxonomy behind the filter chips.
  ///
  /// A failure is RECORDED rather than swallowed (C2). The old comment
  /// defended the silence — "an empty filter row claims nothing about the
  /// user's data" — and that is true of the row on its own. It stops being
  /// true on this screen, where a user who has just been told the map failed
  /// then finds the filter row gone too, with nothing saying why and nothing
  /// to press. The two halves have to agree.
  ///
  /// A successful response with no sectors is still empty, not an error: the
  /// row then renders nothing, which is correct, because there is no filter
  /// to offer and nothing went wrong.
  Future<void> fetchSectors() async {
    sectorsLoading.value = true;
    sectorsError.value = null;
    try {
      final rows = await const ModuleApi().citySectors();
      sectors.assignAll(rows);
    } catch (_) {
      sectors.clear();
      sectorsError.value = 'Could not load the sector filters.';
    } finally {
      sectorsLoading.value = false;
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
