// Pins that the marriage/events post card localises the city it prints.
//
// THE BUG
// The card's meta line is built as `gender · age · city`. Gender went through
// `.tr` and city did not, so an Arabic reader saw «ذكر · 33 · Mosul» — two
// translated fields and one English one, inside the same run of text.
//
// This is the same defect already fixed for the volunteer application card
// (see localized_city_test.dart). The helper existed and this call site simply
// never used it; the file was even importing content_localizer.dart already.
// That is why the test asserts through the widget rather than the helper —
// localizedCity was never broken, the call site was, and only a widget test
// can tell those two apart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_post_card.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  /// Pumps one card with the given profile, in the given locale.
  Future<void> pumpCard(
    WidgetTester tester,
    Map<String, dynamic> profile,
    Locale locale,
  ) async {
    // The card carries a 4:3 image, which overflows the default 800x600 test
    // surface. That overflow is a harness artifact, not a product defect — but
    // it throws during layout and would mask the assertion underneath it.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Get.updateLocale(locale);
    await tester.pumpWidget(
      GetMaterialApp(
        locale: locale,
        translations: AppTranslations(),
        home: Directionality(
          textDirection:
              locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: MarriagePostCard(
              profile: profile,
              saved: false,
              onSave: () {},
              onMeet: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the city is shown in Arabic beside the other Arabic fields',
      (tester) async {
    await pumpCard(tester, {
      'profile_code': 'M-2026000004',
      'gender': 'male',
      'age': '33',
      'city': 'Erbil',
      'social_summary': 'نبذة',
    }, const Locale('ar', 'SA'));

    expect(
      find.textContaining('Erbil'),
      findsNothing,
      reason: 'an Arabic reader must not be shown the English governorate name',
    );
    expect(find.textContaining('أربيل'), findsOneWidget);
  });

  testWidgets('a city that is not a governorate survives exactly as written',
      (tester) async {
    // The boundary that matters: normalising a closed list is safe, but
    // rewriting someone's own words is not. Mosul is the honest example — it is
    // a city inside Nineveh governorate, not a governorate, so it is NOT in the
    // list and must survive exactly as typed. City is a free-text field, so an
    // English city name entered by a user still reaches the reader in English;
    // that is a separate product question, not something this helper decides.
    await pumpCard(tester, {
      'profile_code': 'M-2026000005',
      'gender': 'female',
      'age': '29',
      'city': 'Mosul',
      'social_summary': 'نبذة',
    }, const Locale('ar', 'SA'));

    expect(find.textContaining('Mosul'), findsOneWidget);
  });

  testWidgets('an English reader still sees the English name', (tester) async {
    await pumpCard(tester, {
      'profile_code': 'M-2026000006',
      'gender': 'male',
      'age': '41',
      'city': 'Erbil',
      'social_summary': 'bio',
    }, const Locale('en', 'US'));

    expect(find.textContaining('Erbil'), findsOneWidget);
  });
}
