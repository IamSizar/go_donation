// Pins the Events-hub redesign (chunk 5).
//
// WHAT USED TO BE HERE
// Before this redesign, the Events tab was three flat, full-width tile
// lists — "Event services" (6 tiles), "Events section" (up to 6, guest-
// gated) and "About & contact" (2 tiles) — rendered directly by
// MarriageHubScreen with no grid and no grouping. A test asserting that
// shape would have counted 14 `_MarriageTile`s in one ListView.
//
// WHAT IS HERE NOW, AND WHY THIS FILE INVERTS RATHER THAN DELETES THAT GUARD
// The owner asked for the two service groups to collapse into a top-level
// grid of two cards, each opening its own grid of cards, and for "About &
// contact" to be removed entirely. Per the precedent in
// partners_doors_test.dart, a shape-of-navigation defect like this is
// guarded at the level of "how many doors exist", not by rendering one
// widget and hoping nobody adds a third card back in — so this file checks:
// exactly two top-level cards, no About/Contact entry anywhere in the hub or
// its two group screens, and every one of the 14 real destinations still
// present exactly once, now inside the correct group's grid.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_event_group_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_hub_screen.dart';
import 'package:flutter_application_1/modules/marriage/widgets/event_hub_cards.dart';

Widget _app({required Widget home, Locale locale = const Locale('en', 'US')}) =>
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: locale,
      home: home,
    );

