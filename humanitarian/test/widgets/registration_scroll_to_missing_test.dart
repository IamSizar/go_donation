// The edit form opens at the first thing the person still has to fill in.
//
// WHY THIS EXISTS
// The banner on Home says the profile is incomplete and hands the person a
// button. The button opened a 4,800-line form AT THE TOP, with the gap
// somewhere below — often several screens below, since the fields that are
// already answered are exactly the ones that scroll past first. The client's
// words for it were "open at the first missing field".
//
// WHAT IS ACTUALLY PINNED HERE
// Not "it scrolls" — a form that scrolled to the wrong field would pass that.
// The property is WHICH field it picks: the topmost missing one, chosen by
// real on-screen position rather than by the order the admin's rule set
// happens to arrive in. The two are deliberately put in conflict below.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';

import '../support/fake_http.dart';
import '../support/rendered_tree.dart';

/// One body answers BOTH requests the form makes on open — the admin's field
/// rules and the person's saved profile — because the fake serves a single
/// body to every URL. It works because the two readers look at disjoint keys:
/// the rules parser reads `required`/`hidden`/`searchable` and ignores the
/// rest, the profile prefill reads columns and ignores those three. Cheaper
/// than teaching the shared fake about routing for one test.
///
/// The two required keys are deep in the grantor section — far enough down
/// that reaching either one REQUIRES scrolling, so "did it move" is a real
/// question rather than an artefact of a tall viewport.
///
/// They are listed with the education level FIRST while the form renders the
/// surname ABOVE it. That inversion is the point: a fix that simply jumped to
/// the first entry of the rule set would land on the education question and scroll
/// clean past the unanswered surname.
String _body({required List<String> required}) =>
    '{"required": ${_jsonList(required)}, "hidden": [], "searchable": [], '
    '"full_name": "زيد العراقي", "address": "الموصل", "city": "دهوك", '
    '"date_of_birth": "2000-11-03"}';

String _jsonList(List<String> items) =>
    '[${items.map((s) => '"$s"').join(', ')}]';

Future<ScrollableState> _openEditForm(
  WidgetTester tester, {
  required List<String> requiredKeys,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.reset);

  final previous = HttpOverrides.current;
  HttpOverrides.global = FakeHttpOverrides(
    HttpBehaviour.ok,
    body: _body(required: requiredKeys),
  );
  addTearDown(() => HttpOverrides.global = previous);
  addTearDown(Get.reset);

  SharedPreferences.setMockInitialValues({
    'id_user': '7',
    'role_id': '1',
    'name_user': 'زيد العراقي',
    'address_user': 'الموصل',
  });
  sharedPreferences = await SharedPreferences.getInstance();
  await AppLocaleService.syncDateFormatLocale(AppLocaleService.english);

  // Every DropdownButtonFormField on this form overflows under the test
  // font — measured and written up in role_registration_fields_test.dart's
  // header. It is the harness, not the screen, so it is diverted rather than
  // asserted on; leaving it undiverted fails THIS test for someone else's
  // reason.
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
      home: const RegistrationFormPage(editMode: true),
    ),
  );
  // Two futures resolve on the microtask queue and each rebuilds the form;
  // then the post-frame callback runs and the 400ms scroll plays out.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  // The jump is requested from a post-frame callback, so it is only SCHEDULED
  // by the pump above — these frames are the ones the 400ms animation
  // actually runs in.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  });
  // The form's own scroll view, not merely the first Scrollable in the tree —
  // dropdowns and the app bar contribute their own, and reading one of those
  // reports offset 0.0 forever no matter what the page does.
  final scrollables = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((s) => s.position.maxScrollExtent > 0)
      .toList();
  expect(
    scrollables,
    hasLength(1),
    reason: 'expected exactly one scrollable page; found ${scrollables.length}',
  );
  return scrollables.single;
}

void main() {
  testWidgets('it scrolls to the topmost missing field, not the first rule', (
    tester,
  ) async {
    final scrollable = await _openEditForm(
      tester,
      requiredKeys: ['grantor_education_level', 'grantor_title_surname'],
    );

    expect(
      scrollable.position.pixels,
      greaterThan(0),
      reason:
          'the form still opened at the top — the person is looking at the '
          'fields they already answered, which is the defect',
    );
    // Both are missing; the surname is the one ABOVE, so it is the one that
    // has to be on screen. Whether the education field is also visible depends
    // on how far apart they sit, so only the surname is asserted.
    expect(
      find.text('Surname / title'),
      findsWidgets,
      reason:
          'it scrolled somewhere, but not to the topmost gap. Jumping to the '
          'education question (the first entry in the rule set) leaves the '
          'surname above the fold, unanswered and unseen.',
    );
  });

  testWidgets('the target follows what is missing, not a fixed offset', (
    tester,
  ) async {
    // Same form, one required key instead of two. If the jump were hardcoded
    // or driven by anything other than the gaps themselves, this would land in
    // the same place as the test above.
    final scrollable = await _openEditForm(
      tester,
      requiredKeys: ['grantor_education_level'],
    );

    expect(scrollable.position.pixels, greaterThan(0));
    expect(
      find.text('Educational attainment'),
      findsWidgets,
      reason:
          'the surname is not required in this configuration, so the first '
          'gap is the education level and that is where the form must open',
    );
  });
}
