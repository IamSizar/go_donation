// K15 — one product-catalogue request, as a value.
//
// WHY THIS TYPE EXISTS, AND WHY IT ONLY BUILDS QUERY PARAMETERS
// The client's product list names six functional labels — الأكثر مبيعاً,
// وصل حديثاً, العروض والخصومات, التصفية, الفئات, العلامات التجارية — and every
// one of them is a statement about the WHOLE catalogue. The app loads ten
// products at a time. So a chip implemented over `controller.products` would
// rank ten rows while claiming to rank the shop: "الأكثر مبيعاً" would name the
// best seller of one page. That is the exact defect commit b59c357 removed from
// the server, and re-adding it one layer up would undo the whole change.
//
// This class therefore has NO filtering method and NO sorting method. It turns
// a set of choices into `?sort=&category=&brand=&on_sale=…` and stops there.
// There is deliberately nothing here for a future caller to reach for when they
// want to "just sort what we already have" — the only thing it can do is ask
// the server.
//
// The parameter names are `marketplace.ProductFilters`' (handlers/
// marketplace.go:98 `catalogueFiltersFrom`), not invented here.
import 'package:flutter/foundation.dart';

/// The sort values the server understands.
///
/// Named after the label each one powers rather than after a column, matching
/// the Sort* constants in internal/marketplace/catalogue.go. An unrecognised
/// value falls back server-side to the catalogue's default order, so an app
/// sending something stale degrades rather than errors — but nothing here
/// should ever send one.
abstract final class CatalogueSort {
  /// The catalogue's own order (`id DESC`). Sent as no parameter at all.
  static const none = '';

  /// وصل حديثاً.
  static const newest = 'newest';

  /// الأكثر مبيعاً — SUM(quantity) over approved/processing/completed orders.
  /// A cancelled order is not a sale.
  static const bestSelling = 'best_selling';

  /// التصفية's two price orderings.
  static const priceAsc = 'price_asc';
  static const priceDesc = 'price_desc';

  /// Everything the app may send, for the picker and for tests.
  static const all = [none, newest, bestSelling, priceAsc, priceDesc];

  /// The translation key for one sort value.
  ///
  /// A `switch` rather than `'catalogue_sort_$value'.tr`: GetX answers a
  /// missing key with the key itself, so a value with no entry would render
  /// the literal `catalogue_sort_price_asc` on an Arabic screen.
  static String labelKey(String sort) => switch (sort) {
    newest => 'catalogue_sort_newest',
    bestSelling => 'catalogue_sort_best_selling',
    priceAsc => 'catalogue_sort_price_asc',
    priceDesc => 'catalogue_sort_price_desc',
    _ => 'catalogue_sort_default',
  };
}

/// One request for a page of the public catalogue.
///
/// Immutable, so a sheet can build a candidate query, show it, and only hand it
/// to the controller when the user applies it — without the list re-fetching on
/// every keystroke behind the sheet.
@immutable
class CatalogueQuery {
  const CatalogueQuery({
    this.sort = CatalogueSort.none,
    this.categorySlug = '',
    this.brand = '',
    this.onSale = false,
    this.inStockOnly = false,
    this.minPrice,
    this.maxPrice,
  });

  /// One of [CatalogueSort]'s values.
  final String sort;

  /// الفئات — `marketplace_categories.slug`, empty for "all".
  final String categorySlug;

  /// العلامات التجارية — an exact brand name from GET /api/marketplace/brands.
  /// The app never guesses one; it picks from that list.
  final String brand;

  /// العروض والخصومات. The server matches `discount_percent IS NOT NULL OR
  /// labels @> {sale}`, so products staff tagged before the discount column
  /// existed are included.
  final bool onSale;

  /// التصفية's availability switch. NULL stock means "not tracked" server-side
  /// and stays included — it never meant "none left".
  final bool inStockOnly;

  /// التصفية's price bounds. Null means "no bound"; the server treats 0 the
  /// same way, so a free product is never filtered out by an unset minimum.
  final double? minPrice;
  final double? maxPrice;

  /// Whether anything here narrows the catalogue.
  ///
  /// Drives the empty state's wording: "no products available" is a claim
  /// about the shop, and it is false when the shop is full and the filters are
  /// simply strict. Sorting is deliberately NOT narrowing — reordering the
  /// catalogue cannot empty it.
  bool get isNarrowed =>
      categorySlug.isNotEmpty ||
      brand.isNotEmpty ||
      onSale ||
      inStockOnly ||
      minPrice != null ||
      maxPrice != null;

  /// Whether the user has chosen anything at all, narrowing or ordering.
  bool get isActive => isNarrowed || sort != CatalogueSort.none;

  /// The `?…` parameters for GET /api/marketplace.
  ///
  /// Every default is omitted rather than sent as an empty value, so an
  /// untouched bar produces exactly the request this endpoint received before
  /// K15 — one page of the approved catalogue in its own order.
  Map<String, String> toQueryParameters() => {
    if (sort != CatalogueSort.none) 'sort': sort,
    if (categorySlug.isNotEmpty) 'category': categorySlug,
    if (brand.isNotEmpty) 'brand': brand,
    if (onSale) 'on_sale': '1',
    if (inStockOnly) 'in_stock': '1',
    // Trailing `.0` trimmed: the server parses a float either way, but a URL
    // reading `min_price=5000` is the one a person can check against the
    // dashboard.
    if (minPrice != null) 'min_price': _number(minPrice!),
    if (maxPrice != null) 'max_price': _number(maxPrice!),
  };

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  /// [clearSort] / [clearCategory] / [clearBrand] / [clearPrices] exist because
  /// `copyWith(brand: null)` cannot mean "remove the brand" when null is also
  /// "leave it alone".
  CatalogueQuery copyWith({
    String? sort,
    String? categorySlug,
    String? brand,
    bool? onSale,
    bool? inStockOnly,
    double? minPrice,
    double? maxPrice,
    bool clearPrices = false,
  }) {
    return CatalogueQuery(
      sort: sort ?? this.sort,
      categorySlug: categorySlug ?? this.categorySlug,
      brand: brand ?? this.brand,
      onSale: onSale ?? this.onSale,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      minPrice: clearPrices ? minPrice : (minPrice ?? this.minPrice),
      maxPrice: clearPrices ? maxPrice : (maxPrice ?? this.maxPrice),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogueQuery &&
      other.sort == sort &&
      other.categorySlug == categorySlug &&
      other.brand == brand &&
      other.onSale == onSale &&
      other.inStockOnly == inStockOnly &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice;

  @override
  int get hashCode => Object.hash(
    sort,
    categorySlug,
    brand,
    onSale,
    inStockOnly,
    minPrice,
    maxPrice,
  );

  @override
  String toString() => 'CatalogueQuery(${toQueryParameters()})';
}
