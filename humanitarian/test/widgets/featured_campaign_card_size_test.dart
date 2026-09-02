// The Home featured-campaign cards are as tall as their content, and no taller.
//
// WHAT WAS WRONG
// The strip was a flat `SizedBox(height: 340)`. The card's content measures
// 229pt at the default text scale, so every card carried ~110pt of dead space
// under its funding block — the empty band in the owner's screenshot, and the
// "make them smaller" half of backlog item 7.
//
// A flat number was wrong in the other direction too: at 1.3x text the content
// is 262pt, and at 2.0x it exceeds 340 outright, so the same constant that
// wasted space at normal size would clip for anyone using large text.
//
// HOW THE NUMBERS WERE OBTAINED, since a test full of magic constants is worth
// little: the box was deliberately shrunk to 120pt and the framework's own
// "overflowed by N pixels" was read as a ruler — 109 at 1.0x, 142 at 1.3x.
// This test re-measures the same way, so if the card's contents change the
// numbers here stop matching and someone has to look.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/campaigns_api_client.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/widgets/dashboard.dart';

import '../support/fake_campaigns_dio.dart';
import '../support/fake_http.dart';

const _strip = ValueKey('featured-campaigns-strip');

/// Stands Home up, scrolls the strip into view, and returns the overflow
/// amounts the framework reported while doing it.
Future<List<double>> _openHome(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final previous = HttpOverrides.current;
  // The same envelope the other Home suites use: ModuleApi gates on
  // `success`, the news strip hides itself on an empty `items`, and a bare
  // '{}' makes the surrounding sections fail so the strip never mounts at all.
  HttpOverrides.global = FakeHttpOverrides(
    HttpBehaviour.ok,
    body: '{"success": true, "status": "success", "csrf_token": "t", '
        '"data": [], "items": []}',
  );
  addTearDown(() => HttpOverrides.global = previous);

  SharedPreferences.setMockInitialValues({
    'id_user': '7',
    'role_id': '1',
    'name_user': 'زيد',
    // The controller returns before it calls without this, and the carousel
    // renders its error state instead of any cards.
    'csrf_token_campaigns': 'test-token',
  });
  sharedPreferences = await SharedPreferences.getInstance();
  await AppLocaleService.syncDateFormatLocale(AppLocaleService.arabic);
  CampaignsApiClient.dio.httpClientAdapter =
      FakeCampaignsAdapter(fakeCampaignsJson());

  final overflows = <double>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    final match = RegExp(r'overflowed by ([\d.]+) pixels').firstMatch(text);
    if (match != null) {
      overflows.add(double.parse(match.group(1)!));
    } else {
      previousOnError?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: AppLocaleService.arabic,
      fallbackLocale: AppLocaleService.english,
      supportedLocales: AppLocaleService.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppThemeConfig.buildTheme(Brightness.light),
      home: Builder(
        // copyWith, not a fresh MediaQueryData: replacing it wholesale drops
        // the viewport size, the card stops laying out, and the absence of an
        // overflow then means nothing at all.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: DashboardHomeSection()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  // Home is long, and a sliver that never scrolls into view is never built —
  // so nothing about the card can be measured until it is on screen.
  await tester
      .scrollUntilVisible(
        find.byKey(_strip),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      )
      .catchError((_) {});
  await tester.pump(const Duration(milliseconds: 300));
  return overflows;
}

/// The controllers behind Home poll on Timer.periodic, and the binding checks
/// for pending timers inside the test body — so this cannot be an addTearDown.
Future<void> _closeHome(WidgetTester tester) async {
  await Get.deleteAll();
  await tester.pump();
}

void main() {
  testWidgets('the strip is sized to its content, not to a flat 340', (
    tester,
  ) async {
    final overflows = await _openHome(tester, size: const Size(402, 874));

    final height = tester.getSize(find.byKey(_strip)).height;
    expect(
      height,
      lessThanOrEqualTo(250),
      reason:
          'the card content measures 229pt at this text scale; a strip taller '
          'than ~250 is the dead band under every card that the owner asked to '
          'remove',
    );
    expect(
      height,
      greaterThanOrEqualTo(229),
      reason: 'and it must still fit the content it was measured against',
    );
    expect(overflows, isEmpty, reason: 'the content must not be clipped');

    await _closeHome(tester);
  });

  testWidgets('large text gets a taller strip rather than a clipped card', (
    tester,
  ) async {
    // The bug a flat height would reintroduce: at 1.3x the content is 262pt,
    // so any fixed number chosen to look tight at 1.0x clips here.
    final overflows = await _openHome(
      tester,
      size: const Size(402, 874),
      textScale: 1.3,
    );

    final height = tester.getSize(find.byKey(_strip)).height;
    expect(
      height,
      greaterThanOrEqualTo(262),
      reason: 'the content measures 262pt at 1.3x and must not be cut off',
    );
    expect(overflows, isEmpty, reason: 'nothing may overflow at 1.3x text');

    await _closeHome(tester);
  });

  testWidgets('the narrowest phone still fits the card', (tester) async {
    final overflows = await _openHome(tester, size: const Size(320, 640));

    expect(
      overflows,
      isEmpty,
      reason: 'the card must not overflow on a 320pt-wide screen',
    );

    await _closeHome(tester);
  });

  testWidgets('the card still shows what identifies the campaign', (
    tester,
  ) async {
    // Smaller must not mean emptier: shrinking the box is the whole change,
    // and the headline, the location and the funding numbers all stay.
    await _openHome(tester, size: const Size(402, 874));

    expect(find.textContaining('كسوة الشتاء'), findsWidgets, reason: 'headline');
    expect(find.textContaining('حرشم'), findsWidgets, reason: 'location');
    expect(find.textContaining('%'), findsWidgets, reason: 'funded percentage');

    await _closeHome(tester);
  });
}
