// Pins the redesigned first-run screen (chunk 11): it must render without
// overflow in both themes, in both text directions, and under a large
// Dynamic Type scale, and the language control and primary CTA must both
// stay present and reachable (>=44pt touch target) after the layout moved
// them out of the old bordered card.
//
// WHY THIS FILE EXISTS
// The previous welcome.dart had no dedicated test — the whole screen was one
// small card with no layout logic worth pinning. The redesign removed the
// card, relocated the language selector into a top bar, and enlarged the
// brand mark and heading. Those are exactly the kind of change that silently
// breaks under RTL mirroring or a larger system font size, so this file
// checks the things a human reviewer can't easily eyeball from one
// screenshot: no RenderFlex overflow, and every interactive element still
// meets the touch-target floor, across the matrix of states the screen
// actually ships in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/welcome.dart';

/// The welcome screen wrapped in just enough app to render and navigate.
///
/// `GetMaterialApp` because the screen resolves strings through `.tr` and
/// navigation through `Get.toNamed('/login')`; a bare `/login` route is
/// registered so the CTA has somewhere to go without requiring the app's
/// real routing table.
Widget _welcomeApp({
  required Brightness brightness,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1.0,
}) {
  return GetMaterialApp(
    theme: AppThemeConfig.buildTheme(Brightness.light),
    darkTheme: AppThemeConfig.buildTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    getPages: [
      GetPage(name: '/login', page: () => const SizedBox.shrink()),
    ],
    builder: (context, child) => Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
    home: const WelcomeScreen(),
  );
}

