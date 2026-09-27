// Form-level pin for migration 136: on the volunteer registration form, picking
// a governorate that staff have listed cities for (Nineveh) replaces the
// free-text city box with the AreaPicker; a governorate with no cities keeps
// the free-text box. Harness mirrors role_registration_fields_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';
import 'package:flutter_application_1/modules/auth/widgets/area_picker.dart';

import '../support/fake_http.dart';
import '../support/rendered_tree.dart';

Map<String, dynamic> _city(int id, String ar, String en) => {
  'id': id,
  'governorate': 'Nineveh',
  'parent_id': null,
  'level': 'city',
  'name_en': en,
  'name_ar': ar,
  'name_ckb': '',
  'name_kmr': '',
  'display_order': id,
  'active': true,
  'children': 0,
};

void main() {
  tearDown(() {
    Get.reset();
    AreaDirectory.instance.resetForTest();
  });

  testWidgets('volunteer: picking Nineveh swaps the free-text city for the picker',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(402, 2400);
    addTearDown(tester.view.reset);

    final previous = HttpOverrides.current;
    HttpOverrides.global = FakeHttpOverrides(
      HttpBehaviour.ok,
      body: '{"required": [], "hidden": [], "searchable": []}',
    );
    addTearDown(() => HttpOverrides.global = previous);

    SharedPreferences.setMockInitialValues({
      'id_user': '7',
      'role_id': '3',
      'name_user': 'زيد العراقي',
    });
    sharedPreferences = await SharedPreferences.getInstance();
    await AppLocaleService.syncDateFormatLocale(AppLocaleService.english);

    AreaDirectory.instance.api = ModuleApi(
      httpClient: MockClient((request) async {
        final nineveh = request.url.queryParameters['governorate'] == 'Nineveh';
        return http.Response(
          jsonEncode({
            'success': true,
            'items': nineveh
                ? [_city(1, 'الموصل', 'Mosul'), _city(2, 'تلعفر', 'Tel Afar')]
                : <Map<String, dynamic>>[],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await captureOverflowLocations(() async {
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: AppLocaleService.english,
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

      final cityHint = 'reg_city_hint'.tr;
      bool freeTextCity() => tester
          .widgetList<TextField>(find.byType(TextField))
          .any((t) => t.decoration?.hintText == cityHint);

      // Before any governorate: the free-text city is the only way to answer.
      expect(freeTextCity(), isTrue);

      final dropdown = find.ancestor(
        of: find.text('reg_grantor_governorate_hint'.tr),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nineveh'.tr).last);
      await tester.pumpAndSettle();
      // Let the /areas request resolve and the form rebuild.
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(AreaDirectory.instance.peek('Nineveh')?.hasCities, isTrue);
      expect(find.byType(AreaPicker), findsOneWidget);
      expect(freeTextCity(), isFalse,
          reason: 'the free-text city box must go once Nineveh has a city list');
    });
    Get.reset();
  });
}
