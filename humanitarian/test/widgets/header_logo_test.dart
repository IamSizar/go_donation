// Client note (2026-09-27): "add the app logo inside the app right next to
// the title of the tab". First reading put it on EVERY screen's title
// (AppScreen + PageTopBar) — wrong: the owner's follow-up, with a screenshot
// of "لوحة التحكم", pointed at the bottom-navigation top bar's OWN title (the
// 4 tabs: Home/لوحة التحكم, Marketplace, Events, City Guide) specifically,
// and nowhere else. This file now pins the CORRECTED scope: the shared
// [HeaderLogo] widget exists and renders, but neither of the app's two
// generic screen-chrome widgets shows it — only `DashboardTopBar` does (see
// dashboard_top_bar_logo_test.dart, which checks that one by source since
// `_TopBarTitle` is private and pulls in controllers this file does not set
// up).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

Widget _wrap(Widget child) => GetMaterialApp(
  translations: AppTranslations(),
  locale: AppLocaleService.english,
  fallbackLocale: AppLocaleService.english,
  supportedLocales: AppLocaleService.supportedLocales,
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

void main() {
  tearDown(Get.reset);

  testWidgets('HeaderLogo itself renders as an image', (tester) async {
    await tester.pumpWidget(_wrap(const HeaderLogo()));
    await tester.pump();
    expect(find.byType(HeaderLogo), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    Get.reset();
  });

  testWidgets('AppScreen does NOT show the logo beside its title', (tester) async {
    await tester.pumpWidget(_wrap(const AppScreen(title: 'reg_title_test', child: SizedBox())));
    await tester.pump();
    expect(
      find.byType(HeaderLogo),
      findsNothing,
      reason:
          'the owner asked for the logo only on the bottom-nav top bar '
          '(DashboardTopBar), not on every screen',
    );
    Get.reset();
  });

  testWidgets('PageTopBar does NOT show the logo beside its title', (tester) async {
    await tester.pumpWidget(
      _wrap(Scaffold(body: Column(children: const [PageTopBar(title: 'reg_title_test')]))),
    );
    await tester.pump();
    expect(find.byType(HeaderLogo), findsNothing);
    Get.reset();
  });
}
