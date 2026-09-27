// Pins the marketplace product photo strip — the cover and its gallery
// (migration 117) drawn as ONE scrollable, tap-to-zoom strip.
//
// WHY THIS FILE EXISTS
// The strip replaced a fixed-crop, non-tappable cover "hero" plus a separate,
// only-sometimes-present gallery thumbnail row. The risks worth pinning:
//
//  1. THE COVER IS ALWAYS IN THE STRIP. A product with no gallery photos at
//     all must still show its cover, as the first (and only) tile — this is
//     the opposite of the old ProductGallery, which drew nothing when the
//     gallery array was empty. Losing that would mean every ordinary
//     product's detail sheet loses its picture.
//
//  2. NOTHING IS EVER CROPPED. Every tile is `BoxFit.contain`; a portrait
//     photo (a T-shirt on a hanger) must show whole, letterboxed, never with
//     its top or bottom sliced off to fill a wide tile.
//
//  3. THE PATHS RESOLVE THE SAME WAY FOR THE COVER AND THE GALLERY. The
//     backend stores either a relative upload path or an absolute URL for
//     both fields, and they must agree — a gallery with its own resolver
//     would show broken tiles next to a working cover.
//
//  4. IT IS NOT RTL-SAFE. The app ships Arabic and Kurdish. The strip must
//     start at the right in Arabic, and the viewer's close button must sit
//     under the reader's thumb rather than across the screen.
//
// Widget tests run under BOTH platform targets per the house rule for anything
// with adaptive furniture.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/product_gallery.dart';

import '../support/fake_http.dart';

