// Pins how a chat-group sender label reads in the member's language —
// OPOS #26419.
//
// THE BUG
// The server writes a masked group's auto-generated aliases in English when
// the group is created ("Donor 1", "Beneficiary 2", "Volunteer 3",
// "Member 4" — autoLabel in backend/internal/chatgroups/chatgroups.go), labels
// every staff message with the literal "Support", and falls back to a bare
// "Member" when a sender has no label or name (ListMessagesForMember in
// chatgroups_reads.go). The bubble drew those verbatim, so an Arabic member
// read "Support" and "Donor 1" in English inside an Arabic chat.
//
// WHAT IS PINNED
//   1. Exactly the words the server generates are translated, in English and
//      in Arabic, with the number kept and formatted for the reader.
//   2. Everything else — a label staff typed, a team member's real name, and
//      near-misses of the generated shapes — is shown exactly as sent.
//
// The expected copy is written out in full rather than read from the
// translation map: a test that looked the value up would pass whatever the
// value said.
//
// ON DIGITS: the Arabic rows expect ASCII digits ("مانح 1"). That is what
// intl 0.20.2 prints for `ar` — the same digits the bubble's own time line
// ("14 سبتمبر 9:05 ص") and the rest of the app show. If a future intl prints
// Arabic-Indic digits for `ar`, these rows fail on purpose, so the change is a
// decision rather than a surprise.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/chatgroups/utils/chat_group_sender_label.dart';

/// Labels the server never generates. Each must come back exactly as sent.
const _notGenerated = [
  "Ahmad's family", // a label staff typed
  'أحمد علي', // a team member's real name
  'Donor', // a generated noun with no number
  'Donor 1a', // not a plain number
  'donor 1', // lower case: autoLabel always capitalises the noun
  'Donor 0', // numbering starts at 1
  'Donor 01', // the server never pads the number
  ' Donor 1', // surrounding space is not the server's shape
  'Donor  1', // two spaces
  'Donors 1', // not one of the server's nouns
  'Staff 1', // staff are never shown with a numbered label
  'Supporter', // only the exact word "Support"
  'support', // lower case
  'Support 1', // "Support" never carries a number
  '', // empty
];

void main() {
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(AppTranslations().keys);
  });
  tearDown(Get.reset);

  group('English', () {
    setUp(() => Get.updateLocale(const Locale('en', 'US')));

    test('a staff message reads "Support"', () {
      expect(localizedSenderLabel('Support'), 'Support');
    });

    test('the bare fallback reads "Member"', () {
      expect(localizedSenderLabel('Member'), 'Member');
    });

    test('generated aliases read exactly as the server wrote them', () {
      // A deliberate decision (2026-09-15): English keeps the server's own
      // words, so the alias matches the dashboard and push notifications —
      // not the app's "Grantor" / "Eligible Recipient" role vocabulary.
      expect(localizedSenderLabel('Donor 1'), 'Donor 1');
      expect(localizedSenderLabel('Beneficiary 12'), 'Beneficiary 12');
      expect(localizedSenderLabel('Volunteer 3'), 'Volunteer 3');
      expect(localizedSenderLabel('Member 2'), 'Member 2');
    });

    for (final label in _notGenerated) {
      test('"$label" is shown exactly as sent', () {
        expect(localizedSenderLabel(label), label);
      });
    }
  });

  group('Arabic', () {
    setUp(() => Get.updateLocale(const Locale('ar', 'SA')));

    test('a staff message reads فريق الدعم, not "Support"', () {
      // Not a bare الدعم: that is already Kafala (TERMINOLOGY.md T10).
      expect(localizedSenderLabel('Support'), 'فريق الدعم');
    });

    test('the bare fallback reads عضو, not "Member"', () {
      expect(localizedSenderLabel('Member'), 'عضو');
    });

    test('generated aliases use the app\'s Arabic role nouns', () {
      expect(localizedSenderLabel('Donor 1'), 'مانح 1');
      expect(localizedSenderLabel('Beneficiary 12'), 'مستحق 12');
      expect(localizedSenderLabel('Volunteer 3'), 'متطوع 3');
      expect(localizedSenderLabel('Member 2'), 'عضو 2');
    });

    for (final label in _notGenerated) {
      test('"$label" is shown exactly as sent', () {
        expect(localizedSenderLabel(label), label);
      });
    }

    test('a number too large to parse is shown as sent, not a crash', () {
      const label = 'Donor 123456789012345678901234567890';
      expect(localizedSenderLabel(label), label);
    });
  });

  // Both Kurdish locales ride on `ar` with a region (AppLocaleService:
  // kurdishSorani = ar_IQ, kurdishBadini = ar_TR). AppTranslations merges
  // English underneath each Kurdish map, so a key with no Kurdish value must
  // give the reader the ENGLISH alias — never the Arabic one that GetX's
  // language-code bucket (`ar`) would otherwise hand them.
  //
  // The role nouns carry machine-drafted Kurdish since 2026-09-16. "Support"
  // and the bare/numbered "Member" deliberately do NOT: OPOS #26468 flagged
  // those three terms and they are waiting on a native translator, so they are
  // still expected to fall back to English here. If someone translates them,
  // these rows fail on purpose.
  const kurdishRoleNouns = [
    (Locale('ar', 'IQ'), ['بەخشەر 1', 'وەرگری شایستە 12']),
    (Locale('ar', 'TR'), ['بەخشەر 1', 'وەرگرێ شایستە 12']),
  ];
  for (final (kurdish, expected) in kurdishRoleNouns) {
    group('Kurdish ($kurdish)', () {
      setUp(() => Get.updateLocale(kurdish));

      test('the flagged terms still fall back to English, not Arabic', () {
        expect(localizedSenderLabel('Support'), 'Support');
        expect(localizedSenderLabel('Member'), 'Member');
        expect(localizedSenderLabel('Member 2'), 'Member 2');
      });

      test('the role nouns read in Kurdish, with the number kept', () {
        expect(localizedSenderLabel('Donor 1'), expected[0]);
        expect(localizedSenderLabel('Beneficiary 12'), expected[1]);
      });
    });
  }

  // The Kurdish rows above never reach the missing-translation branch: the
  // English merged under each Kurdish map always answers. This group does, by
  // loading no translations at all, where GetX echoes the KEY back.
  group('with no translation for the key', () {
    setUp(() {
      Get.clearTranslations();
      Get.updateLocale(const Locale('ar', 'SA'));
    });

    test('the server label is shown, never the key name', () {
      expect(localizedSenderLabel('Support'), 'Support');
      expect(localizedSenderLabel('Member'), 'Member');
      expect(localizedSenderLabel('Donor 1'), 'Donor 1');
    });
  });
}
