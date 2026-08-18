// Pins that the social chip's fallback word is translated, and that brand
// names are NOT.
//
// THE BUG
// On the Arabic الشركاء screen a partner's chip read «Social» in English,
// sitting beside «زيارة الموقع». socialNetworkLabel names the network behind a
// URL so a chip reads "Facebook" rather than a raw address, and falls back to
// the generic word "Social" for a host it does not recognise. The brand names
// are correct untranslated — they are proper nouns — but the fallback is an
// ordinary English word and was reaching Arabic readers as one.
//
// THE LINE THIS DRAWS
// Only the fallback is translated. Running the brand names through .tr would
// invite someone to add a 'Facebook' key later and "translate" a proper noun,
// which is how you end up with «فيسبوك» in one place and «Facebook» in
// another. Both halves are pinned, because only the second one is dangerous.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/shared/utils/social_links.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  test('an unrecognised link gets an Arabic label for an Arabic reader', () {
    Get.updateLocale(const Locale('ar', 'SA'));
    final label = socialNetworkLabel('https://some-unknown-network.example/x');
    expect(label, isNot('Social'),
        reason: 'the generic fallback must not reach an Arabic reader in English');
    expect(label, contains('اجتماعي'));
  });

  test('an English reader still sees the English fallback', () {
    Get.updateLocale(const Locale('en', 'US'));
    expect(socialNetworkLabel('https://some-unknown-network.example/x'), 'Social');
  });

  test('brand names are never translated, in any locale', () {
    for (final locale in [const Locale('ar', 'SA'), const Locale('en', 'US')]) {
      Get.updateLocale(locale);
      expect(socialNetworkLabel('https://facebook.com/x'), 'Facebook');
      expect(socialNetworkLabel('https://wa.me/9647'), 'WhatsApp');
      expect(socialNetworkLabel('https://t.me/x'), 'Telegram');
      expect(socialNetworkLabel('https://youtu.be/x'), 'YouTube');
      expect(socialNetworkLabel('https://x.com/x'), 'X');
    }
  });
}
