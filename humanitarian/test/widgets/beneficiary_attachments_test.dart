// Pins the documents the مستحق registration form asks for (L10).
//
// WHY THIS FILE EXISTS
// L10 lists the attachments an eligible applicant must be able to supply:
// "صورة شخصية، صورة البطاقة الوطنية، البطاقة التموينية / بطاقة السكن / الجواز
// (اختياري)، مستند التملك أو عقد الإيجار، التقارير الطبية لكل حالة مرضية، صور
// للمنزل (الواجهة الخارجية، داخل المنزل، خارج المنزل)".
//
// The middle group is three ALTERNATIVE proofs of identity and residence, and
// only the first of them was offered. بطاقة السكن and الجواز existed in the
// app — but only inside the VOLUNTEER block of the same file — so an applicant
// holding a residence card or a passport instead of a ration card had nowhere
// to put it, and the reviewer had nothing to check against.
//
// WHY THIS IS A SOURCE TEST
// The block under test is a `for` loop over a record literal 3,300 lines into a
// 4,800-line form that a widget test can only reach through role selection and
// several network calls. What is being pinned is which documents that literal
// LISTS, which is a property of the source — the same reasoning as
// city_subcategories_test and main_menu_button_test, both of which check the
// files that forgot to opt into something.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/localization/app_translations.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// The recipient "Attachments" panel only — from its section label to the
/// "Assets" panel that follows it. Scoping matters: the volunteer block in the
/// same file names the very rules this test is about, so an unscoped search
/// would pass while the recipient form stayed exactly as broken as it was.
String _recipientAttachmentsBlock() {
  final source = _read('lib/modules/auth/screens/registration_form.dart');
  const start = "'reg_recipient_attachments_section'";
  const end = "'reg_recipient_assets_section'";
  final from = source.indexOf(start);
  final to = source.indexOf(end);
  if (from < 0 || to < 0 || to <= from) {
    fail(
      'the recipient attachments panel could not be located — it is now '
      'bounded by different markers, so this test needs updating',
    );
  }
  return source.substring(from, to);
}

void main() {
  group('the مستحق form asks for every document L10 lists', () {
    final block = _recipientAttachmentsBlock();

    /// Every attachment the client's list names, with the rule id the form
    /// files it under.
    const required = <String, String>{
      'recipient_personal_photo': 'صورة شخصية',
      'recipient_id_photo': 'صورة البطاقة الوطنية',
      'recipient_ration_card_photo': 'البطاقة التموينية',
      'recipient_residence_card_photo': 'بطاقة السكن',
      'recipient_passport_photo': 'الجواز',
      'recipient_property_proof_photo': 'مستند التملك أو عقد الإيجار',
      'recipient_medical_report_photo': 'التقارير الطبية',
      'recipient_house_facade_photo': 'صورة المنزل — الواجهة الخارجية',
      'recipient_house_inside_photo': 'صورة المنزل — من الداخل',
      'recipient_house_outside_photo': 'صورة المنزل — من الخارج',
    };

    for (final entry in required.entries) {
      test('${entry.value} has a tile', () {
        expect(
          block.contains("'${entry.key}'"),
          isTrue,
          reason:
              '${entry.key} is missing from the recipient attachments panel. '
              'It may exist in the volunteer block — that does not help an '
              'eligible applicant, which is the whole of L10.',
        );
      });
    }

    test('the two that were missing are not borrowed volunteer RULE ids', () {
      // Filing a recipient's residence card under `volunteer_residence_card_
      // photo` would look identical on screen and be wrong in the one place it
      // matters: an admin hiding the field for volunteers would hide it for
      // eligible applicants too.
      expect(block.contains("'volunteer_residence_card_photo'"), isFalse);
      expect(block.contains("'volunteer_passport_photo'"), isFalse);
    });
  });

  group('the two new tiles reach the server and read in every language', () {
    test('both are already carried by the upload call', () {
      // No new upload plumbing was written for L10, and this pins why: the
      // registration photo upload has always accepted these two fields, and
      // the Go handler that stores them (SetVolunteerAttachments) updates
      // user_profiles by user_id with no role condition. Only the form never
      // offered them.
      final api = _read('lib/api/registration_api.dart');
      expect(
        api.contains("'residence_card_photo': residenceCardPhotoPath"),
        isTrue,
      );
      expect(api.contains("'passport_photo': passportPhotoPath"), isTrue);

      final form = _read('lib/modules/auth/screens/registration_form.dart');
      expect(
        form.contains('residenceCardPhotoPath: _residenceCardPhotoPath'),
        isTrue,
      );
      expect(form.contains('passportPhotoPath: _passportPhotoPath'), isTrue);
    });

    test('the reused labels really do carry all four languages', () {
      // The reason these two tiles cost no new Kurdish: the labels already
      // exist, translated, under volunteer key names whose VALUES are
      // role-neutral. If someone later "tidies" them into recipient-specific
      // keys, this test says what that costs.
      final translations = AppTranslations().keys;
      const labels = [
        'reg_volunteer_residence_card_photo',
        'reg_volunteer_passport_photo',
      ];
      for (final locale in ['en_US', 'ar_SA', 'ar_IQ', 'ar_TR']) {
        for (final label in labels) {
          final value = translations[locale]![label];
          expect(value, isNotNull, reason: '$label missing in $locale');
          expect(value!.trim(), isNotEmpty, reason: '$label empty in $locale');
        }
      }
      // And the Arabic must not have leaked English.
      for (final label in labels) {
        expect(
          RegExp(r'[A-Za-z]').hasMatch(translations['ar_SA']![label]!),
          isFalse,
        );
      }
    });
  });
}
