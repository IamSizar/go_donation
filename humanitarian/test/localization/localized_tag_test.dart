// Pins that backend tags never reach the user as machine output.
//
// WHY THIS FILE EXISTS
// Found by walking the running app: marketplace product cards showed
// "beauty_care" and news cards showed "event" — raw English snake_case in a
// right-to-left Arabic UI, which breaks the project's hard rule that the
// Arabic interface contains no English.
//
// The values come from two different backend fields (a legacy free-text
// `category` and a `post_type` enum), so the fix is one shared helper rather
// than three patched call sites. These tests cover both halves of it: a
// translated tag wins, and an UNKNOWN tag still degrades to something
// readable — because new tags will appear server-side before anyone
// translates them, and that case must not regress to snake_case.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
  });

  group('localizedTag', () {
    test('a known tag resolves to its translated label', () {
      expect(localizedTag('beauty_care'), 'Beauty care');
      expect(localizedTag('event'), 'Event');
    });

    test('an UNKNOWN tag is humanised, never left as snake_case', () {
      // The regression that matters: a tag added server-side tomorrow must
      // not appear on a product card as "garden_tools".
      expect(localizedTag('garden_tools'), 'Garden tools');
      expect(localizedTag('some-new-kind'), 'Some new kind');
    });

    test('no tag renders nothing, so callers can hide the chip', () {
      // An empty pill is worse than no pill.
      expect(localizedTag(null), '');
      expect(localizedTag(''), '');
      expect(localizedTag('   '), '');
    });

    test('Arabic resolves the Arabic label, not the English one', () {
      Get.locale = const Locale('ar', 'SA');
      final label = localizedTag('beauty_care');

      expect(label, isNot('beauty_care'));
      expect(label, isNot('Beauty care'));
      // The whole point: no Latin letters reach an Arabic screen.
      expect(RegExp(r'[A-Za-z]').hasMatch(label), isFalse);
    });
  });
}
