// Pins that the product list's six labels are answered by the SERVER (K15).
//
// WHY THIS FILE EXISTS
// The client's product-list spec names six functional labels — الأكثر مبيعاً,
// وصل حديثاً, العروض والخصومات, التصفية, الفئات, العلامات التجارية. Commit
// b59c357 refused to build them app-side and said why: `ListProducts(ctx, page,
// limit)` took no sort and no filter, so a chip could only ever re-order the
// rows already in hand — and products arrive TEN AT A TIME, so "الأكثر مبيعاً"
// would have named the best seller of one page while claiming to name the best
// seller of the shop.
//
// `Store.ListCatalogue` now answers all six in SQL over the whole table. The
// risk this file guards is therefore not "the chips do nothing" — it is the
// much quieter "the chips work locally", which looks correct on a small
// database and is wrong on a real one.
//
// SO THE ASSERTIONS ARE ABOUT TWO THINGS:
//   1. WHAT WAS ASKED. Every chip must appear in the query string, on page 1
//      AND on every load-more page after it — a page 2 that dropped `sort`
//      would append the default order under the best sellers.
//   2. WHAT WAS DONE WITH THE ANSWER. The rows must reach `products` in the
//      server's order, untouched. The fixtures below are deliberately in an
//      order no local sort would produce, so any `.sort()` added to the
//      controller fails here.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/models/catalogue_query.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/catalogue_filter_bar.dart';

import '../support/fake_http.dart';

/// Three products in an order NO client-side rule would produce: the prices
/// descend, the sold counts ascend, and the ids are shuffled. Whatever sort is
/// asked for, this is the order the server "chose" — so if the app reorders
/// anything, the assertion on ids catches it.
const _threeProducts =
    '{"success": true, "page": 1, "per_page": 10, "total_items": 3, '
    '"total_pages": 1, "has_more": false, "items": ['
    '{"id": 31, "name": "Kettle", "name_ar": "غلاية", "price": "90000", '
    '"price_after_discount": "90000", "sold_count": 1, "currency": "IQD", '
    '"labels": [], "status": "approved"},'
    '{"id": 12, "name": "Blanket", "name_ar": "بطانية", "price": "60000", '
    '"price_after_discount": "36000", "discount_percent": 40, '
    '"sold_count": 9, "currency": "IQD", "labels": ["sale"], '
    '"status": "approved"},'
    '{"id": 27, "name": "Lamp", "name_ar": "مصباح", "price": "20000", '
    '"price_after_discount": "20000", "sold_count": 44, "currency": "IQD", '
    '"labels": [], "status": "approved"}]}';

/// Exactly ten rows with `has_more: false` — the case the old
/// `rows.length == limit` guess got wrong.
String _tenProductsLastPage() {
  final items = List.generate(
    10,
    (i) =>
        '{"id": ${i + 1}, "name": "P$i", "price": "1000", '
        '"price_after_discount": "1000", "sold_count": 0, "currency": "IQD", '
        '"labels": [], "status": "approved"}',
  ).join(',');
  return '{"success": true, "page": 1, "per_page": 10, "total_items": 10, '
      '"total_pages": 1, "has_more": false, "items": [$items]}';
}

const _twoBrands =
    '{"success": true, "has_more": false, "total_items": 2, "items": ['
    '{"brand": "Nineveh Looms", "product_count": 11},'
    '{"brand": "Zagros", "product_count": 4}]}';

/// The query parameters of the nth request the fake saw.
Map<String, String> _paramsOf(FakeHttpOverrides overrides, int index) =>
    overrides.requestUrls[index].queryParameters;

