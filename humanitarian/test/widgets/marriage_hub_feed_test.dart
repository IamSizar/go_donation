// Pins that the Events hub shows its two cards and NOT the general news and
// activities feed.
//
// WHAT CHANGED
// The owner once asked for the admin panel's activity posts and news to render
// on this screen, below the "Event services" / "Events section" grid, and this
// file used to pin that feed: that it existed, that it sat under the grid, and
// that its cards were wired to the hub's tagged controller. The client later
// flagged the feed as a leak — it pulled the same humanitarian `media_posts`
// rows (`?type=activity,news`) as the general News & Activities screen into
// the Marriage section — so PR #76 (OPOS #25858) removed it entirely, and PR
// #77 (OPOS #25869) gave the general feed a door on the Profile screen
// instead, pinned in profile_menu_doors_test.dart. A marriage-specific staff
// news feed is separate work (OPOS #25862), not this general feed returning.
//
// WHAT THIS GUARDS
// That the general feed does not creep back onto the hub — neither drawn nor
// quietly fetched — and that the two cards, the hub's actual navigation, are
// still there after the feed around them was taken out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
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

/// Clears the grid's entrance stagger (40ms per item).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
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

  testWidgets('the hub carries no news and activities section', (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    // The removed section was a "News and activities" header with a "See all"
    // action over a column of post cards. None of the three may be drawn: the
    // posts are humanitarian work, and this is the Marriage section.
    expect(find.text('News and activities'), findsNothing);
    expect(find.text('See all'), findsNothing);
    expect(find.byType(MediaPostCard), findsNothing);
  });

  testWidgets('the hub does not fetch the general feed either', (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    // Drawing nothing is not enough on its own: a MediaPostsController calls
    // `GET /api/media` from onInit, so registering one here would bring the
    // feed back in everything but its rendering. An untagged one would also be
    // the very instance NewsActivitiesScreen reuses, since it looks one up
    // before creating its own. The hub's old tagged instance must be gone too.
    expect(Get.isRegistered<MediaPostsController>(), isFalse);
    expect(
      Get.isRegistered<MediaPostsController>(tag: 'events-hub-feed'),
      isFalse,
    );
  });

  testWidgets('both cards are still there', (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    // Removing the feed must not have cost the hub its navigation: the two
    // cards are the whole screen now.
    expect(find.byType(EventHubCard), findsNWidgets(2));
    expect(find.text('Event services'), findsOneWidget);
    expect(find.text('Events section'), findsOneWidget);
  });
}
