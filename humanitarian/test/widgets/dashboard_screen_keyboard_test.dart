// Pins the ACTUAL regression for the reported "tap search, keyboard opens, a
// blank box covers everything" defect — see task-4-brief.md /
// task-4-report.md.
//
// WHY THIS FILE EXISTS, ON TOP OF marketplace_embedded_keyboard_test.dart
// That file pumps the real `KeyboardSafeTabBody` (the extracted fix) wrapping
// a real `MarketplaceSection`, and is worth keeping — it pins the wrapper's
// own behaviour (field stays above the keyboard, results list stays
// scrollable, rendered height stays sane). But it CANNOT catch the actual
// regression this task fixed, and says so in its own header: a widget's own
// `build(context)` is always a genuine descendant of whatever Scaffold
// contains it, so `KeyboardSafeTabBody`'s internal `Builder` is inert once
// it is its own widget class — reverting it changes nothing observable.
//
// The original bug was never about what `KeyboardSafeTabBody` does. It was
// about WHICH context `_DashboardScreenState.build` handed to
// `MediaQuery.removePadding`: its own `context`, which sits ABOVE the
// Scaffold that same method builds, rather than a context from inside that
// Scaffold's body. Only `dashboard_screen.dart` can get that wrong, so only
// a test that pumps the real `DashboardScreen` can catch it. That is what
// this file does — no stand-in, no source-text pattern match, the actual
// widget tree the app ships.
//
// HARNESS NOTES (borrowed from existing suites rather than invented fresh):
//   * `withHttp` (test/support/fake_http.dart) fakes every HTTP request for
//     the duration of the callback — see test/api/guest_entry_test.dart.
//   * The `flutter_secure_storage` platform channel has no VM implementation
//     and throws unmocked; mocked the same way guest_entry_test.dart does.
//   * Guest mode is used throughout: it swaps Home for `GuestHomeSection`
//     (no controller of its own) and skips `RoleDashboardController`'s
//     auth-gated summary fetch, keeping the fixture to "does this layout
//     hold up", not "does every tab's real data plumbing work".
//   * `pumpAndSettle` is never used here: `FeaturedCampaignsController` and
//     `RoleDashboardController` poll every 5s for as long as they're
//     mounted, so nothing here ever truly settles. Fixed-duration `pump`s
//     are used instead, and every timer-owning controller is stopped or
//     deleted before the test ends — the same discipline
//     in_list_search_test.dart's `_stopPolling` helper documents.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/dashboard/screens/dashboard_screen.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';

import '../support/fake_http.dart';

const _productsList =
    '{"success": true, "items": [{"id": 1, "name": "Honey Jar", '
    '"price": 5000}], "data": [], "summary": {}, "page": 1, '
    '"per_page": 10, "total_items": 1}';

/// See test/api/guest_entry_test.dart — the session token write goes through
/// this platform channel, which has no VM implementation and throws unmocked.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Cancels every polling timer DashboardScreen's tabs may have started, so
/// the test binding's "no pending timers" invariant holds at teardown.
/// FeaturedCampaignsController and RoleDashboardController are put
/// unconditionally by DashboardScreen.initState; MarketplaceController is
/// put lazily by the Store tab once it is built (IndexedStack builds every
/// tab up front, so it always is here). NotificationsController and
/// ChatController run their own `Timer.periodic` outside
/// RealtimePollingMixin, cancelled by `onClose` — deleting them from Get is
/// simpler and more robust here than reaching into their private timers.
void _stopAllDashboardPolling() {
  Get.find<FeaturedCampaignsController>().stopPolling();
  Get.find<RoleDashboardController>().stopPolling();
  if (Get.isRegistered<MarketplaceController>()) {
    Get.find<MarketplaceController>().stopPolling();
  }
  if (Get.isRegistered<NotificationsController>()) {
    Get.delete<NotificationsController>(force: true);
  }
  if (Get.isRegistered<ChatController>()) {
    Get.delete<ChatController>(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
    SharedPreferences.setMockInitialValues({
      'id_user': '7',
      // Guest mode: swaps Home for the controller-free GuestHomeSection and
      // skips the auth-gated summary fetch — see the file header.
      kGuestModePrefsKey: true,
    });
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    Get.reset();
  });

  testWidgets(
    'the real DashboardScreen keeps the Store tab laid out under a keyboard '
    'inset',
    (tester) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _productsList,
      );

      // A real device size, not the default 800x600 test surface — a small
      // surface leaves too little headroom to tell "correctly shrunk once
      // for a real keyboard" apart from "double-shrunk by the bug".
      tester.view.physicalSize = const Size(1170, 2532); // iPhone-sized, @3x
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await withHttp(overrides, () async {
        await tester.pumpWidget(
          const GetMaterialApp(home: DashboardScreen()),
        );
        // Not pumpAndSettle: FeaturedCampaignsController and
        // RoleDashboardController poll every 5s for as long as they're
        // mounted, so this tree never settles.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);

        // Switch from Home to the Store tab, the way _onTabSelected does.
        dashboardTabNotifier.value = 1;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.text('Honey Jar'), findsOneWidget);

        // Focus the search field and simulate the on-screen keyboard
        // opening.
        await tester.tap(find.byType(TextField).first);
        const keyboardHeightLogical = 300.0;
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardHeightLogical * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        // THE ASSERTION THAT ACTUALLY PINS THE FIX. The bug's signature: the
        // Store tab's own body collapsed to roughly
        // (available height − 2×keyboard height) instead of one keyboard
        // height, because the outer dashboard Scaffold's `context` leaked
        // the raw keyboard inset into the tab, whose own nested Scaffold
        // then subtracted it a second time. Measured on this exact fixture:
        // ~432pt fixed, ~132pt reverted to the pre-fix pattern — asserting a
        // sane minimum catches the regression without pinning an exact
        // pixel value that would break on unrelated layout tweaks.
        final listView = tester.renderObject<RenderBox>(
          find.byKey(marketplaceResultsListKey),
        );
        expect(
          listView.size.height,
          greaterThan(250),
          reason:
              'the double keyboard-inset bug crushes the Store tab to a '
              'sliver the moment its keyboard opens, which read to the '
              'reporting user as a blank box covering the screen — see '
              'dashboard_screen.dart\'s KeyboardSafeTabBody usage',
        );

        _stopAllDashboardPolling();
        await tester.pump();
      });
    },
  );
}
