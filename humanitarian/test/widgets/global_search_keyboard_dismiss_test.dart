// Pins rule 5.6 ("scrolling a list/form dismisses the keyboard on drag") on
// the app's file/content search screen — GlobalSearchScreen
// (lib/modules/search/screens/global_search_screen.dart).
//
// Tap-outside-to-dismiss is already covered app-wide by DismissKeyboardOnTap,
// wired once at GetMaterialApp's builder (see main.dart) — that isn't what
// this test pins. What was missing here specifically was the results
// ListView's own `keyboardDismissBehavior`, unlike every other search-backed
// list in the app (see AppListSearchField's header comment, and
// my_donations_page.dart / marketplace_section.dart for the same pattern
// applied elsewhere).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/search/screens/global_search_screen.dart';

import '../support/fake_http.dart';

const _searchResults =
    '{"success": true, "items": [{"type": "campaign", "id": 1, '
    '"name": "Winter Fuel"}]}';

void main() {
  setUp(() {
    Get.reset();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
  });
  tearDown(Get.reset);

  testWidgets(
    'the search results list dismisses the keyboard on drag',
    (tester) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _searchResults,
      );
      final previous = HttpOverrides.current;
      HttpOverrides.global = overrides;
      addTearDown(() => HttpOverrides.global = previous);

      await tester.pumpWidget(
        const GetMaterialApp(home: GlobalSearchScreen()),
      );
      await tester.pumpAndSettle();

      // Type a query so the results ListView is the one actually built,
      // not the pre-search AppEmpty state.
      await tester.enterText(find.byType(TextField), 'Winter');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(
        listView.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
        reason:
            'dragging the search results should put the keyboard away, '
            'matching every other search-backed list in the app',
      );
    },
  );
}