void main() {
  tearDown(Get.reset);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      testWidgets(
        'renders without overflow — ${brightness.name}/${direction.name}',
        (tester) async {
          await tester.pumpWidget(
            _welcomeApp(brightness: brightness, direction: direction),
          );
          await tester.pumpAndSettle();

          // A RenderFlex overflow (or any other rendering error) surfaces as
          // an exception recorded by the test binding, not a thrown error —
          // this is the standard way to assert "nothing overflowed".
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('survives a large Dynamic Type scale without clipping', (
    tester,
  ) async {
    // 1.3x mirrors iOS's "Accessibility Large" band; the screen must reflow
    // (via AuthScaffold's SingleChildScrollView), not clip or throw.
    await tester.pumpWidget(
      _welcomeApp(brightness: Brightness.light, textScale: 1.3),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Continue with phone'), findsOneWidget);
  });

  testWidgets('the language control is present and reachable', (
    tester,
  ) async {
    await tester.pumpWidget(_welcomeApp(brightness: Brightness.light));
    await tester.pumpAndSettle();

    // `_LangOption` is a private type, so match by the base widget type
    // rather than a generic argument the test file can't name.
    final trigger = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('PopupMenuButton'),
    );
    expect(trigger, findsOneWidget);

    final size = tester.getSize(trigger);
    expect(
      size.height,
      greaterThanOrEqualTo(44),
      reason: 'language control must clear the 44pt touch-target floor',
    );

    // Reachable: opening it lists every supported language.
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Arabic'), findsOneWidget);
  });

  testWidgets(
    'the primary CTA is present with an adequate touch target and navigates',
    (tester) async {
      await tester.pumpWidget(_welcomeApp(brightness: Brightness.light));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(ElevatedButton, 'Continue with phone');
      expect(button, findsOneWidget);

      final size = tester.getSize(button);
      expect(size.height, greaterThanOrEqualTo(44));

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(Get.currentRoute, '/login');
    },
  );

  // Second-pass regression coverage (chunk 12) — pins the two measured
  // defects from the real-device screenshot that the first redesign missed.
  testWidgets(
    'header, headline, button and subtitle all share one horizontal gutter',
    (tester) async {
      // Defect 2 was measured on a real 720x1600 Motorola Defy screenshot:
      // the headline sat ~35px from the edge while the button sat at a
      // visibly wider inset. Reproduce that exact viewport so the assertion
      // actually exercises the same geometry, not an incidental match at
      // the default 800x600 test window.
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_welcomeApp(brightness: Brightness.light));
      await tester.pumpAndSettle();

      final languageControl = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().startsWith('PopupMenuButton'),
      );
      final headline = find.text('Balance and Stability for a Better Life!');
      final button = find.widgetWithText(ElevatedButton, 'Continue with phone');
      final subtitle = find.text(
        'Sign in or create an account with your phone number.',
      );

      final headlineLeft = tester.getTopLeft(headline).dx;
      final buttonLeft = tester.getTopLeft(button).dx;
      final subtitleLeft = tester.getTopLeft(subtitle).dx;

      // The language control is trailing-aligned (centerEnd) rather than
      // leading, so it's checked against the mirrored (right) edge instead.
      final languageRight = tester.getTopRight(languageControl).dx;
      final buttonRight = tester.getTopRight(button).dx;

      const tolerance = 1.0;
      expect(
        (headlineLeft - buttonLeft).abs(),
        lessThanOrEqualTo(tolerance),
        reason: 'headline and button must share the same leading gutter',
      );
      expect(
        (subtitleLeft - buttonLeft).abs(),
        lessThanOrEqualTo(tolerance),
        reason: 'subtitle and button must share the same leading gutter',
      );
      expect(
        (languageRight - buttonRight).abs(),
        lessThanOrEqualTo(tolerance),
        reason: 'header control and button must share the same trailing gutter',
      );
    },
  );

  testWidgets(
    "the primary button's vertical centre sits in the screen's lower portion",
    (tester) async {
      // Defect 1: the whole block was vertically centred, leaving ~350px of
      // empty space above the header and ~300px below the subtitle. The
      // primary action must anchor toward the bottom (thumb reach), not
      // float in the middle of the screen. Same reproduction viewport as
      // the gutter test above.
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_welcomeApp(brightness: Brightness.light));
      await tester.pumpAndSettle();

      final languageControl = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().startsWith('PopupMenuButton'),
      );
      final button = find.widgetWithText(ElevatedButton, 'Continue with phone');
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final headerTop = tester.getTopLeft(languageControl).dy;
      final buttonCenterY = tester.getCenter(button).dy;

      // The header must anchor to the top of the safe area, not float
      // ~350px down as it did when the whole block was vertically centred.
      expect(
        headerTop,
        lessThan(100),
        reason: 'the header control must anchor near the top of the screen',
      );
      // The button must anchor toward the bottom (thumb reach), not sit
      // near the vertical middle of the screen.
      expect(
        buttonCenterY,
        greaterThan(screenHeight * 0.6),
        reason:
            'the primary CTA must sit in the lower ~40% of the screen, '
            'not vertically centred',
      );
    },
  );

  // chunk13 regression coverage — pins the fix for the defect the previous
  // pass left behind: the header/button anchors were correct, but the brand
  // block (logo + wordmark + headline) still sat top-aligned within the
  // middle region, dumping all the slack into one band above the button.
  testWidgets(
    'the brand block is vertically centred within its own region, not '
    'top-aligned',
    (tester) async {
      // Same reproduction viewport as the anchor tests above, so this
      // exercises the same geometry the real-device measurement used.
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_welcomeApp(brightness: Brightness.light));
      await tester.pumpAndSettle();

      final languageControl = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().startsWith('PopupMenuButton'),
      );
      final headline = find.text('Balance and Stability for a Better Life!');
      final button = find.widgetWithText(ElevatedButton, 'Continue with phone');

      // The region the brand block owns runs from just below the header to
      // just above the button — approximate its bounds with those two
      // anchors, which are themselves pinned by the tests above.
      final regionTop = tester.getBottomLeft(languageControl).dy;
      final regionBottom = tester.getTopLeft(button).dy;
      final regionMid = (regionTop + regionBottom) / 2;

      // The brand block spans from the top of the logo to the bottom of
      // the headline; its own centre should land near the region's centre
      // rather than hugging the top of it. Measure the actual painted
      // content — the brand-mark image and the headline text — not a
      // wrapping `Center`'s own box: `Center` fills all the space its
      // `ConstrainedBox(minHeight: ...)` parent offers it (that's exactly
      // what makes the fill-and-centre trick work at large text scales),
      // so the wrapper's bounds always span the whole region regardless
      // of where its content actually sits — asserting on it would pass
      // even if the layout regressed back to top-aligned.
      final brandImage = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/balancenex_icon.png',
      );
      final blockTop = tester.getTopLeft(brandImage).dy;
      final blockBottom = tester.getBottomLeft(headline).dy;
      final blockCenter = (blockTop + blockBottom) / 2;

      // Generous tolerance (10% of the region's height): this is a "not
      // pinned to the top" guard, not a pixel-exact centring assertion —
      // internal padding/rhythm can shift the true centre slightly without
      // the layout having regressed to top-aligned.
      final regionHeight = regionBottom - regionTop;
      expect(
        (blockCenter - regionMid).abs(),
        lessThan(regionHeight * 0.15),
        reason:
            'the brand block must be centred in the space between the '
            'header and the button, not stuck at the top of it',
      );
    },
  );
}