Widget _host(Widget child) => GetMaterialApp(
  locale: const Locale('ar', 'SA'),
  fallbackLocale: const Locale('en', 'US'),
  translations: AppTranslations(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<MarketplaceController> _pumpBar(
  WidgetTester tester,
  FakeHttpOverrides overrides,
) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);

  // Not Get.put: onInit fires four loads and a poll timer, none of which this
  // suite is about. The bar takes its controller as a parameter.
  final controller = MarketplaceController();
  await tester.pumpWidget(_host(CatalogueFilterBar(controller: controller)));
  await tester.pump();
  return controller;
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('ar', 'SA');
    Get.fallbackLocale = const Locale('en', 'US');
  });
  tearDown(Get.reset);

  group('CatalogueQuery builds the server\'s parameters', () {
    test('an untouched query asks for exactly what it always asked for', () {
      // The whole catalogue, unfiltered. Sending `sort=` or `on_sale=0` would
      // be a different request than the one this endpoint used to receive.
      expect(const CatalogueQuery().toQueryParameters(), isEmpty);
      expect(const CatalogueQuery().isActive, isFalse);
      expect(const CatalogueQuery().isNarrowed, isFalse);
    });

    test('each label maps to the parameter the handler reads', () {
      const query = CatalogueQuery(
        sort: CatalogueSort.bestSelling,
        categorySlug: 'home-garden',
        brand: 'Nineveh Looms',
        onSale: true,
        inStockOnly: true,
        minPrice: 5000,
        maxPrice: 80000,
      );

      expect(query.toQueryParameters(), {
        'sort': 'best_selling',
        'category': 'home-garden',
        'brand': 'Nineveh Looms',
        'on_sale': '1',
        'in_stock': '1',
        'min_price': '5000',
        'max_price': '80000',
      });
    });

    test('sorting alone does not count as narrowing', () {
      // Drives the empty state: reordering a catalogue cannot empty it, so a
      // sort must never make the screen say "nothing matches these filters".
      const sorted = CatalogueQuery(sort: CatalogueSort.newest);
      expect(sorted.isNarrowed, isFalse);
      expect(sorted.isActive, isTrue);
    });

    test('an emptied price range really is removed', () {
      const withRange = CatalogueQuery(minPrice: 100, maxPrice: 900);
      final cleared = withRange.copyWith(clearPrices: true);
      expect(cleared.toQueryParameters().containsKey('min_price'), isFalse);
      expect(cleared.toQueryParameters().containsKey('max_price'), isFalse);
    });
  });

  group('the chips ask the server', () {
    testWidgets('الأكثر مبيعاً sends sort=best_selling from page 1', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _threeProducts,
      );
      await _pumpBar(tester, overrides);

      await tester.tap(find.byKey(const Key('catalogue_chip_best_selling')));
      await tester.pumpAndSettle();

      final params = _paramsOf(overrides, 0);
      expect(params['sort'], 'best_selling');
      expect(
        params['page'],
        '1',
        reason: 'page 3 of the old result set is not page 3 of the new one',
      );
    });

    testWidgets('العروض والخصومات sends on_sale, and untapping removes it', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _threeProducts,
      );
      await _pumpBar(tester, overrides);

      await tester.tap(find.byKey(const Key('catalogue_chip_on_sale')));
      await tester.pumpAndSettle();
      expect(_paramsOf(overrides, 0)['on_sale'], '1');

      await tester.tap(find.byKey(const Key('catalogue_chip_on_sale')));
      await tester.pumpAndSettle();
      expect(
        _paramsOf(overrides, 1).containsKey('on_sale'),
        isFalse,
        reason: 'a chip with no way back leaves the catalogue stuck filtered',
      );
    });

    testWidgets('tapping the lit sort chip turns it off', (tester) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _threeProducts,
      );
      final controller = await _pumpBar(tester, overrides);

      await tester.tap(find.byKey(const Key('catalogue_chip_newest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalogue_chip_newest')));
      await tester.pumpAndSettle();

      expect(controller.catalogueQuery.value.sort, CatalogueSort.none);
      expect(_paramsOf(overrides, 1).containsKey('sort'), isFalse);
    });
  });

  group('the ranking is the server\'s, and stays the server\'s', () {
    test('rows reach the list in the order they arrived', () async {
      // Prices descend and sold counts ascend in the fixture, so ANY local
      // sort would reorder these ids. This is the assertion that fails if
      // somebody "helpfully" sorts the loaded page.
      final controller = MarketplaceController();
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _threeProducts),
        () => controller.setCatalogueQuery(
          const CatalogueQuery(sort: CatalogueSort.bestSelling),
        ),
      );

      expect(controller.products.map((p) => p['id']).toList(), [31, 12, 27]);
    });

    test('load-more carries every filter to page 2', () async {
      // J8's lesson, one label over: a second page that dropped the filter
      // would append unfiltered products beneath the filtered ones, so the
      // list would claim a ranking it stops honouring at row eleven.
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        // has_more true so load-more is allowed to run.
        body: _threeProducts.replaceFirst(
          '"has_more": false',
          '"has_more": true',
        ),
      );
      final controller = MarketplaceController();
      await withHttp(overrides, () async {
        await controller.setCatalogueQuery(
          const CatalogueQuery(
            sort: CatalogueSort.bestSelling,
            categorySlug: 'home-garden',
            onSale: true,
          ),
        );
        await controller.loadMoreProducts();
      });

      final second = _paramsOf(overrides, 1);
      expect(second['page'], '2');
      expect(second['sort'], 'best_selling');
      expect(second['category'], 'home-garden');
      expect(second['on_sale'], '1');
    });

    test('a full page with has_more false does not promise another', () async {
      // The old rule was `rows.length == limit`, which is the same guess
      // b59c357 removed from the server — and a FILTERED catalogue lands on an
      // exact multiple of ten far more often than an unfiltered one.
      final controller = MarketplaceController();
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _tenProductsLastPage()),
        () => controller.fetchProducts(reset: true),
      );

      expect(controller.products.length, 10);
      expect(controller.hasMoreProducts.value, isFalse);
    });
  });

  group('the brand facet is the server\'s list, with four states', () {
    test('brands are loaded from the facet endpoint, not from the page', () async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _twoBrands);
      final controller = MarketplaceController();
      await withHttp(overrides, controller.fetchBrands);

      expect(overrides.requestUrls.single.path, '/api/marketplace/brands');
      expect(controller.brands.first['brand'], 'Nineveh Looms');
      expect(
        controller.brands.first['product_count'],
        11,
        reason: 'a chip promising eleven must open onto eleven, which only the '
            'server can count',
      );
      expect(controller.brandsError.value, isNull);
    });

    test('a failed facet is recorded, not swallowed into an empty list', () async {
      // C2's finding, applied to a filter the user opens on purpose: a failure
      // that renders as "there are no brands" is a lie with no retry attached.
      final controller = MarketplaceController();
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.networkError),
        controller.fetchBrands,
      );

      expect(controller.brandsError.value, isNotNull);
      expect(controller.brands, isEmpty);
      expect(controller.isLoadingBrands.value, isFalse);
    });

    test('the categories list gained the same signal', () async {
      // It used to end in `catch (_) { categories.clear(); }` — fine while it
      // only labelled cards, wrong once الفئات became a filter.
      final controller = MarketplaceController();
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.networkError),
        controller.fetchCategories,
      );

      expect(controller.categoriesError.value, isNotNull);
      expect(controller.isLoadingCategories.value, isFalse);
    });

    test('a successful empty facet is not an error', () async {
      final controller = MarketplaceController();
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: '{"success": true, "items": []}'),
        controller.fetchBrands,
      );

      expect(controller.brandsError.value, isNull);
      expect(controller.brands, isEmpty);
    });
  });

  group('the labels are readable on an Arabic screen', () {
    test('every chip and sort label resolves, with no Latin letters', () {
      Get.locale = const Locale('ar', 'SA');
      const keys = [
        'catalogue_sort_best_selling',
        'catalogue_sort_newest',
        'catalogue_sort_price_asc',
        'catalogue_sort_price_desc',
        'catalogue_sort_default',
        'catalogue_on_sale',
        'catalogue_categories',
        'catalogue_brands',
        'catalogue_filters',
        'catalogue_in_stock_only',
        'catalogue_price_min',
        'catalogue_price_max',
        'catalogue_no_results',
        'catalogue_no_results_desc',
        'catalogue_brands_failed',
        'catalogue_categories_failed',
      ];
      for (final key in keys) {
        final label = key.tr;
        expect(label, isNot(key), reason: '$key has no Arabic entry, so GetX '
            'hands the raw key back to the screen');
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '$key renders English on an Arabic screen: $label',
        );
      }
    });

    test('every sort value the app can send has a label', () {
      // Guards `CatalogueSort.labelKey`, whose default branch is the thing
      // standing between a new sort value and a raw token on screen.
      Get.locale = const Locale('en', 'US');
      for (final sort in CatalogueSort.all) {
        final key = CatalogueSort.labelKey(sort);
        expect(key.tr, isNot(key), reason: 'no entry for $key (sort "$sort")');
      }
    });
  });
}
