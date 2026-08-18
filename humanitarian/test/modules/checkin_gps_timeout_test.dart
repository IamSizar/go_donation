// Pins that a check-in cannot hang forever waiting for GPS.
//
// THE BUG, FOUND BY TAPPING IT
// `_captureEvidence` called `Geolocator.getCurrentPosition` with an accuracy
// and no `timeLimit`. A fix that never arrives is not a slow success — it is a
// screen that never finishes: the button keeps its spinner, stays disabled,
// and `_checkingInOut` never returns to false, because a call that never
// returns never runs its caller's `finally`. The only way out is killing the
// app.
//
// That matters more here than almost anywhere else in this codebase. Check-in
// exists to be used in the field — inside a distribution tent, between camp
// buildings — which is exactly where a phone cannot see enough sky to get a
// fix. The feature's normal environment is its failure case.
//
// WHAT THESE PIN
// The timeout must be DECLARED (a value in the source, not a promise in a
// comment), and its copy must be distinct from the two permission refusals:
// waiting or stepping outside fixes a timeout, and changing a setting does
// not. Telling somebody to grant a permission they already granted is worse
// than saying nothing.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

/// The source is read rather than the widget pumped: the failure is a missing
/// ARGUMENT, and no amount of pumping proves an argument is present when the
/// only way to observe it is to wait out a real GPS timeout.
String _evidenceCapture() {
  final src = File(
    'lib/modules/support/screens/support_section.dart',
  ).readAsStringSync();
  final start = src.indexOf('_captureEvidence() async {');
  expect(start, isNonNegative, reason: '_captureEvidence was renamed or moved');
  final end = src.indexOf('\n  Future<', start + 1);
  return end < 0 ? src.substring(start) : src.substring(start, end);
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  test('the GPS fix is bounded', () {
    final body = _evidenceCapture();
    expect(
      body.contains('timeLimit:'),
      isTrue,
      reason:
          'getCurrentPosition has no timeLimit, so a volunteer with no signal '
          'gets a spinner that never stops and a button that never re-enables',
    );
  });

  test('a timeout is told apart from a refusal', () {
    final body = _evidenceCapture();
    expect(
      body.contains('TimeoutException'),
      isTrue,
      reason:
          'the timeout falls into the generic catch and says nothing useful',
    );
    expect(body.contains('location_timed_out'), isTrue);
  });

  test('the three location failures each say something different', () {
    // Same message for three different causes would send someone to fix a
    // setting that is already correct.
    for (final locale in [const Locale('en', 'US'), const Locale('ar', 'SA')]) {
      Get.updateLocale(locale);
      final messages = {
        'location_permission_required'.tr,
        'location_services_disabled'.tr,
        'location_timed_out'.tr,
      };
      expect(
        messages.length,
        3,
        reason: 'two of the three collapsed to the same text in $locale',
      );
      for (final m in messages) {
        expect(m, isNotEmpty);
        expect(m.startsWith('location_'), isFalse, reason: 'untranslated: $m');
      }
    }
  });

  test('the Arabic copy is Arabic', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    expect(RegExp(r'[A-Za-z]').hasMatch('location_timed_out'.tr), isFalse);
  });
}
