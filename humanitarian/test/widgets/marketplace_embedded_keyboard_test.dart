// Pins the fix for the reported "tap search, keyboard opens, a blank box
// covers everything" defect in the Store tab — see task-4-brief.md /
// task-4-report.md.
//
// ROOT CAUSE (found by reproducing the Store tab's exact embedding, not by
// guessing): dashboard_screen.dart wraps each tab's content in
// `MediaQuery.removePadding(context: context, ...)` using the outer
// `_DashboardScreenState.build(context)` parameter. That `context` sits
// ABOVE the Scaffold being built in this same method, so `MediaQuery.of` on
// it resolves to the app-root MediaQuery — where the keyboard's
// `viewInsets.bottom` was never stripped — rather than the Scaffold body's
// own MediaQuery, which its `resizeToAvoidBottomInset` (default true)
// already strips for real descendants. `removePadding` only touches
// padding, so it copied that raw, un-stripped keyboard inset straight
// through into every tab. The active tab's own nested Scaffold (every
// section keeps one, for reuse as a standalone pushed route) then
// subtracted the SAME keyboard height a second time from its own body,
// crushing the visible area to a sliver a few dozen points tall — on
// Marketplace, search field and product list included.
//
// This file proves the fix by mirroring dashboard_screen.dart's exact body
// shape (a fixed-height top bar, an Expanded tab section, a fixed-height nav
// bar, all inside one outer Scaffold) and asserting the product row is still
// laid out at a sane height once a keyboard-sized viewInsets.bottom appears.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';

import '../support/fake_http.dart';

const _productsList =
    '{"success": true, "items": [{"id": 1, "name": "Honey Jar", '
    '"price": 5000}], "data": [], "summary": {}, "page": 1, '
    '"per_page": 10, "total_items": 1}';

/// Mirrors dashboard_screen.dart's body Column exactly: a fixed-height top
/// bar, an Expanded tab section wrapped in the same
/// `Builder` + `MediaQuery.removePadding` pattern the fix uses, and a
/// fixed-height bottom nav bar — all inside ONE outer Scaffold, the way
/// `_DashboardScreenState.build` embeds every tab.
class _FakeDashboardShell extends StatelessWidget {
  const _FakeDashboardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 56), // stand-in DashboardTopBar
          Expanded(
            // Builder here is the fix: it reads MediaQuery from INSIDE this
            // Scaffold's body, where resizeToAvoidBottomInset has already
            // stripped viewInsets.bottom, instead of the outer `context`
            // (above the Scaffold), which still carries the raw keyboard
            // inset. See dashboard_screen.dart for the full account.
            child: Builder(
              builder: (innerContext) => MediaQuery.removePadding(
                context: innerContext,
                removeTop: true,
                removeBottom: true,
                child: child,
              ),
            ),
          ),
          const SizedBox(height: 118), // stand-in _CompactBottomNavBar
        ],
      ),
    );
  }
}

void main() {
  setUp(() async {
    Get.reset();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
    SharedPreferences.setMockInitialValues({'id_user': '7'});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  testWidgets(
    'the embedded Store tab keeps its results laid out under a keyboard inset',
    (tester) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _productsList,
      );
      final previous = HttpOverrides.current;
      HttpOverrides.global = overrides;
      addTearDown(() => HttpOverrides.global = previous);

      // A real device size, not the default 800x600 test surface — a small
      // surface leaves too little headroom to tell "correctly shrunk for a
      // real keyboard" apart from "double-shrunk by the bug".
      tester.view.physicalSize = const Size(1170, 2532); // iPhone-sized, @3x
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const GetMaterialApp(
          home: _FakeDashboardShell(child: MarketplaceSection()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Honey Jar'), findsOneWidget);

      // Focus the search field and simulate the on-screen keyboard opening.
      await tester.tap(find.byType(TextField));
      final keyboardHeight = 300 * tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // REQUIREMENT: results stay visible and scrollable while the keyboard
      // is open. skipOffstage: false — a row squeezed to zero height by a
      // double keyboard subtraction is technically still "in the tree", so
      // this alone would pass even on the bug; the geometry check below is
      // what actually pins the fix.
      expect(
        find.text('Honey Jar', skipOffstage: false),
        findsOneWidget,
        reason: 'the product row should still exist under the field',
      );

      // The bug's signature: the list's own body collapsed to roughly
      // (available height − 2×keyboard height) instead of one keyboard
      // height, because the keyboard inset was subtracted twice. Asserting
      // a sane minimum catches that without pinning an exact pixel value.
      final listView = tester.renderObject<RenderBox>(
        find.byType(ListView).first,
      );
      expect(
        listView.size.height,
        greaterThan(150),
        reason:
            'the double keyboard-inset bug crushed this to a sliver a few '
            'tens of points tall, hiding the search results behind what '
            'read as a blank overlay',
      );

      final controller = Get.find<MarketplaceController>();
      controller.stopPolling();
      await tester.pump();
    },
  );
}
