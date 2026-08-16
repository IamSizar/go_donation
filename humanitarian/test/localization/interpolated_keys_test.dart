// Guards the "interpolated key with nothing behind it" failure, which has
// shipped to users three separate times.
//
// THE SHAPE OF THE BUG
// Screens build translation keys by string interpolation:
//     Text('marital_$m'.tr)
//     InfoChip(label: 'sponsorship_status_$status')
// GetX returns the key UNCHANGED when it has no entry, so a value with no
// matching entry renders the literal `sponsorship_status_cancelled` on screen.
// Nothing throws, nothing logs, and a coverage count of "1967 == 1967" still
// looks perfect — the key is simply absent, or (worse) present with the key
// itself as its value.
//
// So this file pins the CROSS-PRODUCT: for every interpolated key family, every
// value that family's variable can actually take must resolve to real copy.
// The value sets below are not guesses — each was traced to the hardcoded list
// in the widget, or to the database CHECK constraint / Go allowlist that bounds
// what the backend can send, and the source is named on every entry.
//
// WHEN THIS TEST FAILS
// Either a new option was added to a dropdown without its label, or the backend
// gained an enum value. Add the entry to `_en` (and `_ar`); Kurdish is allowed
// to be missing and falls back to English by design (see locale_routing_test).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

/// One interpolated key family: the literal prefix, every value the variable
/// can hold, and where that set was read from.
class _KeyFamily {
  const _KeyFamily(this.prefix, this.values, this.source);
  final String prefix;
  final List<String> values;
  final String source;
}

const List<_KeyFamily> _families = [
  // ─── registration_form.dart — hardcoded const option lists ───
  _KeyFamily('education_',
      ['none', 'primary', 'secondary', 'diploma', 'bachelor', 'master', 'phd'],
      'registration_form.dart:1852/2523/4140 and marriage_form_screen.dart:1181'),
  _KeyFamily('nationality_', ['iraqi', 'syrian', 'egyptian', 'gulf', 'other'],
      'registration_form.dart:2125/3769, marriage_form_screen.dart:949'),
  _KeyFamily(
      'marital_',
      ['single', 'engaged', 'married', 'separated', 'widowed', 'divorced', 'other'],
      'registration_form.dart:2156/4092'),
  _KeyFamily('residency_', ['local', 'returnee', 'displaced', 'refugee', 'other'],
      'registration_form.dart:2190, marriage_form_screen.dart:971'),
  _KeyFamily('housing_side_', ['right', 'left', 'other'],
      'registration_form.dart:2256/3887, marriage_form_screen.dart:1018'),
  // Union of both sites: the volunteer variant drops `usage`, the eligible one
  // includes it, so the union is what must be backed.
  _KeyFamily('housing_type_',
      ['owned', 'rented', 'inherited', 'shared', 'usage', 'other'],
      'registration_form.dart:2377 (with usage) + 3986, marriage_form_screen.dart:1113'),
  _KeyFamily('floors_', ['one', 'one_half', 'two', 'three_plus'],
      'registration_form.dart:2442, marriage_form_screen.dart:1149'),
  _KeyFamily('yesno_', ['yes', 'no'], 'registration_form.dart (7 sites), marriage_form_screen.dart (6 sites)'),
  _KeyFamily('smoking_', ['non_smoker', 'smoker', 'former'],
      'registration_form.dart:2975, marriage_form_screen.dart:1285'),
  _KeyFamily('eyesight_', ['normal', 'glasses', 'weak', 'blind'],
      'registration_form.dart:3005, marriage_form_screen.dart:1301'),
  // Distinct family from housing_type_ — different prefix AND different set.
  _KeyFamily('housing_', ['owned', 'rented', 'hosted', 'displaced'],
      'registration_form.dart:3528'),
  _KeyFamily(
      'language_',
      ['arabic', 'english', 'kurdish', 'turkish', 'german', 'french',
        'chinese_japanese', 'other'],
      'data/nineveh_districts.dart:22 volunteerLanguages'),
  _KeyFamily('exp_', ['none', 'lt1', 'y1to3', 'gt3'], 'registration_form.dart:4424'),

  // ─── marriage screens ───
  _KeyFamily('skin_tone_', ['fair', 'medium', 'olive', 'brown', 'dark'],
      'marriage_form_screen.dart:1249'),
  // 8 values — a different family from `marital_` above, which has 7.
  _KeyFamily(
      'marital_status_',
      ['single', 'engaged', 'married', 'separated', 'widowed', 'divorced',
        'separated_never_married', 'other'],
      'marriage_form_screen.dart:1551, marriage_search_screen.dart:229, '
      'marriage_profile_edit_screen.dart:43'),
  _KeyFamily('employment_status_',
      ['employed', 'unemployed', 'self_employed', 'student'],
      'marriage_form_screen.dart:1585, marriage_search_screen.dart:261, '
      'marriage_profile_edit_screen.dart:53'),
  _KeyFamily('vis_', ['private', 'employee_only', 'matched_summary'],
      'marriage_form_screen.dart:1621, marriage_profile_edit_screen.dart:59'),
  // BACKEND: CHECK in migrations/058_marriage_mediated_chat.sql:24.
  _KeyFamily('marriage_chat_status_', ['pending', 'active', 'declined'],
      'DB CHECK 058_marriage_mediated_chat.sql:24'),

  // ─── marketplace ───
  // BACKEND, application-enforced only: marketplaceLabels in
  // backend/internal/handlers/admin_edit.go:597. No DB CHECK exists.
  _KeyFamily('label_', ['new', 'sale', 'featured', 'used', 'in_stock'],
      'Go allowlist admin_edit.go:597'),

  // ─── sponsorship ───
  _KeyFamily('sched_empty_', ['upcoming', 'due', 'overdue', 'history'],
      'sponsorship_schedule_screen.dart:28 _filters'),
  _KeyFamily('sched_status_', ['upcoming', 'due', 'overdue', 'paid', 'skipped'],
      'DB CHECK 086_sponsorship_schedule.sql:52'),
  _KeyFamily('sponsorship_', ['weekly', 'monthly', 'quarterly', 'yearly'],
      'DB CHECK 001_full_v2.sql:592 schedule_interval'),
  // ALL SEVEN. The overview screen (sponsorship_overview_screen.dart:175)
  // applies no status filter, so every DB value reaches a chip — this is the
  // family that shipped `sponsorship_status_cancelled` to users.
  _KeyFamily(
      'sponsorship_status_',
      ['pending', 'active', 'paused', 'delayed', 'stopped', 'completed', 'cancelled'],
      'DB CHECK 001_full_v2.sql:595, unfiltered by sponsorships.go:44'),

  // ─── self-guarded sites (they humanise on miss) — pinned anyway so the
  // translated path stays the one users get ───
  _KeyFamily('marriage_status_',
      ['submitted', 'under_review', 'active', 'paused', 'matched', 'rejected', 'closed'],
      'DB CHECK 001_full_v2.sql:504'),
  _KeyFamily('status_', ['open', 'in_progress', 'resolved', 'closed'],
      'DB CHECK 001_full_v2.sql:615 support tickets'),
];

