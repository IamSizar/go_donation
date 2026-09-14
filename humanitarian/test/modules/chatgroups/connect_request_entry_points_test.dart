// Pins where a member can ask staff to connect them — OPOS #25284 Phase 5
// Task 5 (OPOS #26046).
//
// WHAT IS PINNED
//   1. ConnectRequestButton renders NOTHING for a guest — the server refuses
//      guests on this route (auth.RequireNotGuest), so the button could only
//      ever fail for them — and nothing when there is no id to name.
//   2. A signed-in member sees the labelled button. The icon-only variant used
//      inside a donation row is announced by name and opens the sheet.
//   3. BeneficiaryCaseDetailScreen offers it for its own case. (Users only
//      ever see a case CODE, so a "type a case number" dialog could not have
//      named the case — the entry point lives on the case itself.)
//   4. BeneficiaryCampaignDonationsScreen offers it on each donation row, for
//      that donation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_button.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_sheet.dart';
import 'package:flutter_application_1/modules/proposal/screens/beneficiary_case_detail_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_campaign_donations_controller.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart';

/// Lets a frame build and a sheet animate, in short steps.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps [home] inside the app's theme and translations, in English.
Future<void> _pump(WidgetTester tester, Widget home) async {
  Get.locale = const Locale('en', 'US');
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppThemeConfig.buildTheme(Brightness.light),
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: home,
    ),
  );
  await _settle(tester);
}

/// Disposes the tree before the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// [child] on a bare screen.
Widget _onScreen(Widget child) => Scaffold(body: Center(child: child));

/// A campaign-donations controller that answers from [seed] instead of the
/// network. The screen finds it because it is registered first.
class _SeededCampaignDonations extends BeneficiaryCampaignDonationsController {
  _SeededCampaignDonations(this.seed);

  /// The campaigns, shaped as BeneficiaryCampaignDonations writes them.
  final List<Map<String, dynamic>> seed;

  @override
  Future<void> fetch() async => campaigns.assignAll(seed);
}

void main() {
  final label = AppTranslations.englishForTest['connect_request_action']!;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.reset();
  });

  tearDown(Get.reset);

  group('ConnectRequestButton', () {
    testWidgets('renders nothing for a guest', (tester) async {
      await sharedPreferences.setBool(kGuestModePrefsKey, true);

      await _pump(
        tester,
        _onScreen(
          const ConnectRequestButton(
            contextType: kConnectContextDonation,
            contextId: 42,
          ),
        ),
      );

      expect(find.byType(AppPressable), findsNothing);
      expect(find.text(label), findsNothing);
      await _close(tester);
    });

    testWidgets('renders nothing when there is no id', (tester) async {
      await _pump(
        tester,
        _onScreen(
          const ConnectRequestButton(
            contextType: kConnectContextDonation,
            contextId: null,
          ),
        ),
      );

      expect(find.byType(AppPressable), findsNothing);
      expect(find.text(label), findsNothing);
      await _close(tester);
    });

    testWidgets('a signed-in member sees the labelled button', (tester) async {
      await _pump(
        tester,
        _onScreen(
          const ConnectRequestButton(
            contextType: kConnectContextDonation,
            contextId: 42,
          ),
        ),
      );

      expect(find.text(label), findsOneWidget);
      await _close(tester);
    });

    testWidgets('the icon-only variant is announced by name and opens the '
        'sheet', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        _onScreen(
          const ConnectRequestButton.iconOnly(
            contextType: kConnectContextDonation,
            contextId: 42,
          ),
        ),
      );

      expect(find.text(label), findsNothing);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);

      await tester.tap(find.byType(ConnectRequestButton));
      await _settle(tester);

      expect(find.byType(ConnectRequestSheet), findsOneWidget);
      semantics.dispose();
      await _close(tester);
    });
  });

  group('BeneficiaryCaseDetailScreen', () {
    testWidgets('offers the action for its case', (tester) async {
      await _pump(
        tester,
        const BeneficiaryCaseDetailScreen(
          caseItem: {
            'id': 7,
            'case_code': 'CSE-000007',
            'public_title': 'Winter support',
          },
        ),
      );

      final button = tester.widget<ConnectRequestButton>(
        find.byType(ConnectRequestButton),
      );
      expect(button.contextType, kConnectContextCase);
      expect(button.contextId, 7);
      expect(find.text(label), findsOneWidget);
      await _close(tester);
    });

    testWidgets('offers nothing for a case without an id', (tester) async {
      await _pump(
        tester,
        const BeneficiaryCaseDetailScreen(
          caseItem: {'case_code': 'CSE-000007'},
        ),
      );

      expect(find.text(label), findsNothing);
      await _close(tester);
    });
  });

  testWidgets('a campaign donation row offers the action for that donation', (
    tester,
  ) async {
    Get.put<BeneficiaryCampaignDonationsController>(
      _SeededCampaignDonations([
        {
          'id': 3,
          'title': 'Winter fuel',
          'title_ar': '',
          'goal_amount': '1000',
          'raised_amount': '250',
          'status': 'active',
          'donations': [
            {
              'id': 91,
              'donor_user_id': 12,
              'amount': '250',
              'delivery_status': 'received',
              'payment_method': 'cash',
              'message': '',
              'transaction_date': '2026-09-14T10:00:00Z',
              'donor_name': 'Sara',
              'donor_phone': null,
            },
          ],
        },
      ]),
    );

    await _pump(tester, const BeneficiaryCampaignDonationsScreen());

    final finder = find.byType(ConnectRequestButton);
    final button = tester.widget<ConnectRequestButton>(finder);
    expect(button.contextType, kConnectContextDonation);
    expect(button.contextId, 91);

    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await _settle(tester);

    expect(find.byType(ConnectRequestSheet), findsOneWidget);
    await _close(tester);
  });
}
