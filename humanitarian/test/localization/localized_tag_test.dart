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

    test('a snake_case token never survives to the screen, in any language',
        () {
      // The humanising branch must run for EVERY locale, not just English.
      // A Kurdish reader seeing "garden_tools" is the same defect as an Arabic
      // one seeing it.
      for (final locale in const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
        Locale('ar', 'IQ'),
        Locale('ar', 'TR'),
      ]) {
        Get.locale = locale;
        expect(localizedTag('garden_tools'), isNot(contains('_')),
            reason: 'raw token leaked in $locale');
      }
    });

    test('a tag translated only in English degrades to English, not Kurdish',
        () {
      // Kurdish is deliberately incomplete. `beauty_care` has no Sorani entry,
      // so a Sorani reader must get the ENGLISH label — not the Badini one,
      // which is what GetX's language-only fallback used to hand back.
      Get.locale = const Locale('ar', 'IQ');
      final sorani = localizedTag('beauty_care');
      Get.locale = const Locale('en', 'US');
      final english = localizedTag('beauty_care');

      expect(sorani, isNotEmpty);
      expect(sorani, isNot('beauty_care'));
      // Either a real Sorani label exists, or it falls back to English. What
      // it must NEVER be is Arabic or Badini text picked up by accident.
      final soraniEntry = AppTranslations.soraniForTest['beauty_care'];
      if (soraniEntry == null) {
        expect(sorani, english,
            reason: 'no Sorani entry, so English is the required fallback');
      }
    });
  });

  group('the backend tags actually rendered by the app', () {
    // These are the values that reach localizedTag call sites today:
    //   marketplace_controller.dart:366  product['category']  (legacy free text)
    //   news_activities_screen.dart:307  item['post_type']    (enum)
    //   dashboard.dart:1925              post['post_type']    (enum)
    //   dashboard.dart:95                any status token
    //   technical_support_screen.dart:342 ticket status
    const postTypes = ['activity', 'event', 'news', 'article'];
    const supportStatuses = ['open', 'in_progress', 'resolved', 'closed'];

    test('post_type enum values all have real labels in en and ar', () {
      for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
        Get.locale = locale;
        for (final t in postTypes) {
          final label = localizedTag(t);
          expect(label, isNotEmpty);
          expect(label, isNot(t),
              reason: '$t rendered as the raw token in $locale');
        }
      }
    });

    test('support ticket statuses render as words, never as tokens', () {
      // technical_support_screen builds `status_<value>`; localizedTag is the
      // fallback when that key is absent. Either way no underscore may show.
      Get.locale = const Locale('ar', 'SA');
      for (final s in supportStatuses) {
        expect('status_$s'.tr, isNot('status_$s'),
            reason: 'status_$s has no Arabic entry');
        expect(localizedTag(s), isNot(contains('_')));
      }
    });
  });
}
