// Pins that each list's search asks the SERVER, and that the one list which
// filters locally is the one that genuinely holds everything.
//
// WHY THIS FILE EXISTS (J8)
// The client asked for search "in the main menu, all sub-sections, and every
// page holding data or lists". The app had one global box in the top bar and,
// across 44 list-bearing screens, exactly one list with a search of its own.
//
// WHY THE URL IS WHAT IS ASSERTED, AND NOT "THE LIST GOT SHORTER"
// A text box over `items.where(...)` makes the list get shorter too, and looks
// identical on screen — while searching only the rows that happen to be
// loaded. Partners, media and the City Guide are capped at 50 rows by the
// server (`clampLimit`, listings.go:506) and the marketplace loads 10 at a
// time, so a local filter on any of them answers "no such product" about a
// catalogue it has never seen. That is the defect found in K15, where product
// labels sorted 20 loaded rows while claiming to rank the whole catalogue.
//
// So the thing under test is that `q` reaches the request. Only the query
// string can tell the two implementations apart, and only the query string
// decides whether the answer is true.
//
// THE ONE EXCEPTION, AND WHY IT IS ALLOWED
// `donations.ListByUser` (donations.go:557-565) has no LIMIT and no paging —
// the donor's ENTIRE history is already in memory. Filtering that locally
// searches everything there is, so it is honest, and a round-trip per
// keystroke would buy nothing. That claim is pinned below too: if the endpoint
// ever grows a LIMIT, the local filter stops being true.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:flutter_application_1/core/widgets/app_list_search_field.dart';
import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';
import 'package:flutter_application_1/modules/donations/controllers/my_donations_controller.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';

import '../support/fake_http.dart';

/// A response body wide enough for every list under test: each controller
/// reads the key it cares about and ignores the rest.
const _anyList =
    '{"success": true, "items": [], "data": [], '
    '"summary": {}, "page": 1, "per_page": 10, "total_items": 0}';

/// Installs [overrides] before any controller is put — GetX runs `onInit`
/// synchronously, so a controller created first would fetch through the real
/// client.
void _installHttp(FakeHttpOverrides overrides) {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);
}

/// Stops the 5s poll [controller] started in `onInit`.
///
/// Must run INSIDE the test body: the pending-timer invariant is checked
/// before `tearDown`, so `Get.reset()` there is too late. MarketplaceController
/// and MyDonationsController both use RealtimePollingMixin.
Future<void> _stopPolling(
  RealtimePollingMixin controller,
  WidgetTester t,
) async {
  controller.stopPolling();
  await t.pump();
}

