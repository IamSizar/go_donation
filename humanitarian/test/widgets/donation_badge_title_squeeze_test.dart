// A campaign's title keeps its width when its category badge is long.
//
// WHAT WAS REPORTED
// A phone screenshot of the campaign details screen showed a title wrapped one
// syllable per line, because a wide badge shared a Row with the title. An audit
// (OPOS #28157) found the same layout on the Contribute tab: the campaign LIST
// card and the SELECTED-campaign card both put the title (an Expanded) in one
// Row with _DonationTypeBadge(campaign.category).
//
// ROOT CAUSE
// A Row lays non-flexible children out at natural width FIRST and gives the
// Expanded title only what is left. Measured on the real widget (real Arabic
// font, 360dp, text scale 1.3) the title kept 157 px with no category, 110 px
// with the seeded 'رعاية طبية', 62 px (about 19 lines) with the seeded Badini
// 'چاودێریا پزیشکی', and 0 px with a long admin-typed category.
//
// WHY THE REAL FONT IS LOADED
// flutter_test draws text in the Ahem font, where every glyph is a full-em
// square, so every width in a default test is meaningless. setUpAll registers
// the app's own NotoKufiArabic so the measurements are true.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';

/// The real controller starts a network fetch and a 15 s poll in onInit; the
/// test only needs the list it holds, so onInit does nothing.
class _StubCampaigns extends FeaturedCampaignsController {
  @override
  // Skipping super is the point: it would fetch from the network and start the
  // polling timer.
  // ignore: must_call_super
  void onInit() {}
}

const _campaignId = 43;
const _title = 'حملة خيرية يتم من خلالها التبرع لعدد من الفقراء';

/// Real category names from backend/migrations/029_project_categories.sql, plus
/// one an admin could type (categories are editable, so length is unbounded).
const _seededArabic = 'رعاية طبية';
const _seededBadini = 'چاودێریا پزیشکی';
const _adminLong = 'المساعدات الغذائية والإغاثة العاجلة';

/// Pumps the real Contribute screen with one campaign selected, so both the
/// list card and the selected-campaign card are on screen.
Future<void> _pump(
  WidgetTester tester, {
  required String category,
  double textScale = 1.3,
}) async {
  Get.reset();
  addTearDown(Get.reset);
  SharedPreferences.setMockInitialValues({'id_user': '7', 'role_id': '1'});
  sharedPreferences = await SharedPreferences.getInstance();

  final stub = _StubCampaigns();
  stub.campaigns.assignAll([
    FeaturedCampaignData.fromJson({
      'id': _campaignId,
      'title': 'x',
      'title_ar': _title,
      'category': category,
      'category_ar': category,
      'amount_needed': 1000000,
      'raised_amount': 250000,
    }),
  ]);
  Get.put<FeaturedCampaignsController>(stub);

  // A common phone: 360 x 800 logical px.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  const locale = Locale('ar', 'SA');
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      theme: AppThemeConfig.applyLocaleFont(
        AppThemeConfig.buildTheme(Brightness.dark),
        locale,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const DonationsSection(initialCampaignId: _campaignId),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Finds the private selected-campaign card by its type name.
Finder _selectedCard() => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_SelectedDonationCard',
);

Finder _listCard() => find.byType(DonationFeaturedCampaignCard);

Finder _badge() => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_DonationTypeBadge',
);

/// Asserts, for one card, that the title is readable and the badge is under it
/// rather than beside it.
void _expectTitleKeepsItsWidth(WidgetTester tester, Finder card, String name) {
  expect(card, findsOneWidget, reason: '$name should be on screen');
  final title = find.descendant(of: card, matching: find.text(_title));
  final badge = find.descendant(of: card, matching: _badge());
  expect(title, findsOneWidget);
  expect(badge, findsOneWidget);

  expect(
    tester.getSize(title).width,
    greaterThan(140),
    reason: '$name: the category badge is squeezing the title beside it',
  );
  expect(
    tester.getTopLeft(badge).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
    reason: '$name: the badge shares a row with the title and takes its width',
  );
}

void main() {
  setUpAll(() async {
    final bytes = File(
      'assets/fonts/NotoKufiArabic-Variable.ttf',
    ).readAsBytesSync();
    final loader = FontLoader('NotoKufiArabic')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  final scenarios = <String, ({String category, double scale})>{
    'a seeded Arabic category at scale 1.3': (
      category: _seededArabic,
      scale: 1.3,
    ),
    'the longest seeded (Badini) category at scale 1.3': (
      category: _seededBadini,
      scale: 1.3,
    ),
    'a long admin-typed category at scale 1.3': (
      category: _adminLong,
      scale: 1.3,
    ),
    'a long admin-typed category at scale 2.0': (
      category: _adminLong,
      scale: 2.0,
    ),
  };

  scenarios.forEach((name, s) {
    testWidgets('list card keeps its title with $name', (tester) async {
      await _pump(tester, category: s.category, textScale: s.scale);
      _expectTitleKeepsItsWidth(tester, _listCard(), 'list card');
      expect(tester.takeException(), isNull, reason: 'list card overflowed');
    });

    testWidgets('selected card keeps its title with $name', (tester) async {
      await _pump(tester, category: s.category, textScale: s.scale);
      _expectTitleKeepsItsWidth(tester, _selectedCard(), 'selected card');
      expect(
        tester.takeException(),
        isNull,
        reason: 'selected card overflowed',
      );
    });
  });
}
