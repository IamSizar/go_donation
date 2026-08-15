// Pins that the City Guide's 27 seeded sub-categories are reachable.
//
// WHY THIS FILE EXISTS (K16)
// The client's note names six City Guide sectors "each with the sub-categories
// listed in the PDF". Both halves were built server-side: the six sectors are
// seeded and were already reachable, and migration 101 seeded 27
// sub-categories under them, in all four languages, behind a public endpoint
// (`GET /api/city-categories`, wired in main.go:378, no auth).
//
// The app never asked for them. Grepping the Flutter tree for
// `city-categories` returned nothing — only `citySectors()` existed — so the
// data was seeded, served, and invisible. The client's own check ("tap into a
// sector: no sub-categories underneath. When you add a business, التصنيف is a
// typing box, not a list") describes exactly that.
//
// WHAT MATCHING MEANS HERE, AND WHY IT IS FUZZY
// Entries store a free-text `category` — live values include 'training',
// 'asdsa' and single Arabic letters — and migration 101 deliberately left that
// column alone so nothing was lost. So a curated sub-category has to match an
// entry by slug OR by any of its four names, and an entry nobody has retagged
// simply does not match. That is the honest answer: it is untagged, not
// mis-tagged, and the empty state already offers to clear the filter.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// One seeded row, in the shape GET /api/city-categories really answers with.
Map<String, dynamic> _category({
  required String slug,
  required String sector,
  String en = '',
  String ar = '',
}) => {
  'slug': slug,
  'sector_slug': sector,
  'name_en': en,
  'name_ar': ar,
  'name_ckb': '',
  'name_kmr': '',
};

void main() {
  group('the app asks the server for its sub-categories', () {
    test('the endpoint is wired', () {
      expect(
        _read('lib/api/links.dart').contains('city-categories'),
        isTrue,
        reason:
            'the route has existed and been public since migration 101; the '
            'app simply never called it',
      );
      expect(
        _read('lib/api/module_api.dart').contains('cityCategories'),
        isTrue,
      );
    });

    test('the add-a-place form no longer asks the user to type a category', () {
      final form = _read(
        'lib/modules/community/screens/add_activity_screen.dart',
      );
      expect(
        form.contains("_field(_category, 'activity_category'.tr"),
        isFalse,
        reason:
            'a typing box is how the column filled up with "asdsa" and single '
            'letters — the curated list is right there',
      );
      expect(
        form.contains('fetchCategories'),
        isTrue,
        reason: 'the form must load the catalogue it picks from',
      );
      expect(
        form.contains("'category': _categorySlug!"),
        isTrue,
        reason:
            'it has to submit the SLUG — a typed name is what the filter '
            'cannot match reliably across four languages',
      );
    });
  });

  group('sub-categories belong to the sector above them', () {
    late CommunityController controller;

    setUp(() {
      controller = CommunityController();
      controller.categories.assignAll([
        _category(slug: 'hospitals', sector: 'health', en: 'Hospitals'),
        _category(slug: 'pharmacies', sector: 'health', en: 'Pharmacies'),
        _category(slug: 'malls', sector: 'commercial', en: 'Malls'),
      ]);
    });

    test('only the selected sector\'s children are offered', () {
      controller.selectSector('health');
      expect(controller.categoriesForSelectedSector.map((c) => c['slug']), [
        'hospitals',
        'pharmacies',
      ]);
    });

    test('no sector selected means no sub-category row', () {
      // 27 chips with no parent is not a filter, it is a wall.
      controller.selectSector(null);
      expect(controller.categoriesForSelectedSector, isEmpty);
    });

    test('changing sector drops a sub-category from the old one', () {
      controller.selectSector('health');
      controller.selectCategory('hospitals');
      controller.selectSector('commercial');
      expect(
        controller.selectedCategory.value,
        isNull,
        reason:
            'leaving "Hospitals" selected under التجارة would filter the list '
            'to nothing and look like the guide was empty',
      );
    });
  });

  group('filtering entries by a sub-category', () {
    late CommunityController controller;

    setUp(() {
      controller = CommunityController();
      controller.categories.assignAll([
        _category(
          slug: 'pharmacies',
          sector: 'health',
          en: 'Pharmacies and medical supplies',
          ar: 'الصيدليات ومخازن المستلزمات الطبية',
        ),
      ]);
      controller.entries.assignAll([
        {
          'name': 'New Pharmacy',
          'category': 'pharmacies',
          'sectors': ['health'],
        },
        {
          'name': 'Old Pharmacy',
          'category': 'الصيدليات ومخازن المستلزمات الطبية',
          'sectors': ['health'],
        },
        {
          'name': 'Untagged Place',
          'category': 'asdsa',
          'sectors': ['health'],
        },
      ]);
      controller.selectSector('health');
    });

    test('an entry tagged with the slug matches', () {
      controller.selectCategory('pharmacies');
      expect(
        controller.filteredEntries.map((e) => e['name']),
        contains('New Pharmacy'),
      );
    });

    test('a legacy entry holding the localized NAME matches too', () {
      // Existing rows were typed by staff in Arabic before the curated list
      // existed. Matching only the slug would hide every one of them.
      controller.selectCategory('pharmacies');
      expect(
        controller.filteredEntries.map((e) => e['name']),
        contains('Old Pharmacy'),
      );
    });

    test('an entry with unrelated free text does not match', () {
      controller.selectCategory('pharmacies');
      expect(
        controller.filteredEntries.map((e) => e['name']),
        isNot(contains('Untagged Place')),
      );
    });

    test('clearing the sub-category restores the sector list', () {
      controller.selectCategory('pharmacies');
      controller.selectCategory(null);
      expect(controller.filteredEntries.length, 3);
    });
  });
}
