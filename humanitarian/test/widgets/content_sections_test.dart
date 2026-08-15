// Pins that a content page renders its NAMED sub-sections as separate titled
// blocks (K12, app half).
//
// WHY THIS FILE EXISTS
// Backend 1696562 + migration 111 gave `app_content` a child table of named,
// ordered sub-sections, and `GET /api/content/:slug` now carries them as
// `sections` alongside the page. The server ALSO recomposes them back into
// `body_*` in the same transaction, so the installed app kept rendering the
// right words — as one undifferentiated blob. The client asked for "من نحن" to
// carry three NAMED parts (about the app, about the organization, about its
// goals); a blob is exactly what that asked to stop being.
//
// Reproduced before writing anything: `fetchContent` returned
// `decoded['content']` and dropped `sections` on the floor, and
// content_page_screen.dart rendered one `Text(body)`. `grep -rn sections lib`
// found nothing.
//
// WHAT IS PINNED, AND WHY EACH ONE
//   1. Each sub-section is its OWN block, with its own heading. This is the
//      whole row.
//   2. `body_*` is NOT drawn as well when sub-sections exist. It is composed
//      FROM them server-side, so rendering both would print every word twice.
//   3. A page with NO sub-sections still renders `body_*`. That is every page
//      the owner has not split, and breaking it would be a regression in the
//      only content this app has ever shown.
//   4. A sub-section with nothing in this locale falls back to English rather
//      than leaving a titled block with a hole in it — the same chain
//      `composeBody` uses server-side.
//   5. A page that genuinely carries nothing shows the designed empty state.
//      The old screen drew `Text('')`, i.e. a blank white page, and every one
//      of these pages is empty in production today because no prose has been
//      supplied yet.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';

import '../support/fake_http.dart';

/// One `GET /api/content/:slug` body, in the shape the Go handler returns.
String _page({
  String titleEn = 'About Us',
  String bodyEn = '',
  List<Map<String, dynamic>> sections = const [],
}) => jsonEncode({
  'success': true,
  'content': {
    'slug': 'about',
    'title_en': titleEn,
    'body_en': bodyEn,
    // The K13 columns ride on the same row and default to empty everywhere.
    'logo_path': '',
    'contact_phone': '',
    'contact_whatsapp': '',
    'contact_email': '',
    'social_links': '',
    'address_en': '',
  },
  'sections': sections,
});

/// One sub-section row, as `content.Section` marshals it.
Map<String, dynamic> _section({
  required int order,
  String titleEn = '',
  String bodyEn = '',
  String titleAr = '',
  String bodyAr = '',
}) => {
  'id': order + 1,
  'display_order': order,
  'title_en': titleEn,
  'title_ar': titleAr,
  'title_ckb': '',
  'title_kmr': '',
  'body_en': bodyEn,
  'body_ar': bodyAr,
  'body_ckb': '',
  'body_kmr': '',
};

Widget _screen({Locale locale = const Locale('en', 'US')}) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: locale,
  home: const ContentPageScreen(slug: 'about', titleKey: 'About Us'),
);

/// Pumps the screen inside the fake's zone and lets the single load land.
Future<void> _open(
  WidgetTester tester,
  FakeHttpOverrides fake, {
  Locale locale = const Locale('en', 'US'),
}) async {
  await withHttp(fake, () async {
    await tester.pumpWidget(_screen(locale: locale));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  group('named sub-sections render as separate titled blocks', () {
    testWidgets('each one gets its own heading and its own prose', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _page(
            // What the server composed from the two sub-sections. If the screen
            // renders this as well, every word appears twice.
            bodyEn: 'COMPOSED-BLOB',
            sections: [
              _section(
                order: 0,
                titleEn: 'About the app',
                bodyEn: 'What the app does.',
              ),
              _section(
                order: 1,
                titleEn: 'About the organization',
                bodyEn: 'Who we are.',
              ),
            ],
          ),
        ),
      );

      expect(find.byKey(const Key('content_section_0')), findsOneWidget);
      expect(find.byKey(const Key('content_section_1')), findsOneWidget);
      expect(find.text('About the app'), findsOneWidget);
      expect(find.text('About the organization'), findsOneWidget);
      expect(find.text('What the app does.'), findsOneWidget);
      expect(find.text('Who we are.'), findsOneWidget);
    });

    testWidgets('the composed blob is not drawn a second time', (tester) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _page(
            bodyEn: 'COMPOSED-BLOB',
            sections: [
              _section(order: 0, titleEn: 'Goals', bodyEn: 'Our goals.'),
            ],
          ),
        ),
      );

      expect(
        find.text('COMPOSED-BLOB'),
        findsNothing,
        reason:
            'ReplaceSections writes body_* FROM the sub-sections, so drawing '
            'both prints the whole page twice',
      );
      expect(find.text('Our goals.'), findsOneWidget);
    });

    testWidgets('a sub-section missing this locale falls back to English', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _page(
            sections: [
              _section(
                order: 0,
                titleEn: 'Goals',
                bodyEn: 'Our goals.',
                titleAr: 'أهدافنا',
                // No Arabic body: the same per-field fallback composeBody uses.
                bodyAr: '',
              ),
            ],
          ),
        ),
        locale: const Locale('ar', 'SA'),
      );

      expect(find.text('أهدافنا'), findsOneWidget);
      expect(find.text('Our goals.'), findsOneWidget);
    });
  });

  group('a page with no sub-sections is unchanged', () {
    testWidgets('the plain body still renders', (tester) async {
      await _open(
        tester,
        FakeHttpOverrides(
          HttpBehaviour.ok,
          body: _page(bodyEn: 'One paragraph, no sub-sections.'),
        ),
      );

      expect(find.text('One paragraph, no sub-sections.'), findsOneWidget);
      expect(find.byKey(const Key('content_section_0')), findsNothing);
    });
  });

  group('an unsupplied page says so instead of showing a blank sheet', () {
    testWidgets('empty title, empty body, no sub-sections -> empty state', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _page(titleEn: '')),
      );

      expect(
        find.byType(AppEmpty),
        findsOneWidget,
        reason:
            'the owner has supplied no prose yet, so this is the state every '
            'one of these pages is in today',
      );
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('a heading with no prose under it is still empty', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _page(titleEn: 'About Us')),
      );

      expect(
        find.byType(AppEmpty),
        findsOneWidget,
        reason:
            'the top bar already names the page, so a lone repeat of the name '
            'is a blank sheet with a title on it',
      );
    });

    testWidgets('a failed load is an error with a way out, not an empty page', (
      tester,
    ) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.serverError));

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.byType(AppEmpty), findsNothing);
      expect(find.text('retry'.tr), findsOneWidget);
    });
  });
}