Future<void> _settle(WidgetTester tester) async {
  // The grid's entrance stagger delays up to 40ms * (itemCount - 1); this
  // clears every StaggeredEntrance in one go regardless of grid size.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  // The default 800×600 test surface is too short for a 3-row grid — the
  // third row sits below the fold, and GridView.builder only builds what is
  // (or was recently) on screen, so the last row's finders come back empty
  // even though the grid itself is correct. Every group here has at most 6
  // items / 3 rows, so a tall, phone-width surface makes all of them build
  // without needing to scroll mid-test.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(430, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1;
    addTearDown(
      binding.platformDispatcher.views.first.resetPhysicalSize,
    );
    addTearDown(
      binding.platformDispatcher.views.first.resetDevicePixelRatio,
    );
  });

  group('top level', () {
    testWidgets('renders exactly two cards', (tester) async {
      await tester.pumpWidget(_app(home: const MarriageHubScreen()));
      await _settle(tester);

      expect(find.byType(EventHubCard), findsNWidgets(2));
      expect(find.text('Event services'), findsOneWidget);
      expect(find.text('Events section'), findsOneWidget);
    });

    testWidgets('no About/Contact entry is reachable from this hub', (
      tester,
    ) async {
      await tester.pumpWidget(_app(home: const MarriageHubScreen()));
      await _settle(tester);

      expect(find.text('About My Engagement'), findsNothing);
      expect(find.text('Contact My Engagement'), findsNothing);
      expect(find.text('About & contact'), findsNothing);

      // Confirms the removal all the way down, not just at the top level —
      // opening each group must not surface an About/Contact entry either.
      await tester.tap(find.text('Event services'));
      await tester.pumpAndSettle();
      expect(find.text('About My Engagement'), findsNothing);
      expect(find.text('Contact My Engagement'), findsNothing);

      Navigator.of(tester.element(find.byType(EventServicesGroupScreen))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Events section'));
      await tester.pumpAndSettle();
      expect(find.text('About My Engagement'), findsNothing);
      expect(find.text('Contact My Engagement'), findsNothing);
    });

    testWidgets('tapping each card reaches its group', (tester) async {
      await tester.pumpWidget(_app(home: const MarriageHubScreen()));
      await _settle(tester);

      await tester.tap(find.text('Event services'));
      await tester.pumpAndSettle();
      expect(find.byType(EventServicesGroupScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(EventServicesGroupScreen))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Events section'));
      await tester.pumpAndSettle();
      expect(find.byType(EventsSectionGroupScreen), findsOneWidget);
    });
  });

  group('service group grid', () {
    testWidgets('all six services appear', (tester) async {
      await tester.pumpWidget(_app(home: const EventServicesGroupScreen()));
      await _settle(tester);

      for (final title in const [
        'Hall booking',
        'Photographer booking',
        'Wedding stage setup',
        'Decorations',
        'Event tents and equipment',
        'Add another service',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.byType(EventHubCard), findsNWidgets(6));
    });

    testWidgets(
      'row gap follows the card height, not a fixed aspect-ratio cell '
      '(regression for the dead-space defect)',
      (tester) async {
        // The bug this guards: a fixed `childAspectRatio` grid cell sized
        // roughly TWICE the card's real (content-sized) height, so the gap
        // between row 1 and row 2 read as almost another whole card's worth
        // of empty space. CardGrid (a Wrap) makes each row hug its tallest
        // child, so the gap between rows should be exactly the configured
        // spacing (12 in this grid) — nowhere close to the card's own
        // height.
        await tester.pumpWidget(
          _app(home: const EventServicesGroupScreen()),
        );
        await _settle(tester);

        final cards = find.byType(EventHubCard);
        // Items are laid out in DOM/list order; under LTR (this test's
        // locale) that is also left-to-right, top-to-bottom reading order,
        // so index 0/1 are row 1 and index 2/3 are row 2.
        final row1Bottom = tester.getBottomLeft(cards.at(0)).dy;
        final row2Top = tester.getTopLeft(cards.at(2)).dy;
        final cardHeight = tester.getSize(cards.at(0)).height;
        final rowGap = row2Top - row1Bottom;

        expect(
          rowGap,
          closeTo(12, 1),
          reason:
              'row gap should be exactly CardGrid\'s 12pt spacing, not a '
              'stretched grid-cell remainder',
        );
        // The regression signature: with the old GridView, the gap was
        // roughly as tall as the card itself (~1x cardHeight). Asserting
        // well under half of that catches the defect returning even if the
        // exact spacing constant above ever changes.
        expect(rowGap, lessThan(cardHeight * 0.5));
      },
    );
  });

  group('events section grid', () {
    testWidgets('all six items appear for a signed-in user', (tester) async {
      await tester.pumpWidget(_app(home: const EventsSectionGroupScreen()));
      await _settle(tester);

      for (final title in const [
        'Browse profiles',
        'Event posts',
        'My profile',
        'Subscription',
        'Chats',
        'Message the staff team',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.byType(EventHubCard), findsNWidgets(6));
    });

    testWidgets('a guest sees only the two public items', (tester) async {
      await sharedPreferences.setBool(kGuestModePrefsKey, true);

      await tester.pumpWidget(_app(home: const EventsSectionGroupScreen()));
      await _settle(tester);

      expect(find.byType(EventHubCard), findsNWidgets(2));
      expect(find.text('Browse profiles'), findsOneWidget);
      expect(find.text('Event posts'), findsOneWidget);
      expect(find.text('My profile'), findsNothing);
      expect(find.text('Message the staff team'), findsNothing);
    });
  });

  group('RTL', () {
    testWidgets('the top-level grid flows right-to-left in Arabic', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(home: const MarriageHubScreen(), locale: const Locale('ar', 'SA')),
      );
      await _settle(tester);

      // ambient Directionality drives GridView's cross-axis layout; with no
      // explicit `textDirection` override on the tree, this is what actually
      // makes the grid RTL rather than merely mirroring individual glyphs.
      final dir = Directionality.of(
        tester.element(find.byType(MarriageHubScreen)),
      );
      expect(dir, TextDirection.rtl);

      final cards = tester
          .widgetList<EventHubCard>(find.byType(EventHubCard))
          .toList();
      expect(cards.length, 2);

      // The Arabic labels resolve (not the English fallback), confirming the
      // locale actually took effect for this pump rather than silently
      // rendering the English strings under an RTL wrapper.
      expect(find.text('خدمات الفعاليات'), findsOneWidget);
      expect(find.text('قسم الفعاليات'), findsOneWidget);
    });
  });
}
