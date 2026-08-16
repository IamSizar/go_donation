// K15 — الفئات and العلامات التجارية: the two product-list labels whose options
// come from the SERVER rather than from the page in hand.
//
// WHY THEY ARE A MIXIN AND NOT PART OF THE CONTROLLER
// MarketplaceController already owns products, paging, the cart, orders and the
// wallet balance; adding two more loaders and their four state flags each put
// it over this repo's 500-line ceiling. These two belong together — both are
// facets, both feed a picker sheet, both fail the same way — so they move
// together rather than being trimmed apart.
//
// WHY BOTH SIGNAL FAILURE INSTEAD OF CLEARING QUIETLY
// fetchCategories used to end in `catch (_) { categories.clear(); }`, with a
// comment arguing that a missing label is a smaller lie than a stale one. That
// was sound while the list only NAMED things on a card. It stopped being sound
// the moment الفئات became a filter the user opens on purpose: a failed load
// and an empty taxonomy then look identical, and neither offers a way to try
// again. That is C2's finding on the City Guide's sector chips, and it applies
// here for the same reason.
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';

/// The two server-supplied facets behind الفئات and العلامات التجارية.
mixin CatalogueFacets on GetxController {
  /// #28 — the admin-managed category list. Labels a product card AND filters
  /// the catalogue.
  final categories = <Map<String, dynamic>>[].obs;
  final isLoadingCategories = false.obs;
  final categoriesError = RxnString();

  /// K15 — {brand, product_count} rows from GET /api/marketplace/brands.
  final brands = <Map<String, dynamic>>[].obs;
  final isLoadingBrands = false.obs;
  final brandsError = RxnString();

  /// #28 — the category list, used both to LABEL a product card and (K15) to
  /// FILTER by الفئات.
  ///
  /// It used to end in `catch (_) { categories.clear(); }`, with a comment
  /// arguing that a missing label is a smaller lie than a stale one. That was
  /// sound while this list only named things. It stopped being sound the moment
  /// it became a filter the user opens on purpose: a failed load and an empty
  /// taxonomy then look identical, and neither offers a way to try again —
  /// the same defect C2 fixed on the City Guide's sector chips.
  ///
  /// The product feed still works without it: the label falls back to the
  /// legacy free-text category, and the picker shows its own error rather than
  /// blocking the list.
  Future<void> fetchCategories() async {
    isLoadingCategories.value = true;
    categoriesError.value = null;
    try {
      categories.assignAll(await const ModuleApi().marketplaceCategories());
    } catch (_) {
      categories.clear();
      categoriesError.value = 'catalogue_categories_failed'.tr;
    } finally {
      isLoadingCategories.value = false;
    }
  }

  /// K15 — العلامات التجارية, straight from the server's facet.
  ///
  /// The app never derives this list from the products it happens to be
  /// holding: that would offer the brands of one page and count them wrong.
  /// GET /api/marketplace/brands counts approved products, so a chip promising
  /// eleven opens onto eleven.
  Future<void> fetchBrands() async {
    isLoadingBrands.value = true;
    brandsError.value = null;
    try {
      brands.assignAll(await const ModuleApi().marketplaceBrands());
    } catch (_) {
      brands.clear();
      brandsError.value = 'catalogue_brands_failed'.tr;
    } finally {
      isLoadingBrands.value = false;
    }
  }

  String localizedCategoryName(Map<String, dynamic> cat) {
    const byLang = {
      'en': 'name_en',
      'ar': 'name_ar',
      'ckb': 'name_ckb',
      'kmr': 'name_kmr',
    };
    final key = byLang[AppLocaleService.assistantLang()] ?? 'name_en';
    final v = (cat[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    return (cat['name_en'] ?? '').toString();
  }

  /// Localized category name for a product: prefers its category_slug (CMS),
  /// falls back to the legacy free-text category.
  String categoryLabel(Map<String, dynamic> product) {
    final slug = (product['category_slug'] ?? '').toString();
    if (slug.isNotEmpty) {
      for (final cat in categories) {
        if ((cat['slug'] ?? '').toString() == slug) {
          return localizedCategoryName(cat);
        }
      }
    }
    // Legacy free-text fallback. Runs through localizedTag so a value like
    // 'beauty_care' reaches the user as a translated label — or at worst as
    // "Beauty care" — instead of raw snake_case. Products predating the CMS
    // categories have no category_slug, so this path is the common one today.
    return localizedTag(product['category']);
  }
}
