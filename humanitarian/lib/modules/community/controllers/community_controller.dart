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

  // K16 — the curated sub-categories under each sector (migration 101, 27
  // rows, four languages). They were seeded and served from day one; the app
  // had simply never called `GET /api/city-categories`, so a sector opened
  // onto nothing and "التصنيف" on the add-a-place form was a typing box.
  final categories = <Map<String, dynamic>>[].obs;
  final selectedCategory = RxnString();
  final categoriesLoading = false.obs;
  final categoriesError = RxnString();

  /// J8 — the in-list search term, sent to the server as `?q=`.
  ///
  /// The directory is capped at 50 entries per response and is the list that
  /// grows fastest, so a local filter would go wrong soonest here. The server
  /// matches name, name_ar, address, phone AND category (`listings.go:354-357`)
  /// — which is why a phone number or a street pasted into the box finds the
  /// place, and a client-side name match never would.
  final searchQuery = ''.obs;

  /// Whether a query is narrowing the directory right now. Drives the empty
  /// copy: "no places listed" is a claim about the guide itself.
  bool get hasActiveSearch => searchQuery.value.trim().isNotEmpty;

  /// Applies [query] and reloads from the server. A no-op when unchanged.
  Future<void> setSearchQuery(String query) async {
    final next = query.trim();
    if (next == searchQuery.value) return;
    searchQuery.value = next;
    await fetchEntries();
  }

  @override
  void onInit() {
    super.onInit();
    fetchEntries();
    fetchSectors();
    fetchCategories();
  }

  Future<void> fetchEntries() async {
    isLoading.value = true;
    errorMessage.value = null;

    try {
      final rows = await const ModuleApi().communityDirectory(
        q: searchQuery.value,
      );
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

  /// Loads the sub-category catalogue. Same failure policy as [fetchSectors]:
  /// recorded, not swallowed, so the chip row can say what went wrong and
  /// offer a retry instead of silently not being there.
  Future<void> fetchCategories() async {
    categoriesLoading.value = true;
    categoriesError.value = null;
    try {
      final rows = await const ModuleApi().cityCategories();
      categories.assignAll(rows);
    } catch (_) {
      categories.clear();
      categoriesError.value = 'Could not load the sub-categories.';
    } finally {
      categoriesLoading.value = false;
    }
  }

  void selectSector(String? slug) {
    selectedSector.value = slug;
    // A sub-category belongs to exactly one sector, so keeping the old one
    // selected after switching would filter the list to nothing and read as
    // "the guide is empty" rather than "that combination cannot exist".
    selectedCategory.value = null;
  }

  void selectCategory(String? slug) {
    selectedCategory.value = slug;
  }

  /// The sub-categories offered under the currently selected sector.
  ///
  /// Empty when no sector is chosen, deliberately: 27 chips with no parent is
  /// not a filter, it is a wall, and the sectors exist precisely to narrow it
  /// first.
  List<Map<String, dynamic>> get categoriesForSelectedSector {
    final sector = selectedSector.value;
    if (sector == null || sector.isEmpty) return const [];
    return categories
        .where((c) => (c['sector_slug'] ?? '').toString() == sector)
        .toList();
  }

  /// Every spelling of [categorySlug] an entry's free-text `category` column
  /// might legitimately hold: the slug itself, and each of the four localized
  /// names.
  ///
  /// WHY MATCHING IS NOT JUST THE SLUG. Migration 101 deliberately left
  /// `city_directory_entries.category` in place rather than migrating it, so
  /// staff can retag at their own pace and nothing is lost. That column was
  /// filled in by hand and holds values like 'الصيدليات ومخازن المستلزمات
  /// الطبية' next to 'training' and 'asdsa'. Matching the slug alone would
  /// hide every place recorded before the curated list existed.
  Set<String> _spellingsOf(String categorySlug) {
    for (final c in categories) {
      if ((c['slug'] ?? '').toString() != categorySlug) continue;
      return {
        for (final key in const [
          'slug',
          'name_en',
          'name_ar',
          'name_ckb',
          'name_kmr',
        ])
          (c[key] ?? '').toString().trim().toLowerCase(),
      }..removeWhere((s) => s.isEmpty);
    }
    return {categorySlug.toLowerCase()};
  }

  // Entries filtered by the selected sector (#29) and, under it, the selected
  // sub-category (K16). An entry matches the sector when its `sectors` array
  // contains the slug; it matches the sub-category when its free-text
  // `category` equals any spelling of that sub-category.
  List<Map<String, dynamic>> get filteredEntries {
    final slug = selectedSector.value;
    var rows = entries.toList();

    if (slug != null && slug.isNotEmpty) {
      rows = rows.where((e) {
        final raw = e['sectors'];
        if (raw is List) {
          return raw.map((s) => s.toString()).contains(slug);
        }
        return false;
      }).toList();
    }

    final category = selectedCategory.value;
    if (category != null && category.isNotEmpty) {
      final spellings = _spellingsOf(category);
      rows = rows.where((e) {
        final value = (e['category'] ?? '').toString().trim().toLowerCase();
        return value.isNotEmpty && spellings.contains(value);
      }).toList();
    }

    return rows;
  }
}
