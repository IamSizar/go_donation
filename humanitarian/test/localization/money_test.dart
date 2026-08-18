// Pins that money reads in the reader's language, everywhere.
//
// THE BUG
// «IQD 0» on a screen where every other word was Arabic. A translation for the
// code had existed all along (د.ع) and nothing called it.
//
// WHY IT SURVIVED SO LONG
// _formatMoney was copied byte-for-byte into four screens. Fixing one would
// have left three wrong — which is exactly how the app came to render money
// two different ways. The duplication and the leak were the same defect.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/money.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  test('an Arabic reader sees the Arabic currency, not the code', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    final shown = formatMoney(50000, 'IQD');
    expect(shown.contains('د.ع'), isTrue, reason: 'got "$shown"');
    expect(shown.contains('IQD'), isFalse,
        reason: 'the raw code must not reach an Arabic reader; got "$shown"');
  });

  test('an English reader still sees IQD', () {
    Get.updateLocale(const Locale('en', 'US'));
    expect(formatMoney(50000, 'IQD'), contains('IQD'));
  });

  test('an unknown currency passes through untranslated rather than guessed',
      () {
    // GetX returns the key when there is no translation, and for a currency
    // the code itself is the right fallback: a campaign priced in USD must
    // stay USD, not become an invention.
    Get.updateLocale(const Locale('ar', 'SA'));
    expect(formatMoney(10, 'USD'), contains('USD'));
    expect(localizedCurrency('EUR'), 'EUR');
  });

  test('a missing currency falls back rather than rendering a bare number', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    expect(formatMoney(10, '   '), contains('د.ع'));
    expect(localizedCurrency('   '), '');
  });

  test('the amount is grouped for the reader', () {
    Get.updateLocale(const Locale('en', 'US'));
    expect(formatMoney(50000, 'IQD'), startsWith('50,000'));
  });
}
