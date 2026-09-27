// Migration 137 — the events (marriage) profile asks for the ID card, residence
// card and ration card as three separate documents, each front AND back,
// instead of one "Golden Square" photo of all three.
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
import 'package:flutter_application_1/modules/marriage/screens/marriage_form_screen.dart';

import '../../support/fake_http.dart';
import '../../support/rendered_tree.dart';

const _rules =
    '{"required": ["marriage_id_photo", "marriage_residence_card_photo", '
    '"marriage_ration_card_photo"], "hidden": [], "searchable": []}';

Future<void> _pump(WidgetTester tester, Locale locale, String rules) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(402, 14000);
  addTearDown(tester.view.reset);
  final previous = HttpOverrides.current;
  HttpOverrides.global = FakeHttpOverrides(HttpBehaviour.ok, body: rules);
  addTearDown(() => HttpOverrides.global = previous);
  SharedPreferences.setMockInitialValues({'id_user': '7'});
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
      home: const MarriageFormScreen(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  tearDown(Get.reset);

  const labels = [
    'reg_grantor_id_photo',
    'reg_id_photo_back',
    'reg_volunteer_residence_card_photo',
    'reg_residence_card_photo_back',
    'reg_volunteer_ration_card_photo',
    'reg_ration_card_photo_back',
  ];

  for (final locale in [AppLocaleService.english, AppLocaleService.arabic]) {
    testWidgets(
      '${locale.languageCode}: six document pickers, no golden square',
      (tester) async {
        await captureOverflowLocations(() async {
          await _pump(tester, locale, _rules);
          for (final key in labels) {
            // Each label must resolve (a missing key would render itself).
            expect(key.tr, isNot(key), reason: '$key has no translation');
            expect(find.text(key.tr), findsOneWidget, reason: key);
          }
          expect(find.text('marriage_golden_square'.tr), findsNothing);
          // ID + residence require both sides, ration card the front only -> five markers.
          expect(find.text('*'), findsNWidgets(5));
        });
        Get.reset();
      },
    );
  }

  testWidgets('a rule that hides a document removes both of its sides', (
    tester,
  ) async {
    await captureOverflowLocations(() async {
      await _pump(
        tester,
        AppLocaleService.english,
        '{"required": [], "hidden": ["marriage_ration_card_photo"], '
        '"searchable": []}',
      );
      expect(find.text('reg_volunteer_ration_card_photo'.tr), findsNothing);
      expect(find.text('reg_ration_card_photo_back'.tr), findsNothing);
      expect(find.text('reg_grantor_id_photo'.tr), findsOneWidget);
      expect(find.text('*'), findsNothing);
    });
    Get.reset();
  });

  testWidgets(
    'submitting with no photos is refused naming the first document',
    (tester) async {
      await captureOverflowLocations(() async {
        await _pump(tester, AppLocaleService.english, _rules);
        final submit = find.text('marriage_submit'.tr);
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(
          find.textContaining('${'reg_grantor_id_photo'.tr}: '),
          findsOneWidget,
        );
        await tester.pumpAndSettle(const Duration(seconds: 5));
      });
      Get.reset();
    },
  );

  // Client note: religion under القومية, weight + height with skin tone, and
  // the age asked once (derived from the date of birth).
  double? fieldTop(WidgetTester tester, String labelKey) {
    final f = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == labelKey.tr,
    );
    return f.evaluate().isEmpty ? null : tester.getTopLeft(f).dy;
  }

  double? labelTop(WidgetTester tester, String key) {
    final f = find.text(key.tr);
    return f.evaluate().isEmpty ? null : tester.getTopLeft(f.first).dy;
  }

  testWidgets('physical fields sit together and religion follows ethnicity', (
    tester,
  ) async {
    await captureOverflowLocations(() async {
      await _pump(tester, AppLocaleService.english, _rules);
      final skin = labelTop(tester, 'marriage_skin_tone')!;
      final weight = fieldTop(tester, 'marriage_weight')!;
      final height = fieldTop(tester, 'marriage_height')!;
      final family = fieldTop(tester, 'reg_family_size')!;
      expect(weight, greaterThan(skin));
      expect(height, greaterThan(weight));
      expect(
        family,
        greaterThan(height),
        reason: 'weight + height come right after skin tone, before the rest',
      );
      final ethnicity = fieldTop(tester, 'marriage_ethnicity')!;
      final religion = fieldTop(tester, 'marriage_religion')!;
      final skills = fieldTop(tester, 'reg_skills')!;
      expect(religion, greaterThan(ethnicity));
      expect(
        skills,
        greaterThan(religion),
        reason: 'religion sits directly under ethnicity',
      );
    });
    Get.reset();
  });

  testWidgets('age is asked once: only when the date of birth is hidden', (
    tester,
  ) async {
    await captureOverflowLocations(() async {
      await _pump(tester, AppLocaleService.english, _rules);
      expect(fieldTop(tester, 'marriage_age'), isNull);
      expect(find.text('marriage_date_of_birth'.tr), findsOneWidget);
    });
    Get.reset();
    await captureOverflowLocations(() async {
      await _pump(
        tester,
        AppLocaleService.english,
        '{"required": [], "hidden": ["marriage_date_of_birth"], "searchable": []}',
      );
      expect(fieldTop(tester, 'marriage_age'), isNotNull);
      expect(find.text('marriage_date_of_birth'.tr), findsNothing);
    });
    Get.reset();
  });
}