void main() {
  final english = AppTranslations.englishForTest;
  final arabic = AppTranslations.arabicForTest;

  setUp(() {
    Get.clearTranslations();
    Get.addTranslations(AppTranslations().keys);
    Get.fallbackLocale = const Locale('en', 'US');
    Get.locale = const Locale('en', 'US');
  });

  group('every interpolated key resolves to real copy', () {
    for (final family in _families) {
      test('${family.prefix}* — ${family.values.length} values', () {
        final missing = <String>[];
        final selfReferencing = <String>[];

        for (final value in family.values) {
          final key = '${family.prefix}$value';
          final entry = english[key];
          if (entry == null) {
            missing.add(key);
          } else if (entry == key) {
            // The entry exists but its value IS the key, so the user reads the
            // raw token anyway. This is how sponsorship_status_cancelled
            // survived a coverage check.
            selfReferencing.add(key);
          }
        }

        expect(missing, isEmpty,
            reason: 'No English entry — GetX renders these keys verbatim to '
                'the user. Values come from ${family.source}.');
        expect(selfReferencing, isEmpty,
            reason: 'Entry exists but its value is the key itself, so the raw '
                'token still reaches the user. Values come from ${family.source}.');
      });
    }

    test('and Arabic has them too, with no Latin letters', () {
      Get.locale = const Locale('ar', 'SA');
      final untranslated = <String>[];
      for (final family in _families) {
        for (final value in family.values) {
          final key = '${family.prefix}$value';
          final label = arabic[key];
          if (label == null || label == key || RegExp(r'[A-Za-z]').hasMatch(label)) {
            untranslated.add('$key -> ${label ?? "(absent)"}');
          }
        }
      }
      expect(untranslated, isEmpty,
          reason: 'The Arabic interface must contain no English (project rule).');
    });
  });

  group('no _en entry is its own key', () {
    test('a snake_case key never maps to itself anywhere in _en', () {
      // Broader than the families above: catches the same defect in any key,
      // including ones reached by a call site nobody has audited yet.
      final token = RegExp(r'^[a-z0-9]+(_[a-z0-9]+)+$');
      final offenders = english.entries
          .where((e) => e.value == e.key && token.hasMatch(e.key))
          .map((e) => e.key)
          .toList();

      expect(offenders, isEmpty,
          reason: 'These render as raw machine tokens in English, Sorani and '
              'Badini (the Kurdish buckets merge over English).');
    });
  });
}
