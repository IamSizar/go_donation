// Pins that the volunteer application card speaks the reader's language.
//
// TWO LEAKS, ONE LINE
// The card's subtitle read "submitted - duhok - Mon 09:00-17:00, Tue …" on an
// Arabic screen. Found by actually submitting an application as a volunteer.
//
//   * STATUS was the raw column with underscores swapped for spaces. The four
//     values the backend allows are already keys in every locale, so the fix
//     was the missing `.tr`, not new copy.
//
//   * AVAILABILITY was the harder half. The `availability` column stores the
//     summary the FORM produced, and the form produced it with English day
//     names — the English was already IN THE DATA, so no display-time `.tr`
//     could have repaired it. The structured `availability_schedule` is stored
//     beside it and holds day KEYS, which localize.
//
// So this file is mostly about the second: given the same stored row, the
// summary must follow the reader, not whoever filled the form.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/support/widgets/availability_schedule_picker.dart';

const _schedule = [
  {'day': 'mon', 'from': '09:00', 'to': '17:00'},
  {'day': 'sun', 'from': '09:00', 'to': '17:00'},
];

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  test('Arabic gets Arabic day names, not the stored English', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    final summary = localizedScheduleSummary(_schedule);

    expect(summary.contains('إثن'), isTrue, reason: 'Monday should be Arabic');
    expect(summary.contains('أحد'), isTrue, reason: 'Sunday should be Arabic');
    expect(
      RegExp(r'Mon|Sun').hasMatch(summary),
      isFalse,
      reason: 'this is the exact English that reached the Arabic card',
    );
    // The times stay as stored — they are numerals, not words.
    expect(summary.contains('09:00-17:00'), isTrue);
  });

  test('English still reads in English', () {
    Get.updateLocale(const Locale('en', 'US'));
    final summary = localizedScheduleSummary(_schedule);
    expect(summary.contains('Mon'), isTrue);
    expect(summary.contains('Sun'), isTrue);
  });

  test('the four application statuses all resolve in Arabic', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    for (final status in ['submitted', 'approved', 'rejected', 'inactive']) {
      final label = status.tr;
      expect(
        label,
        isNot(status),
        reason: '"$status" fell through untranslated onto an Arabic card',
      );
      expect(RegExp(r'[A-Za-z]').hasMatch(label), isFalse);
    }
  });

  test('the eight mission signup statuses all resolve in Arabic', () {
    // A second code path with the same omission: the «مهامي» card printed
    // "pending" in English beside fully Arabic text. Every value the backend
    // allows already had copy — only the .tr was missing.
    Get.updateLocale(const Locale('ar', 'SA'));
    for (final status in [
      'pending',
      'approved',
      'rejected',
      'joined',
      'completion_requested',
      'cancelled',
      'completed',
      'no_show',
    ]) {
      final label = status.tr;
      expect(
        label,
        isNot(status),
        reason: '"$status" would render untranslated on the missions card',
      );
      expect(RegExp(r'[A-Za-z]').hasMatch(label), isFalse);
    }
  });

  test('a governorate on the missions card is translated', () {
    // The card said "Erbil" while the detail screen one tap away said أربيل.
    Get.updateLocale(const Locale('ar', 'SA'));
    expect('Erbil'.tr, 'أربيل');
    expect('Duhok'.tr, isNot('Duhok'));
    // Free text someone typed is not a key and must survive untouched rather
    // than being mangled into something else.
    expect('duhok'.tr, 'duhok');
  });

  test('case priority and household size are translated', () {
    Get.updateLocale(const Locale('ar', 'SA'));

    // priority_level is a backend token printed on the case card.
    for (final p in ['low', 'medium', 'high', 'urgent']) {
      expect(p.tr, isNot(p), reason: '"$p" would print as a bare token');
      expect(RegExp(r'[A-Za-z]').hasMatch(p.tr), isFalse);
    }

    // The household label was two hardcoded English literals.
    expect('household_individual'.tr, isNot('household_individual'));
    expect(RegExp(r'[A-Za-z]').hasMatch('household_individual'.tr), isFalse);

    final family = 'household_family_of'.trParams({'count': '3'});
    expect(family.contains('3'), isTrue, reason: 'the count must survive');
    expect(family.contains('Family'), isFalse);
    expect(
      family,
      isNot(contains('@count')),
      reason: 'the placeholder was left unsubstituted',
    );
  });

  test('a missing or malformed schedule yields nothing, so the caller can '
      'fall back to the stored text', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    expect(localizedScheduleSummary(null), '');
    expect(localizedScheduleSummary('not a list'), '');
    expect(
      localizedScheduleSummary(const [
        {'day': 'nope'},
      ]),
      '',
    );
  });

  test(
    'an unknown locale falls back to English rather than dropping the day',
    () {
      Get.updateLocale(const Locale('fr', 'FR'));
      final summary = localizedScheduleSummary(_schedule);
      expect(summary, isNotEmpty);
      expect(summary.contains('Mon'), isTrue);
    },
  );
}
