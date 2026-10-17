// R2 #68 — the family-profile card must show the whole title and speak Arabic.
//
// Found on the screen reached from Home → «تصفح حسب الفئة»: the title was cut to
// ONE line and the priority tag beside it took a third of the row, so most
// titles ended in «…»; the tags read «Urgent need» / «High priority» in English
// on an Arabic screen.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/orphan_family_profiles_screen.dart';

const _long =
    'أرملة تعيل ثلاثة أطفال وتحتاج إلى دعم عاجل لتأمين الغذاء والدواء والتدفئة';

Widget _app(String priority) => GetMaterialApp(
  translations: AppTranslations(),
  locale: const Locale('ar', 'SA'),
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: 360,
        child: ProfileCard(
          item: {
            'public_title': 'x',
            'public_title_ar': _long,
            'priority_level': priority,
            'family_members_count': 4,
            'city': 'Kirkuk',
          },
        ),
      ),
    ),
  ),
);

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  testWidgets('a long title is shown in full, never ellipsised', (
    tester,
  ) async {
    await tester.pumpWidget(_app('urgent'));
    await tester.pump();

    expect(find.text(_long), findsOneWidget);
    final title = tester.renderObject<RenderParagraph>(find.text(_long));
    expect(title.didExceedMaxLines, isFalse);
  });

  testWidgets('every priority tag is Arabic', (tester) async {
    const expected = {
      'urgent': 'حاجة عاجلة',
      'high': 'أولوية عالية',
      'low': 'دعم مستقر',
      'medium': 'دعم مستمر',
    };
    for (final e in expected.entries) {
      await tester.pumpWidget(_app(e.key));
      await tester.pump();
      expect(find.text(e.value), findsOneWidget, reason: e.key);
    }
  });
}
