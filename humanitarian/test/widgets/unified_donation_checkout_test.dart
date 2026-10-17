// R2 #47-55 — the kind of donation is chosen ON the checkout screen (it used
// to be a separate step before it), and the screen no longer repeats itself.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';
import 'package:flutter_application_1/modules/donations/screens/continue_donation_screen.dart';

import '../support/fake_http.dart';

const _methods =
    '{"items": ['
    '{"id": 1, "slug": "cash", "method_type": "cash", "name_en": "Cash", '
    '"name_ar": "", "name_ckb": "", "name_kmr": "", "instructions_en": "", '
    '"instructions_ar": "", "instructions_ckb": "", "instructions_kmr": "", '
    '"account_number": "", "account_name": ""},'
    '{"id": 3, "slug": "visa", "method_type": "card", "name_en": "Visa Card", '
    '"name_ar": "", "name_ckb": "", "name_kmr": "", "instructions_en": "", '
    '"instructions_ar": "", "instructions_ckb": "", "instructions_kmr": "", '
    '"account_number": "", "account_name": ""}]}';

Widget _app() => GetMaterialApp(
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const ContinueDonationScreen(
    amount: 20000,
    optionTitle: 'Comprehensive Giving',
    optionSummary: '',
    optionTypeLabel: '',
    optionSupportNote: 'A flexible way to help where the need is greatest.',
    optionIcon: Icons.volunteer_activism_rounded,
    optionColor: Colors.teal,
    paymentMethod: 'Cash',
    channel: DonationChannel.cash,
  ),
);

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({
      'name_user': 'Test Donor',
      'phone_user': '9641555000005',
    });
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  testWidgets('one screen: donor line, amount, kind picker, no repeats', (
    tester,
  ) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = FakeHttpOverrides(HttpBehaviour.ok, body: _methods);
    addTearDown(() => HttpOverrides.global = previous);

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Donor details are one line, with no explanatory note beneath them.
    expect(find.text('Test Donor'), findsOneWidget);
    expect(find.text('9641555000005'), findsOneWidget);
    expect(find.textContaining('come from your verified'), findsNothing);
    // The hero card and the summary panel repeated the amount and the title.
    expect(find.text('Contribution summary'), findsNothing);
    expect(find.text('Comprehensive Giving'), findsNothing);

    // The kind of donation is picked here, not on a step before.
    expect(find.text('Cash donation (direct handover)'), findsOneWidget);
    await tester.tap(find.text('Cash donation (direct handover)'));
    await tester.pumpAndSettle();
    expect(find.text('Donation by electronic payment'), findsOneWidget);
    expect(find.text('In-kind contribution'), findsOneWidget);

    // Picking electronic swaps the methods listed below to that family.
    await tester.tap(find.text('Donation by electronic payment'));
    await tester.pumpAndSettle();
    expect(find.text('Visa Card'), findsWidgets);
  });
}
