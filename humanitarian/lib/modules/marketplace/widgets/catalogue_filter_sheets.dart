// K15 — the three product-list labels that open a picker rather than toggling:
// الفئات, العلامات التجارية and التصفية.
//
// Split out of catalogue_filter_bar.dart so neither file approaches the
// 500-line limit; the bar owns the row and the chip, this owns what a chip
// opens. Both send their result through `MarketplaceController
// .setCatalogueQuery`, which resets to page 1 and re-asks the SERVER — nothing
// in either file inspects `controller.products`.
//
// THE TWO FACETS CARRY FOUR STATES EACH. الفئات and العلامات التجارية are
// server lists, and a server list that answers a failure with an empty sheet
// tells the user "there are no brands" when the truth is "we could not ask".
// That is C2's finding on the City Guide's sector chips, and it applies here
// for the same reason: the row is something the user opened on purpose.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/models/catalogue_query.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/catalogue_filter_bar.dart';

/// Opens the sheet that any of the three chips shows.
Future<void> _open(BuildContext context, Widget Function() build) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => build(),
  );
}

// ─── الفئات ──────────────────────────────────────────────────────────────

/// The category picker. Sends `?category=<slug>`.
Future<void> openCategorySheet(
  BuildContext context,
  MarketplaceController controller,
) {
  return _open(
    context,
    () => CatalogueSheet(
      titleKey: 'catalogue_categories',
      child: Obx(
        () => CatalogueFacet(
          loading: controller.isLoadingCategories.value,
          error: controller.categoriesError.value,
          onRetry: controller.fetchCategories,
          rows: controller.categories,
          emptyTitleKey: 'catalogue_categories_empty',
          builder: (rows) => ListView(
            shrinkWrap: true,
            children: [
              // "All" is a real choice, not the absence of one: it is how a
              // user removes the filter without hunting for the row they
              // picked.
              CatalogueOptionTile(
                label: 'All'.tr,
                selected: controller.catalogueQuery.value.categorySlug.isEmpty,
                onTap: () => _apply(
                  context,
                  controller,
                  controller.catalogueQuery.value.copyWith(categorySlug: ''),
                ),
              ),
              for (final cat in rows)
                CatalogueOptionTile(
                  key: Key('catalogue_category_${cat['slug']}'),
                  label: controller.localizedCategoryName(cat),
                  selected:
                      controller.catalogueQuery.value.categorySlug ==
                      (cat['slug'] ?? '').toString(),
                  onTap: () => _apply(
                    context,
                    controller,
                    controller.catalogueQuery.value.copyWith(
                      categorySlug: (cat['slug'] ?? '').toString(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─── العلامات التجارية ───────────────────────────────────────────────────

/// The brand picker. Sends `?brand=<exact name>`.
///
/// The names come from GET /api/marketplace/brands, which counts APPROVED
/// products — so a chip reading "11" opens onto eleven rows. Deriving this
/// list from the loaded page instead would offer the brands of ten products
/// and count them wrong.
Future<void> openBrandSheet(
  BuildContext context,
  MarketplaceController controller,
) {
  return _open(
    context,
    () => CatalogueSheet(
      titleKey: 'catalogue_brands',
      child: Obx(
        () => CatalogueFacet(
          loading: controller.isLoadingBrands.value,
          error: controller.brandsError.value,
          onRetry: controller.fetchBrands,
          rows: controller.brands,
          emptyTitleKey: 'catalogue_brands_empty',
          builder: (rows) => ListView(
            shrinkWrap: true,
            children: [
              CatalogueOptionTile(
                label: 'All'.tr,
                selected: controller.catalogueQuery.value.brand.isEmpty,
                onTap: () => _apply(
                  context,
                  controller,
                  controller.catalogueQuery.value.copyWith(brand: ''),
                ),
              ),
              for (final row in rows)
                CatalogueOptionTile(
                  key: Key('catalogue_brand_${row['brand']}'),
                  // A brand is a proper noun in the seller's own spelling, so
                  // it is printed as stored — a data value, not UI copy.
                  label: (row['brand'] ?? '').toString(),
                  count: int.tryParse((row['product_count'] ?? '').toString()),
                  selected:
                      controller.catalogueQuery.value.brand ==
                      (row['brand'] ?? '').toString(),
                  onTap: () => _apply(
                    context,
                    controller,
                    controller.catalogueQuery.value.copyWith(
                      brand: (row['brand'] ?? '').toString(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Applies one picked option and closes the sheet.
Future<void> _apply(
  BuildContext context,
  MarketplaceController controller,
  CatalogueQuery next,
) async {
  AppHaptics.selection();
  Navigator.of(context).pop();
  await controller.setCatalogueQuery(next);
}

// ─── التصفية ─────────────────────────────────────────────────────────────

/// Price range, availability and price ordering.
///
/// A stateful sheet with its own Apply button rather than live-updating chips:
/// a price range is only meaningful once both ends are typed, and re-fetching
/// on every keystroke would fire a request for `min_price=1`, `min_price=15`,
/// `min_price=150`… and briefly show the shopper a result set nobody asked for.
Future<void> openRefineSheet(
  BuildContext context,
  MarketplaceController controller,
) {
  return _open(context, () => _RefineSheet(controller: controller));
}

class _RefineSheet extends StatefulWidget {
  const _RefineSheet({required this.controller});

  final MarketplaceController controller;

  @override
  State<_RefineSheet> createState() => _RefineSheetState();
}

class _RefineSheetState extends State<_RefineSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _min;
  late final TextEditingController _max;
  late bool _inStockOnly;
  late String _sort;

  @override
  void initState() {
    super.initState();
    final query = widget.controller.catalogueQuery.value;
    _min = TextEditingController(text: _text(query.minPrice));
    _max = TextEditingController(text: _text(query.maxPrice));
    _inStockOnly = query.inStockOnly;
    _sort = query.sort;
  }

  static String _text(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? '${value.round()}' : '$value';
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  // ─── Validation ───────────────────────────────────────────────────────

  /// Empty is valid and means "no bound" — the same thing the server does with
  /// a 0 or an unparseable value. Anything else must be a non-negative number,
  /// because a price filter that silently ignores what was typed is a filter
  /// the user cannot trust.
  String? _validatePrice(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value < 0) return 'catalogue_price_invalid'.tr;
    return null;
  }

  /// Cross-field rule: an inverted range matches nothing at all, and an empty
  /// result the user cannot explain is worse than a rejected form.
  String? _rangeError() {
    final min = double.tryParse(_min.text.trim());
    final max = double.tryParse(_max.text.trim());
    if (min == null || max == null) return null;
    if (max < min) return 'catalogue_price_range_invalid'.tr;
    return null;
  }

  Future<void> _apply() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppHaptics.error();
      return;
    }
    if (_rangeError() != null) {
      AppHaptics.error();
      setState(() {}); // surfaces the range message under the fields
      return;
    }
    AppHaptics.selection();
    final base = widget.controller.catalogueQuery.value;
    final next = base.copyWith(
      sort: _sort,
      inStockOnly: _inStockOnly,
      // clearPrices lets an emptied field mean "no bound" again; without it
      // copyWith's null would read as "leave the old bound alone" and the
      // range could never be removed.
      clearPrices: true,
      minPrice: double.tryParse(_min.text.trim()),
      maxPrice: double.tryParse(_max.text.trim()),
    );
    Navigator.of(context).pop();
    await widget.controller.setCatalogueQuery(next);
  }

  // ─── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rangeError = _rangeError();
    return CatalogueSheet(
      titleKey: 'catalogue_filters',
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Row(
              children: [
                Expanded(child: _priceField(_min, 'catalogue_price_min')),
                const SizedBox(width: 10),
                Expanded(child: _priceField(_max, 'catalogue_price_max')),
              ],
            ),
            if (rangeError != null) ...[
              const SizedBox(height: 6),
              Text(
                rangeError,
                style: TextStyle(
                  color: AppThemeConfig.consequence(context),
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              key: const Key('catalogue_in_stock_only'),
              contentPadding: EdgeInsets.zero,
              value: _inStockOnly,
              onChanged: (v) {
                AppHaptics.selection();
                setState(() => _inStockOnly = v);
              },
              title: Text('catalogue_in_stock_only'.tr),
              subtitle: Text(
                'catalogue_in_stock_only_desc'.tr,
                style: TextStyle(color: AppThemeConfig.mutedText(context)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'catalogue_sort_label'.tr,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            // EVERY sort, including the two the bar has chips for.
            //
            // The bar's chips are shortcuts to this same field, so listing all
            // five here cannot make the two disagree — but omitting the two
            // would: a shopper who tapped الأكثر مبيعاً and then opened التصفية
            // would find a "Sort" group with nothing selected, and picking any
            // row would silently drop a ranking they had chosen.
            //
            // Rendered as the same checked rows the other two sheets use
            // rather than as radios: RadioListTile's value/onChanged pair is
            // deprecated in this Flutter version, and the alternative would
            // have been an `ignore` comment for a control that has no need to
            // look different from its neighbours.
            for (final sort in CatalogueSort.all)
              CatalogueOptionTile(
                key: Key('catalogue_sort_${sort.isEmpty ? 'none' : sort}'),
                label: CatalogueSort.labelKey(sort).tr,
                selected: _sort == sort,
                onTap: () {
                  AppHaptics.selection();
                  setState(() => _sort = sort);
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('catalogue_refine_clear'),
                    onPressed: () {
                      AppHaptics.selection();
                      setState(() {
                        _min.clear();
                        _max.clear();
                        _inStockOnly = false;
                        _sort = CatalogueSort.none;
                      });
                    },
                    child: Text('catalogue_clear'.tr),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('catalogue_refine_apply'),
                    onPressed: _apply,
                    child: Text('catalogue_apply'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceField(TextEditingController controller, String labelKey) {
    return TextFormField(
      key: Key('catalogue_${labelKey}_field'),
      controller: controller,
      // A price is money, so the decimal pad — not the plain number pad, which
      // has no separator on iOS.
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: _validatePrice,
      decoration: InputDecoration(
        labelText: labelKey.tr,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
