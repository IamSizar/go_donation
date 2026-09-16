// My Donations must never show the backend's raw English error text — OPOS
// #25282.
//
// THE BUG
// donations.go answers a failed history/stats fetch with
// `{"success": false, "error": "Could not fetch donations or stats."}` — a
// hardcoded English literal never run through internal/notify's 4-language
// system. MyDonationsController.fetchHistory then did
// `map['error']?.toString() ?? 'Could not load donations.'.tr` — since the
// backend ALWAYS sends a non-null `error`, the localized fallback was
// unreachable dead code and the raw English string rendered on an otherwise
// fully-Arabic screen ("حدث خطأ ما / Could not fetch donations or stats.").
//
// THE FIX
// Stop trusting the backend's error text for display at all — always show
// the client's own localized copy, matching how errors are handled
// throughout the rest of the app (the backend text can still change freely
// without an app release, since nothing renders it).
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/controllers/my_donations_controller.dart';

import '../support/fake_http.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'id_user': '42'});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  for (final locale in [const Locale('en', 'US'), const Locale('ar', 'SA')]) {
    test(
      'a backend failure shows localized copy, not the raw English text ($locale)',
      () async {
        Get.updateLocale(locale);
        final localizedFallback = 'Could not load donations.'.tr;

        final fake = FakeHttpOverrides(
          HttpBehaviour.ok,
          body: jsonEncode({
            'success': false,
            'error': 'Could not fetch donations or stats.',
            'items': [],
            'summary': {
              'total_count': 0,
              'total_amount': '0',
              'success_count': 0,
              'success_amount': '0',
              'pending_count': 0,
              'pending_amount': '0',
              'failed_count': 0,
              'failed_amount': '0',
            },
          }),
        );

        final controller = MyDonationsController();
        await withHttp(fake, () => controller.fetchHistory());

        expect(
          controller.errorMessage.value,
          localizedFallback,
          reason:
              'the backend\'s own English "error" text must never reach the '
              'UI — every screen shows this app\'s own localized copy',
        );
        expect(
          controller.errorMessage.value,
          isNot(contains('Could not fetch donations or stats')),
          reason: 'the raw backend literal must not leak through verbatim',
        );
      },
    );
  }

  test('a missing/invalid user_id (400) also shows localized copy', () async {
    Get.updateLocale(const Locale('ar', 'SA'));
    final localizedFallback = 'Missing or invalid user.'.tr;

    final fake = FakeHttpOverrides(
      HttpBehaviour.ok,
      status: 400,
      body: jsonEncode({
        'success': false,
        'error': 'Missing or invalid user_id.',
      }),
    );

    final controller = MyDonationsController();
    await withHttp(fake, () => controller.fetchHistory());

    expect(controller.errorMessage.value, localizedFallback);
  });
}