/// Every request whose path contains [pathFragment].
List<Uri> _requestsTo(FakeHttpOverrides overrides, String pathFragment) =>
    overrides.requestUrls
        .where((u) => u.path.contains(pathFragment))
        .toList(growable: false);

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({'id_user': '7'});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the search reaches the server, not just the loaded rows', () {
    testWidgets('partners — GET /api/partners carries q', (tester) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _anyList);
      _installHttp(overrides);
      final controller = Get.put(PartnersController());
      await tester.pumpAndSettle();

      await controller.setSearchQuery('crescent');
      await tester.pumpAndSettle();

      final hits = _requestsTo(overrides, '/api/partners');
      expect(hits, isNotEmpty, reason: 'the list never asked the server');
      expect(
        hits.last.queryParameters['q'],
        'crescent',
        reason:
            'without q this filters the 50 partners already loaded and calls '
            'that a search of the register',
      );
    });

    testWidgets('news & activities — GET /api/media carries q', (tester) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _anyList);
      _installHttp(overrides);
      final controller = Get.put(MediaPostsController());
      await tester.pumpAndSettle();

      await controller.setSearchQuery('winter');
      await tester.pumpAndSettle();

      final hits = _requestsTo(overrides, '/api/media');
      expect(hits, isNotEmpty);
      expect(hits.last.queryParameters['q'], 'winter');
    });

    testWidgets('city guide — GET /api/community carries q', (tester) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _anyList);
      _installHttp(overrides);
      final controller = Get.put(CommunityController());
      await tester.pumpAndSettle();

      await controller.setSearchQuery('hospital');
      await tester.pumpAndSettle();

      final hits = _requestsTo(overrides, '/api/community');
      expect(hits, isNotEmpty);
      expect(hits.last.queryParameters['q'], 'hospital');
    });

    testWidgets('marketplace — GET /api/marketplace carries q, from page 1', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _anyList);
      _installHttp(overrides);
      final controller = Get.put(MarketplaceController());
      await tester.pumpAndSettle();

      await controller.setProductSearch('honey');
      await tester.pumpAndSettle();

      final hits = _requestsTo(overrides, '/api/marketplace');
      expect(hits, isNotEmpty);
      expect(hits.last.queryParameters['q'], 'honey');
      expect(
        hits.last.queryParameters['page'],
        '1',
        reason:
            'searching from page 3 of the old results would return page 3 of '
            'the new ones and look like a catalogue with a hole in it',
      );
      await _stopPolling(controller, tester);
    });
  });

  group('my donations filters locally, because it holds everything', () {
    testWidgets('a query needs no second request', (tester) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body:
            '{"success": true, "summary": {}, "items": ['
            '{"campaign_name": "Winter Campaign", "amount": 50000, '
            '"reference": "#11", "status": "success"},'
            '{"campaign_name": "Ramadan Baskets", "amount": 25000, '
            '"reference": "#12", "status": "success"}]}',
      );
      _installHttp(overrides);
      final controller = Get.put(MyDonationsController());
      await tester.pumpAndSettle();

      final callsBefore = overrides.requestUrls.length;
      controller.setSearchQuery('ramadan');
      await tester.pumpAndSettle();

      expect(
        overrides.requestUrls.length,
        callsBefore,
        reason:
            'the whole history is already loaded (ListByUser has no LIMIT), '
            'so a round-trip per keystroke buys nothing',
      );
      expect(controller.visibleItems.length, 1);
      expect(controller.visibleItems.first.campaignName, 'Ramadan Baskets');
      await _stopPolling(controller, tester);
    });

    testWidgets('the match is case-insensitive and covers the reference', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body:
            '{"success": true, "summary": {}, "items": ['
            '{"campaign_name": "Winter Campaign", "amount": 50000, '
            '"reference": "#11", "status": "success"}]}',
      );
      _installHttp(overrides);
      final controller = Get.put(MyDonationsController());
      await tester.pumpAndSettle();

      controller.setSearchQuery('WINTER');
      await tester.pumpAndSettle();
      expect(controller.visibleItems.length, 1);

      // A donor looking for one donation has the reference, not the campaign
      // name — it is what the receipt and the confirmation notification say.
      controller.setSearchQuery('#11');
      await tester.pumpAndSettle();
      expect(controller.visibleItems.length, 1);

      controller.setSearchQuery('nothing like this');
      await tester.pumpAndSettle();
      expect(controller.visibleItems, isEmpty);
      await _stopPolling(controller, tester);
    });
  });

  group('an empty result under a query is not an empty section', () {
    testWidgets('each searchable list knows a search is active', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _anyList);
      _installHttp(overrides);
      final partners = Get.put(PartnersController());
      final media = Get.put(MediaPostsController());
      final community = Get.put(CommunityController());
      final market = Get.put(MarketplaceController());
      final donations = Get.put(MyDonationsController());
      await tester.pumpAndSettle();

      // "No partners are listed yet" is a claim about the organization's
      // register. Under a query the truth is only "nothing matched", and the
      // screens pick their copy from this flag.
      expect(partners.hasActiveSearch, isFalse);
      expect(media.hasActiveSearch, isFalse);
      expect(community.hasActiveSearch, isFalse);
      expect(market.hasActiveSearch, isFalse);
      expect(donations.hasActiveSearch, isFalse);

      await partners.setSearchQuery('zzz');
      await media.setSearchQuery('zzz');
      await community.setSearchQuery('zzz');
      await market.setProductSearch('zzz');
      donations.setSearchQuery('zzz');
      await tester.pumpAndSettle();

      expect(partners.hasActiveSearch, isTrue);
      expect(media.hasActiveSearch, isTrue);
      expect(community.hasActiveSearch, isTrue);
      expect(market.hasActiveSearch, isTrue);
      expect(donations.hasActiveSearch, isTrue);

      await _stopPolling(market, tester);
      await _stopPolling(donations, tester);
    });
  });

  group('the box actually reaches the user', () {
    // A SOURCE test, like partners_doors_test.dart, and for the same reason:
    // the property is "this screen offers a search at all", which is about the
    // codebase rather than about one widget tree. Every controller above can
    // be perfect and the client still finds no box if a screen forgets to
    // mount one — which is precisely the state J8 was reported in.
    test('every searchable list mounts the field', () {
      const screens = <String, String>{
        'lib/modules/proposal/screens/partners_screen.dart': 'الشركاء',
        'lib/modules/proposal/screens/news_activities_screen.dart':
            'الأخبار والأنشطة',
        // Shares MediaPostsController with the feed above, so it shares the
        // search term — which is exactly why it needs a box of its own rather
        // than inheriting an invisible filter.
        'lib/modules/proposal/screens/our_work_screen.dart': 'أعمالنا',
        'lib/modules/community/screens/community_services_section.dart':
            'دليل المدينة',
        'lib/modules/marketplace/screens/marketplace_section.dart': 'المتجر',
        'lib/modules/donations/screens/my_donations_page.dart': 'المساهمات',
      };

      final missing = <String>[];
      for (final entry in screens.entries) {
        final file = File(entry.key);
        if (!file.existsSync()) {
          fail('${entry.key} is missing — this test needs updating');
        }
        if (!file.readAsStringSync().contains('AppListSearchField(')) {
          missing.add('${entry.value} (${entry.key})');
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'these sections have a working server-side search behind them and '
            'no way for the user to type into it: ${missing.join(', ')}',
      );
    });
  });

  group('the search field itself', () {
    testWidgets('debounces, trims, and emits once per distinct query', (
      tester,
    ) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: AppListSearchField(
              onChanged: emitted.add,
              debounce: const Duration(milliseconds: 50),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ho');
      await tester.enterText(find.byType(TextField), 'hon');
      await tester.enterText(find.byType(TextField), 'honey  ');
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        emitted,
        ['honey'],
        reason:
            'one request per pause, not per keystroke, and trimmed so a '
            'trailing space is not a different search',
      );
    });

    testWidgets('offers a way to undo the filter', (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: AppListSearchField(
              onChanged: emitted.add,
              debounce: const Duration(milliseconds: 50),
            ),
          ),
        ),
      );

      expect(
        find.byIcon(Icons.close_rounded),
        findsNothing,
        reason: 'nothing to clear yet',
      );

      await tester.enterText(find.byType(TextField), 'honey');
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        emitted.last,
        '',
        reason:
            'a filter the user cannot see how to undo is how a list ends up '
            'looking permanently empty',
      );
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });
}
