// Migration 138 — the volunteer registration asks for the ID card, residence
// card and ration card as three separate documents, each front AND back,
// instead of a merged "Golden Square" photo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';

import '../support/fake_http.dart';
import '../support/rendered_tree.dart';

Future<void> _pump(WidgetTester tester, Locale locale, String rules) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(402, 30000);
  addTearDown(tester.view.reset);
  final previous = HttpOverrides.current;
  HttpOverrides.global = FakeHttpOverrides(HttpBehaviour.ok, body: rules);
  addTearDown(() => HttpOverrides.global = previous);
  SharedPreferences.setMockInitialValues({
    'id_user': '7',
    'role_id': '3',
    'name_user': 'زيد العراقي',
  });
  sharedPreferences = await SharedPreferences.getInstance();
  await AppLocaleService.syncDateFormatLocale(locale);
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: AppLocaleService.english,
      supportedLocales: AppLocaleService.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppThemeConfig.buildTheme(Brightness.light),
      home: const RegistrationFormPage(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  tearDown(Get.reset);

  const labels = [
    'reg_volunteer_id_photo_doc',
    'reg_id_photo_back',
    'reg_volunteer_ration_card_photo',
    'reg_ration_card_photo_back',
    'reg_volunteer_residence_card_photo',
    'reg_residence_card_photo_back',
  ];
  const open = '{"required": [], "hidden": [], "searchable": []}';

  for (final locale in [AppLocaleService.english, AppLocaleService.arabic]) {
    testWidgets('${locale.languageCode}: six document pickers, no golden square',
        (tester) async {
      await captureOverflowLocations(() async {
        await _pump(tester, locale, open);
        for (final key in labels) {
          expect(key.tr, isNot(key), reason: '$key has no translation');
          expect(find.text(key.tr), findsOneWidget, reason: key);
        }
        expect(find.text('reg_volunteer_golden_square_photo'.tr), findsNothing);
      });
      Get.reset();
    });
  }

  testWidgets('hiding a document rule removes both of its sides',
      (tester) async {
    await captureOverflowLocations(() async {
      await _pump(
        tester,
        AppLocaleService.english,
        '{"required": [], "hidden": ["volunteer_ration_card_photo"], '
        '"searchable": []}',
      );
      expect(find.text('reg_volunteer_ration_card_photo'.tr), findsNothing);
      expect(find.text('reg_ration_card_photo_back'.tr), findsNothing);
      expect(find.text('reg_volunteer_id_photo_doc'.tr), findsOneWidget);
    });
    Get.reset();
  });
}
