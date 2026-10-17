// The app opens in Arabic by default (owner, 2026-10-17).
//
// It used to follow the phone. A phone set to English with Kurdish second — the
// common setup in Iraq — opened the whole app in Kurdish, because the device
// lookup skipped English and took the next language in the list.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/localization/locale_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a first launch opens in Arabic, whatever the phone speaks', () async {
    SharedPreferences.setMockInitialValues({});
    // The test binding's platform locale is en_US, i.e. NOT Arabic: if the old
    // "follow the phone" rule were back this would be English.
    expect(await AppLocaleService.loadLocale(), AppLocaleService.arabic);
  });

  test('a language the user chose always wins', () async {
    for (final chosen in [
      AppLocaleService.english,
      AppLocaleService.kurdishSorani,
      AppLocaleService.kurdishBadini,
      AppLocaleService.arabic,
    ]) {
      SharedPreferences.setMockInitialValues({
        'locale_code': AppLocaleService.localeTag(chosen),
      });
      expect(await AppLocaleService.loadLocale(), chosen);
    }
  });
}
