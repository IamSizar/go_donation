// Pins the fix for the reported "tap search, keyboard opens, a blank box
// covers everything" defect in the Store tab — see task-4-brief.md /
// task-4-report.md.
//
// ROOT CAUSE (found by reproducing the Store tab's exact embedding, not by
// guessing): dashboard_screen.dart used to wrap each tab's content in
// `MediaQuery.removePadding(context: context, ...)`, using the outer
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
// The fix lives in lib/modules/dashboard/screens/keyboard_safe_tab_body.dart
// (`KeyboardSafeTabBody`), which dashboard_screen.dart now delegates to
// instead of inlining the removePadding call. THIS TEST IMPORTS AND PUMPS
// THAT SAME WIDGET — not a hand-copied stand-in.
//
// IMPORTANT: this file's own test, on its own, does NOT pin the fix.
// `KeyboardSafeTabBody`'s internal `Builder` turns out to be inert once the
// wrapper is its own widget class — a widget's own `build` context is
// ALWAYS a genuine descendant of whatever Scaffold contains it, so
// `MediaQuery.removePadding(context: context, ...)` inside
// `KeyboardSafeTabBody.build` reads the correctly-stripped MediaQuery even
// without the Builder. The ORIGINAL bug only existed because
// `_DashboardScreenState.build`'s own `context` sits ABOVE the Scaffold it
// builds — a State reusing its own incoming context to read something its
// own return value is about to introduce. That means this test would NOT
// fail if someone deleted KeyboardSafeTabBody's Builder, or if
// dashboard_screen.dart stopped delegating to KeyboardSafeTabBody at all —
// it only pins that the WRAPPER behaves correctly in isolation (field stays
// above the keyboard, results list stays scrollable, rendered height stays
// sane), which is still worth having.
//
// The actual regression guard — pumping the real `DashboardScreen`, which
// is the only widget that can get the context wrong in the first place — is
// test/widgets/dashboard_screen_keyboard_test.dart. See that file's header
// for why a widget-level test alone cannot catch this defect, and for the
// harness this repo already provides for pumping DashboardScreen (an
// earlier attempt to state that as impossible was wrong).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/dashboard/screens/keyboard_safe_tab_body.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';

import '../support/fake_http.dart';

const _productsList =
    '{"success": true, "items": [{"id": 1, "name": "Honey Jar", '
    '"price": 5000}], "data": [], "summary": {}, "page": 1, '
    '"per_page": 10, "total_items": 1}';

/// Mirrors dashboard_screen.dart's body Column exactly: a fixed-height top
/// bar, an `Expanded` tab section wrapped in the REAL `KeyboardSafeTabBody`
/// (not a copy of it), and a fixed-height bottom nav bar — all inside ONE
/// outer Scaffold, the way `_DashboardScreenState.build` embeds every tab.
class _FakeDashboardShell extends StatelessWidget {
  const _FakeDashboardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 56), // stand-in DashboardTopBar
          Expanded(child: KeyboardSafeTabBody(child: child)),
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
      final keyboardHeightLogical = 300.0;
      final keyboardHeightPhysical =
          keyboardHeightLogical * tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeightPhysical,
      );
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
      // Targeted by Key rather than `find.byType(ListView).first`, which
      // would silently start matching the wrong list the day a second
      // ListView appears anywhere in this screen's subtree.
      final listView = tester.renderObject<RenderBox>(
        find.byKey(marketplaceResultsListKey),
      );
      expect(
        listView.size.height,
        greaterThan(150),
        reason:
            'the double keyboard-inset bug crushed this to a sliver a few '
            'tens of points tall, hiding the search results behind what '
            'read as a blank overlay',
      );

      // REQUIREMENT (rule 5.6): the keyboard must never cover the focused
      // field. The field's own bottom edge, in the SAME coordinate space as
      // the screen (global), must sit above where the keyboard starts.
      final fieldBox = tester.renderObject<RenderBox>(
        find.byType(TextField),
      );
      final fieldBottomGlobal =
          fieldBox.localToGlobal(Offset(0, fieldBox.size.height)).dy;
      final screenHeightLogical =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final keyboardTopGlobal = screenHeightLogical - keyboardHeightLogical;
      expect(
        fieldBottomGlobal,
        lessThanOrEqualTo(keyboardTopGlobal),
        reason:
            'the focused search field must stay above the on-screen '
            'keyboard, never behind it',
      );

      // REQUIREMENT: the results list still scrolls with the keyboard open —
      // it is not pinned/frozen by whatever laid it out at a reduced height.
      // `.first` — CatalogueFilterBar nests its own horizontal
      // Scrollable inside this list's rows, so more than one Scrollable is
      // a descendant of the results list itself.
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(marketplaceResultsListKey),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final positionBefore = scrollable.position.pixels;
      await tester.drag(
        find.byKey(marketplaceResultsListKey),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(
        scrollable.position.pixels,
        greaterThan(positionBefore),
        reason: 'the product list should still be draggable/scrollable '
            'while the keyboard is open',
      );

      final controller = Get.find<MarketplaceController>();
      controller.stopPolling();
      await tester.pump();
    },
  );
}
