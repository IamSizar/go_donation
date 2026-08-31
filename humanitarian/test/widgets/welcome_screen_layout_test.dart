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
}
