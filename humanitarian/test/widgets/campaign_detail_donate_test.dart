// Every signed-in role can donate from a campaign's page.
//
// WHAT WAS REPORTED
// "When I tap on a campaign I want to see a button here to donate directly."
// The account was a VOLUNTEER, and the button was wrapped in
// `if (role_id == '1')` — so donors saw it and nobody else did. The rest of
// the page rendered identically for every role: funding progress, location,
// timeline, contact. A page that shows you a half-funded campaign and offers
// no way to give is the whole defect.
//
// WHY REMOVING THE GATE IS SAFE
// Nothing was enforcing it. POST /donations checks the caller is signed in
// and not a guest and says nothing about role (backend/internal/handlers/
// donations.go), so the restriction existed only in this widget. Guests are
// still stopped, one screen later, by the donate flow's own upgrade prompt.
//
// The test pumps the real screen at each role, because the bug was that one
// role saw something different from another — and only rendering all of them
// can catch a gate coming back.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';

/// A campaign with the fields the page needs to render at all.
FeaturedCampaignData _campaign() => FeaturedCampaignData.fromJson(const {
  'id': 42,
  'title': 'Winter Relief for Displaced Families',
  'location': 'Erbil - Harsham Camp',
  'target_amount': 5000000,
  'collected_amount': 150000,
  'status': 'active',
});

Future<void> _openAs(WidgetTester tester, String roleId) async {
  addTearDown(Get.reset);
  SharedPreferences.setMockInitialValues({'id_user': '7', 'role_id': roleId});
  sharedPreferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      home: CampaignDetailScreen(campaign: _campaign()),
    ),
  );
  await tester.pump();
}

void main() {
  // 1 donor, 2 eligible recipient, 3 volunteer — the three roles the app
  // registers. Before the fix only the first of these passed.
  for (final role in const ['1', '2', '3']) {
    testWidgets('role $role is offered the donate button', (tester) async {
      await _openAs(tester, role);

      expect(
        find.text('Donate to this campaign'.tr),
        findsOneWidget,
        reason:
            'role $role can see the campaign and its funding gap but is given '
            'no way to close it. Nothing server-side refuses their donation.',
      );
    });
  }

  testWidgets('the button hands the caller a donate intent, not a bare pop', (
    tester,
  ) async {
    // The three screens that open this page all listen for `true` and use it
    // to start the donate flow (selecting this campaign, not just any). A pop
    // carrying nothing would dismiss the page and do nothing else, which is
    // indistinguishable from a dead button.
    await _openAs(tester, '3');

    Object? result;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator
          .push(
            MaterialPageRoute<Object?>(
              builder: (_) => CampaignDetailScreen(campaign: _campaign()),
            ),
          )
          .then((value) => result = value),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Donate to this campaign'.tr).last);
    await tester.pumpAndSettle();

    expect(
      result,
      isTrue,
      reason:
          'the callers key the donate flow off this exact value; anything else '
          'closes the page and leaves the user where they started',
    );
  });
}
