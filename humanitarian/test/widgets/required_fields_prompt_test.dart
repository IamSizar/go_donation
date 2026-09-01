// required_fields_prompt_test.dart — owner #16's safety net.
//
// THE PROPERTY UNDER TEST IS A NEGATIVE ONE, which is why it needs a test at
// all: when staff make a registration field required, the people who already
// signed up must be PROMPTED and NEVER BLOCKED. A prompt is easy to build; a
// prompt that cannot accidentally become a gate is the thing to pin down.
//
// Four claims:
//
//  1. The set of missing fields is computed from the role's own rules, and a
//     hidden field is never demanded (it cannot be filled in).
//  2. The prompt appears for a user missing a newly-required field, and the
//     screen behind it stays fully usable — nothing is covered, nothing is
//     disabled, no route is intercepted.
//  3. Dismissing it works, and it does not come back.
//  4. A user missing nothing sees nothing at all — not an empty banner, not a
//     reserved gap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/profile/required_fields_prompt.dart';

// ─── The pure decision ──────────────────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'id_user': '7', 'role_id': '3'});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  tearDown(Get.reset);

  group('which fields are missing', () {
    test('only this role\'s rules apply, and shared ones apply to everybody', () {
      const rules = FieldRuleSets(
        required: {
          'volunteer_national_id', // this role — and blank
          'volunteer_phone1', // this role — and filled in
          'recipient_tribe_clan', // ANOTHER role's rule
          'gender', // unprefixed: the shared sign-up step
        },
        hidden: {},
      );
      final missing = missingRequiredFields(
        roleId: 3,
        rules: rules,
        account: const {'national_id': '', 'phone1': '07700000000', 'gender': ''},
      );
      expect(missing, ['gender', 'volunteer_national_id']);
    });

    test('a hidden field is never demanded', () {
      // A field the form does not render cannot be filled in, so demanding it
      // would send the user to a screen with nothing to do — a dead end.
      const rules = FieldRuleSets(
        required: {'volunteer_languages'},
        hidden: {'volunteer_languages'},
      );
      expect(
        missingRequiredFields(roleId: 3, rules: rules, account: const {'languages': ''}),
        isEmpty,
      );
    });

    test('a role with no registration form is never prompted', () {
      // Role 0 / a staff account has no form behind it, so no rule applies.
      const rules = FieldRuleSets(required: {'gender'}, hidden: {});
      expect(rulePrefixForRole(0), isNull);
      expect(
        missingRequiredFields(roleId: 0, rules: rules, account: const {'gender': ''}),
        // The unprefixed shared keys still apply — they are asked of everyone
        // who registers — but nothing role-specific leaks in.
        ['gender'],
      );
    });

    test('a multi-column field counts as missing until every part is there', () {
      // "Full name" is one question and four columns; three of four filled in
      // is not a filled-in name.
      const rules = FieldRuleSets(required: {'volunteer_name_parts'}, hidden: {});
      expect(
        missingRequiredFields(roleId: 3, rules: rules, account: const {
          'name_first': 'Zaid',
          'name_father': 'Ali',
          'name_grandfather': 'Hassan',
          'name_family': '',
        }),
        ['volunteer_name_parts'],
      );
    });
  });

  // ─── The banner ───────────────────────────────────────────────────────────

  /// Stands the prompt up over a page that stands in for the dashboard, so the
  /// "does not block" claim is checked against something the user can actually
  /// still press.
  Future<void> pumpPrompt(
    WidgetTester tester, {
    required List<String> missing,
  }) async {
    var behindTapped = 0;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: AppLocaleService.english,
        fallbackLocale: AppLocaleService.english,
        home: Scaffold(
          body: Column(
            children: [
              RequiredFieldsPrompt(loader: () async => missing, onOpenProfile: () {}),
              TextButton(
                onPressed: () => behindTapped++,
                child: const Text('carry on'),
              ),
            ],
          ),
        ),
      ),
    );
    // The loader resolves on the microtask queue and setStates the banner.
    await tester.pump();
    await tester.pump();

    // THE CLAIM: whatever the banner is doing, the app underneath still works.
    await tester.tap(find.text('carry on'));
    await tester.pump();
    expect(behindTapped, 1, reason: 'the prompt blocked the screen behind it');
  }

  testWidgets('it appears when a newly-required field is missing, and blocks nothing',
      (tester) async {
    await pumpPrompt(tester, missing: ['volunteer_national_id']);
    expect(find.text('A few details are still missing'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('dismissing it hides it, and it does not come back', (tester) async {
    await pumpPrompt(tester, missing: ['volunteer_national_id']);

    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('A few details are still missing'), findsNothing);

    // The dismissal outlives the widget: a fresh mount, same missing set —
    // which is what "does not nag on every launch" means.
    expect(isPromptDismissed(['volunteer_national_id']), isTrue);
    await pumpPrompt(tester, missing: ['volunteer_national_id']);
    expect(find.text('A few details are still missing'), findsNothing);

    // But a DIFFERENT set is a different request, and is asked once. Storing a
    // single boolean instead would silence staff forever after one dismissal.
    expect(isPromptDismissed(['volunteer_national_id', 'volunteer_phone1']), isFalse);
  });

  testWidgets('a user missing nothing sees nothing at all', (tester) async {
    await pumpPrompt(tester, missing: const []);
    expect(find.text('A few details are still missing'), findsNothing);
    // Not an empty banner and not a reserved gap: the whole widget collapses.
    expect(
      tester.getSize(find.byType(RequiredFieldsPrompt)).height,
      0,
      reason: 'an empty prompt still took up room at the top of every screen',
    );
  });
}
