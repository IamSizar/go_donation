// Pins that a city renders in the reader's language whatever case it was typed
// in — and that anything which is NOT a governorate is left alone.
//
// THE BUG
// The volunteer application card read "duhok" beside «تم الإرسال» and «أربيل».
// The governorate keys are capitalised ('Duhok') because they double as the
// English labels, but `city` is a free-text field prefilled from a preference
// that itself came from typing. So the stored value was whatever the volunteer
// wrote, `.tr` found no key, and GetX returned the string unchanged.
//
// THE LINE THIS DRAWS
// Matching case-insensitively against a CLOSED list of eighteen names is a
// normalisation. Matching loosely would be a guess, and would start rewriting
// people's own words — a village or a district that merely resembles a
// governorate must survive exactly as written. Both halves are pinned here,
// because only the second one is dangerous.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/data/iraq_governorates.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
    Get.updateLocale(const Locale('ar', 'SA'));
  });
  tearDown(Get.reset);

  test('a governorate is translated however it was typed', () {
    for (final written in ['Duhok', 'duhok', 'DUHOK', '  Duhok  ']) {
      expect(
        localizedCity(written),
        'دهوك',
        reason: '"$written" is the same governorate however it was written',
      );
    }
  });

  test('every one of the eighteen resolves and translates', () {
    for (final name in iraqGovernorates) {
      expect(governorateKeyFor(name.toLowerCase()), name);
      final label = localizedCity(name);
      expect(label, isNotEmpty);
      expect(
        RegExp(r'[A-Za-z]').hasMatch(label),
        isFalse,
        reason: '$name has no Arabic entry, so the card would print English',
      );
    }
  });

  test('text that is not a governorate is returned exactly as written', () {
    // The dangerous half: these must NOT be rewritten, matched loosely, or
    // dropped. They are what somebody typed about where they live.
    for (final written in ['Sumel', 'حي الجامعة', 'Duhok District', 'zakho']) {
      expect(governorateKeyFor(written), isNull, reason: written);
      expect(localizedCity(written), written);
    }
  });

  test('empty and null yield empty, so the card omits the field', () {
    expect(localizedCity(null), '');
    expect(localizedCity(''), '');
    expect(localizedCity('   '), '');
  });

  test('English still reads in English', () {
    Get.updateLocale(const Locale('en', 'US'));
    expect(localizedCity('duhok'), 'Duhok');
  });
}
