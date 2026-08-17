// Pins that a beneficiary case's REVIEW OUTCOME reads as language, not data.
//
// WHY THIS FILE EXISTS
// An applicant whose aid case was refused saw the word "rejected" and nothing
// else. Three columns that would have explained it — review_notes,
// reviewed_by_user_id, reviewed_at — had existed on the table since the first
// migration and no query ever returned them, and the status endpoint never
// wrote them either. The rejection notification said "please contact support
// for details", sending the applicant to ask for a reason a member of staff
// had already typed.
//
// Now that all three reach the app, the words around them have to be readable
// in Arabic. Two failure modes are pinned here:
//
//   1. the backend's own tokens ('under_review', 'needs_changes', 'high')
//      being printed as-is — the case screen used to do exactly that, with a
//      `replaceAll('_', ' ')` that only made the English prettier;
//   2. the panel's own labels having no Arabic at all.
//
// Both Kurdish locales use Arabic script, so "it looks Arabic" proves nothing
// about which map a string came from — the Kurdish assertions below check only
// that no MACHINE token survives, which is the guarantee that holds while
// Kurdish is still incomplete.
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

  // Every value `beneficiary_cases.verification_status` may hold, per the Go
  // allow-list in backend/internal/handlers/admin_status.go.
  const caseStatuses = [
    'draft',
    'submitted',
    'under_review',
    'needs_changes',
    'approved',
    'rejected',
    'archived',
  ];

  // priority_level, rendered on the same screen and in the list subtitle.
  const priorities = ['urgent', 'high', 'medium', 'low'];

  group('case status and priority tokens', () {
    test('every status has a real English label, not the raw token', () {
      for (final s in caseStatuses) {
        expect(localizedTag(s), isNot(s), reason: '$s rendered as its token');
        expect(
          localizedTag(s),
          isNot(contains('_')),
          reason: '$s leaked snake_case',
        );
      }
    });

    test('every status reads in Arabic with no Latin letters left', () {
      // The defect the client reported: English words sitting in a
      // right-to-left interface.
      Get.locale = const Locale('ar', 'SA');
      for (final s in caseStatuses) {
        final label = localizedTag(s);
        expect(label, isNotEmpty);
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '$s rendered as "$label" in Arabic',
        );
      }
    });

    test('every priority reads in Arabic with no Latin letters left', () {
      Get.locale = const Locale('ar', 'SA');
      for (final p in priorities) {
        final label = localizedTag(p);
        expect(label, isNotEmpty);
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '$p rendered as "$label" in Arabic',
        );
      }
    });

    test('no status survives as a machine token in ANY locale', () {
      // Kurdish has no entries for these yet, so localizedTag's humanising
      // branch is what protects a Kurdish reader. It must run everywhere.
      for (final locale in const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
        Locale('ar', 'IQ'), // Sorani
        Locale('ar', 'TR'), // Badini
      ]) {
        Get.locale = locale;
        for (final s in caseStatuses) {
          expect(
            localizedTag(s),
            isNot(contains('_')),
            reason: '$s leaked its token in $locale',
          );
        }
      }
    });
  });

  group('review panel labels', () {
    const labels = [
      'case_review_title',
      'case_reviewed_by',
      'case_reviewed_at',
    ];

    test('the panel labels exist in English and Arabic', () {
      for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
        Get.locale = locale;
        for (final k in labels) {
          // GetX echoes the key back when it has no entry, which is how a
          // missing translation reaches the screen as "case_reviewed_by".
          expect(k.tr, isNot(k), reason: '$k has no entry in $locale');
        }
      }
    });

    test('the Arabic labels are Arabic, not English left in place', () {
      Get.locale = const Locale('ar', 'SA');
      for (final k in labels) {
        expect(
          RegExp(r'[A-Za-z]').hasMatch(k.tr),
          isFalse,
          reason: '$k reads "${k.tr}" in Arabic',
        );
      }
    });

    test('Kurdish falls back to English rather than showing the key', () {
      // Kurdish is deliberately incomplete (TRANSLATION_REQUEST.md). The
      // requirement is a legible English fallback — never the bare key, and
      // never Arabic picked up by accident because both scripts look alike.
      for (final locale in const [Locale('ar', 'IQ'), Locale('ar', 'TR')]) {
        Get.locale = locale;
        for (final k in labels) {
          expect(k.tr, isNot(k), reason: '$k rendered as its key in $locale');
        }
      }
      // Confirm the fallback really is the English string while no Kurdish
      // entry exists, rather than the Arabic one.
      for (final k in labels) {
        if (AppTranslations.soraniForTest[k] == null) {
          Get.locale = const Locale('en', 'US');
          final english = k.tr;
          Get.locale = const Locale('ar', 'IQ');
          expect(
            k.tr,
            english,
            reason: 'no Sorani entry, so English is the required fallback',
          );
        }
      }
    });
  });
}
