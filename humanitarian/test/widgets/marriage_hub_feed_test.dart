// Pins that the admin panel's activity posts and news render on the Events
// hub, underneath the two cards.
//
// THE REQUEST
// The owner asked for the posts published from the admin panel to appear on
// this screen, below the "Event services" / "Events section" grid. Before
// this, the hub was the grid and nothing else — a published activity post was
// only reachable from the separate News & Activities screen.
//
// WHAT THIS GUARDS THAT A UNIT TEST CANNOT
// media_posts_type_filter_test.dart pins the REQUEST (`?type=activity,news`).
// This file pins the PLACEMENT: that the feed section exists, that it sits
// after the grid rather than before it, and that a failed load leaves the two
// cards untouched — the feed is an addition to the hub, never a gate in front
// of the navigation that was already there. That last one is the real risk of
// wrapping a working screen in an async section, and it is exactly what the
// test surface reproduces, since no HTTP is served here and the fetch fails.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_hub_screen.dart';
import 'package:flutter_application_1/modules/marriage/widgets/event_hub_cards.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';

Widget _app({Locale locale = const Locale('en', 'US')}) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: locale,
  home: const MarriageHubScreen(),
);

/// Clears the grid's entrance stagger (40ms per item) and lets the feed's
/// in-flight fetch settle into its error state.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(430, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(binding.platformDispatcher.views.first.resetPhysicalSize);
    addTearDown(binding.platformDispatcher.views.first.resetDevicePixelRatio);
  });
  tearDown(Get.reset);

  testWidgets('the hub carries a news and activities section', (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    expect(find.byType(AppSectionHeader), findsOneWidget);
    // "See all" opens the full feed — this section is a preview of a capped
    // endpoint, so a post that falls off the end must stay reachable.
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('the feed sits below the two cards, not above them', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    final lastCardBottom = tester
        .getRect(find.byType(EventHubCard).last)
        .bottom;
    final headerTop = tester.getRect(find.byType(AppSectionHeader)).top;

    // greaterThanOrEqualTo, not greaterThan: AppSectionHeader carries its own
    // top padding INSIDE its box, so the box abuts the last card exactly while
    // the visible rule sits AppSpace.lg below it. The two orderings this
    // guards against — feed above the grid, or interleaved — both put the
    // header top far ABOVE the last card's bottom, so the weaker comparison
    // loses nothing.
    expect(
      headerTop,
      greaterThanOrEqualTo(lastCardBottom),
      reason: 'the posts must appear under the boxes, which is what was asked',
    );
  });

  testWidgets('a feed that fails to load still leaves both cards usable', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    // No HTTP is served in a widget test, so the feed is in its error state
    // here — the navigation must be completely unaffected by that.
    expect(find.byType(EventHubCard), findsNWidgets(2));
    expect(find.text('Event services'), findsOneWidget);
    expect(find.text('Events section'), findsOneWidget);
  });

  testWidgets('the hub feed does not become the general News feed', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    // The hub registers its type-filtered controller under a GetX tag. An
    // untagged lookup — what NewsActivitiesScreen does — must not resolve to
    // it, or the full News & Activities screen would silently inherit the
    // hub's narrower `activity,news` feed the moment a user visited Events
    // first. Registering the hub's instance untagged is the regression.
    expect(Get.isRegistered<MediaPostsController>(), isFalse);
    expect(
      Get.isRegistered<MediaPostsController>(tag: 'events-hub-feed'),
      isTrue,
    );

    // Closes the loop with media_posts_type_filter_test.dart, which pins what
    // the API does with this value: together they cover screen → controller →
    // wire. Without this line, dropping `postType:` at the call site would
    // turn the hub into the general feed with every test still green.
    expect(
      Get.find<MediaPostsController>(tag: 'events-hub-feed').postType,
      'activity,news',
    );
  });

  testWidgets('each card is wired to the hub feed, not the untagged one', (
    tester,
  ) async {
    // THE BUG THIS PINS
    // MediaPostCard's engagement bar used to resolve its controller with an
    // untagged Get.find. On this screen the feed is a TAGGED instance, so a
    // tap on Like/Save mutated the post map and then called posts.refresh()
    // on a DIFFERENT controller than the one this screen observes — the Obx
    // never rebuilt and both buttons looked completely dead, even though the
    // request had gone out. Seeding a post here (rather than relying on the
    // network, which a widget test has none of) is what makes a card exist to
    // check.
    final feed = Get.put(
      MediaPostsController(postType: 'activity,news'),
      tag: 'events-hub-feed',
    );

    await tester.pumpWidget(_app());
    // Seed AFTER the first load settles: onInit fires a fetch that has no
    // network here, and its failure path clears `posts` — seeding earlier
    // would be wiped before a card ever built.
    await _settle(tester);
    feed.posts.assignAll([
      {
        'id': 1,
        'title': 'Seeded post',
        'body': 'Body',
        'post_type': 'activity',
        'like_count': 0,
        'comment_count': 0,
        'share_count': 0,
        'liked_by_me': false,
        'saved_by_me': false,
      },
    ]);
    feed.errorMessage.value = null;
    await tester.pump();

    final card = tester.widget<MediaPostCard>(find.byType(MediaPostCard));
    expect(
      card.controller,
      same(feed),
      reason: 'an untagged lookup here makes like and save do nothing visible',
    );
  });
}
