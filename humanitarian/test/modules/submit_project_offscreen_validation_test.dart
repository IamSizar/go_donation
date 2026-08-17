// Pins that every required field on the project-request form is actually
// validated — including the ones scrolled out of sight.
//
// WHY THIS FILE EXISTS
// The form's body was a `ListView`, whose children are built lazily. A
// `FormField` registers itself with its `Form` in initState and unregisters in
// dispose, so a field outside the viewport is not merely invisible — it does
// not exist, and `_formKey.currentState.validate()` never asks it anything.
//
// The layout turned that into a guarantee rather than an edge case: the submit
// button is the last child of the same ListView, so reaching it REQUIRES
// scrolling the first fields off the top. Project title, category, summary,
// description and requested amount were therefore unvalidated on every real
// submission, and a request could be filed with none of them.
//
// Measured, not inferred: pumping the screen at 390x600 logical pixels built
// twelve Text widgets, ending at "Full description". The budget, location,
// contact fields and the submit button were absent from the tree entirely.
//
// Found by submitting the empty form on an iPhone 17 Pro — only the fields
// near the button objected, and scrolling back up showed the required ones
// above carrying no error state at all.
//
// The fix builds the fields eagerly (SingleChildScrollView + Column). These
// tests assert the whole form exists at once, and that a submit validates the
// top of it. They deliberately do NOT assert visibility: an off-screen widget
// that is built is still found, and being built is the property that was
// missing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_submit_project_screen.dart';

/// A viewport too short to fit the form, so "off-screen" is real. A tall test
/// surface would fit everything and hide the defect completely.
Future<void> _pumpForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 1800);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const GetMaterialApp(home: BeneficiarySubmitProjectScreen()),
  );
  // Categories are fetched in initState and fail soft under the test binding
  // (all HTTP returns 400). The screen documents that fallback; settle past it
  // rather than asserting on it, since these tests are about validation.
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('the whole form is built at once, not only the visible part', (
    tester,
  ) async {
    await _pumpForm(tester);

    // The first field and the last control must coexist. With a lazy list they
    // never did, which is what let the fields above the fold escape validation.
    expect(
      find.text('Project title'),
      findsOneWidget,
      reason: 'the first field should be built',
    );
    expect(
      find.text('Submit project request'),
      findsOneWidget,
      reason:
          'the submit button must exist while the top fields do; in a lazily '
          'built list it only appeared once they had been unmounted',
    );
  });

  testWidgets('submitting empty validates the required fields above the fold', (
    tester,
  ) async {
    await _pumpForm(tester);

    // Scroll the button into view and press it the way a person does. This is
    // the exact motion that used to unmount the fields asserted below.
    final submit = find.text('Submit project request');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();

    // These sit at the very top — the fields most certainly unmounted by the
    // time a real person reaches the button.
    expect(
      find.text('Enter a project title'),
      findsOneWidget,
      reason:
          'the title is required, but a bottom-anchored submit never validated '
          'it — a request could be filed with no title at all',
    );
    expect(
      find.text('Enter a short summary'),
      findsOneWidget,
      reason: 'the summary is required and sits above the fold too',
    );
  });
}