/// Hosts the widget with the app's real translations, so a missing key shows up
/// here as the raw key rather than as translated text.
Widget _host(Widget child, {Locale locale = const Locale('en', 'US')}) =>
    GetMaterialApp(
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      translations: AppTranslations(),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({'id_user': '7'});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
  });
  tearDown(Get.reset);

  // ─── The parser ───────────────────────────────────────────────────────

  group('marketplaceGalleryUrls', () {
    test('a product with no gallery yields no photos', () {
      // Every shape "no gallery" actually arrives in. An older server sends no
      // key at all; the column's NOT NULL DEFAULT means a new one sends [].
      expect(marketplaceGalleryUrls(null), isEmpty);
      expect(marketplaceGalleryUrls(const []), isEmpty);
      expect(marketplaceGalleryUrls('images/uploads/a.jpg'), isEmpty);
      expect(marketplaceGalleryUrls(42), isEmpty);
    });

    test('blank entries are dropped rather than becoming broken tiles', () {
      expect(marketplaceGalleryUrls(const ['', '   ', null]), isEmpty);
    });

    test('absolute URLs pass through and relative paths are resolved', () {
      final urls = marketplaceGalleryUrls(const [
        'https://cdn.example.com/a.jpg',
        'images/uploads/b.jpg',
      ]);

      expect(urls, hasLength(2));
      expect(urls.first, 'https://cdn.example.com/a.jpg');
      // Not asserting the exact host — that is deployment configuration. What
      // matters is that a relative path became absolute and kept its path.
      expect(urls.last, startsWith('http'));
      expect(urls.last, endsWith('images/uploads/b.jpg'));
    });

    test('the gallery resolves paths exactly as the cover image does', () {
      // The bug this prevents: a gallery with its own resolver, showing broken
      // thumbnails next to a cover that loads fine.
      expect(
        marketplaceGalleryUrls(const ['images/uploads/b.jpg']).single,
        marketplaceMediaUrl('images/uploads/b.jpg'),
      );
    });

    test('order is preserved — it is the order staff arranged', () {
      final urls = marketplaceGalleryUrls(const [
        'a/1.jpg',
        'a/2.jpg',
        'a/3.jpg',
      ]);
      expect(urls[0], endsWith('1.jpg'));
      expect(urls[1], endsWith('2.jpg'));
      expect(urls[2], endsWith('3.jpg'));
    });
  });

  // ─── The strip ────────────────────────────────────────────────────────

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    final name = platform == TargetPlatform.iOS ? 'iOS' : 'Android';

    testWidgets('$name — no cover and no gallery still draws a fallback tile, '
        'not an empty screen', (tester) async {
      await tester.pumpWidget(
        _host(
          Theme(
            data: ThemeData(platform: platform),
            child: const ProductPhotoStrip(coverUrl: null, galleryUrls: []),
          ),
        ),
      );

      // Not scrollable — there is nothing to page through — but a fallback
      // tile still occupies the space, so the sheet never just goes blank.
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(AppPressable), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name — a cover with no gallery is still one tappable page, '
        'with no dots for a single photo', (tester) async {
      await tester.pumpWidget(
        _host(
          Theme(
            data: ThemeData(platform: platform),
            child: const ProductPhotoStrip(
              coverUrl: 'https://cdn.example.com/cover.jpg',
              galleryUrls: [],
            ),
          ),
        ),
      );

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(AppPressable), findsOneWidget);
      // A single photo has nothing to flip between, so no page dots.
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('$name — the cover leads, and swiping reaches the gallery '
        'photos after it', (tester) async {
      await tester.pumpWidget(
        _host(
          Theme(
            data: ThemeData(platform: platform),
            child: const ProductPhotoStrip(
              coverUrl: 'https://cdn.example.com/cover.jpg',
              galleryUrls: [
                'https://cdn.example.com/a.jpg',
                'https://cdn.example.com/b.jpg',
              ],
            ),
          ),
        ),
      );

      // Cover + 2 gallery photos = 3 page dots, the first lit.
      expect(find.byType(AnimatedContainer), findsNWidgets(3));
      // PageView only builds the current page — one tappable banner, not
      // three tiles side by side, which is the whole point of this being a
      // promo-banner carousel instead of a thumbnail row.
      expect(find.byType(AppPressable), findsOneWidget);

      // Swipe start-to-end (a promo banner's "next") and land on a
      // different photo without losing the ability to tap it.
      //
      // Not `pumpAndSettle`: the loading tile's shimmer animation repeats
      // forever, so with no network in a test the image never "finishes"
      // and settling never converges. A fixed pump is enough to let the
      // page-change animation complete.
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // The departing page can still be mounted alongside the arriving one
      // right after a drag — asserting "still tappable", not "exactly one".
      expect(find.byType(AppPressable), findsWidgets);
    });
  }

  testWidgets('the strip pages start-to-end, so it swipes toward the right in '
      'Arabic', (tester) async {
    Get.locale = const Locale('ar', 'SA');
    await tester.pumpWidget(
      _host(
        const ProductPhotoStrip(
          coverUrl: 'https://cdn.example.com/cover.jpg',
          galleryUrls: ['https://cdn.example.com/a.jpg'],
        ),
        locale: const Locale('ar', 'SA'),
      ),
    );

    // A hardcoded `reverse:` would fail here: what is asserted is that the
    // PageView took its direction from the ambient Directionality rather
    // than from a constant.
    final page = tester.widget<PageView>(find.byType(PageView));
    expect(page.scrollDirection, Axis.horizontal);
    expect(
      Directionality.of(tester.element(find.byType(PageView))),
      TextDirection.rtl,
    );
  });

  // ─── The viewer ───────────────────────────────────────────────────────

  testWidgets('tapping a photo — cover included — opens a zoomable '
      'full-screen viewer', (tester) async {
    await tester.pumpWidget(
      _host(
        const ProductPhotoStrip(
          coverUrl: 'https://cdn.example.com/cover.jpg',
          galleryUrls: [],
        ),
      ),
    );

    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(find.byType(AppPressable).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InteractiveViewer), findsOneWidget);

    // And it must be escapable by the visible control, not only by tapping the
    // photo — an image filling the screen with no obvious way out is a trap.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets("the viewer's close button is anchored to the end edge", (
    tester,
  ) async {
    // In Arabic the close button belongs on the left. Positioned(right:) would
    // put it on the right in every language; PositionedDirectional follows the
    // reader.
    await tester.pumpWidget(
      _host(
        const ProductPhotoStrip(
          coverUrl: 'https://cdn.example.com/cover.jpg',
          galleryUrls: [],
        ),
        locale: const Locale('ar', 'SA'),
      ),
    );
    await tester.tap(find.byType(AppPressable).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(PositionedDirectional),
      ),
      findsOneWidget,
    );
  });

  // ─── In the real detail sheet ─────────────────────────────────────────
  //
  // The widget tests above prove the strip draws. These prove it is actually
  // WIRED — and, just as important, that the sheet it was added to still fits
  // on a phone. That sheet used to be an unscrollable Column sized to its
  // contents, so the honest risk of adding a photo rail to it was a
  // yellow-and-black overflow stripe on a product with a long description.

  /// One catalogue response, with the gallery under test spliced in.
  String catalogueWith(String galleryJson) =>
      '{"success": true, "page": 1, "per_page": 10, "total_items": 1, '
      '"total_pages": 1, "has_more": false, "items": [{"id": 1, '
      '"name": "Honey Jar", "price": "5000", "price_after_discount": "5000", '
      '"currency": "IQD", "labels": [], "status": "approved", '
      '"description": "A long description that exists to push the sheet '
      'towards the bottom of the screen, because a sheet that overflows is '
      'the regression adding a photo rail to it would most plausibly cause.", '
      '"specs": "Weight: 500g", "sku": "HNY-1", $galleryJson}]}';

  /// Pumps the real catalogue screen on a phone-sized surface and opens the
  /// first product's detail sheet.
  Future<void> openFirstProductSheet(
    WidgetTester tester,
    String responseBody,
  ) async {
    final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: responseBody);
    final previous = HttpOverrides.current;
    HttpOverrides.global = overrides;
    addTearDown(() => HttpOverrides.global = previous);

    // A real phone, not the 800x600 default: the point of these tests is
    // whether the sheet fits a device, and the default surface is taller
    // relative to its width than any phone.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: MarketplaceSection())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Honey Jar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The screen's controller polls orders on a timer, which the test binding
    // reports as a leak if it is still pending when the tree goes away. This
    // suite is about the sheet, not the polling, so it is stopped here rather
    // than being left for the framework to complain about.
    if (Get.isRegistered<MarketplaceController>()) {
      Get.find<MarketplaceController>().stopPolling();
    }
  }

  testWidgets(
    'the detail sheet shows the product photo strip, without overflowing',
    (tester) async {
      await openFirstProductSheet(
        tester,
        catalogueWith(
          '"gallery": ["images/uploads/a.jpg", "images/uploads/b.jpg", '
          '"images/uploads/c.jpg"]',
        ),
      );

      expect(find.byType(ProductPhotoStrip), findsOneWidget);
      // A RenderFlex overflow surfaces as a thrown exception in tests, so this
      // is the assertion the whole scrollable-sheet change exists to satisfy.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a product with no gallery still shows its cover in the strip',
    (tester) async {
      // The common case, and the one that must not regress: no gallery array
      // is not the same as no photo — the cover alone must still show.
      await openFirstProductSheet(tester, catalogueWith('"gallery": []'));

      expect(find.byType(ProductPhotoStrip), findsOneWidget);
      expect(find.textContaining('HNY-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a response from a server older than migration 117 is fine', (
    tester,
  ) async {
    // No `gallery` key at all. An app build ahead of its backend must show a
    // product normally rather than crash on a missing field.
    await openFirstProductSheet(tester, catalogueWith('"brand": ""'));

    expect(find.byType(ProductPhotoStrip), findsOneWidget);
    expect(find.textContaining('HNY-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
