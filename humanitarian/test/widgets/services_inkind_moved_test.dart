// OPOS #25293 — "In-kind donation" used to have its own tile in the Services
// hub, duplicating the Contribute tab's entry point for the same
// InKindDonationFormScreen (Contribute -> Continue -> "What kind of donation
// is this?" -> In-kind contribution, pinned by donation_kind_step_test.dart).
// It is a form of giving, not a service being requested, so it was reported
// as misplaced and removed from Services.
//
// THE CLAIM: the donor's Services list no longer offers it, and every other
// donor tile that lived alongside it is untouched.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';

void main() {
  setUp(() async {
    // Empty role_id resolves to the donor branch of _roleSpecificTiles, the
    // branch this tile used to live in.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  tearDown(Get.reset);

  testWidgets(
    'a donor no longer sees "In-kind donation" as its own Services tile',
    (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: AppLocaleService.english,
          fallbackLocale: AppLocaleService.english,
          home: const ProposalServicesSection(),
        ),
      );
      await tester.pumpAndSettle();

      // 'In-kind donation' is the translation KEY (see app_translations.dart);
      // its English display value is 'In-kind contribution' -- the same text
      // donation_kind_step_test.dart pins for the Contribute tab's copy of
      // this same tile. Asserting on the raw key would pass vacuously (the
      // key is never rendered verbatim), so the display text is what must be
      // checked.
      expect(
        find.text('In-kind contribution'),
        findsNothing,
        reason:
            'moved under Contributions (Contribute -> Continue -> "What kind '
            'of donation is this?"), so Services must not offer it too',
      );

      // The tiles that sat alongside it are unaffected — the removal did not
      // take the section, or its neighbours, down with it. Text asserted here
      // is the rendered (translated) copy, not the raw source-code keys.
      expect(find.text('Eligible cases'), findsOneWidget);
      expect(find.text('Create support'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
    },
  );
}
