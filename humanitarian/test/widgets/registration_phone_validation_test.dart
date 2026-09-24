// Every profile phone field on the registration form is validated.
//
// WHY THIS FILE EXISTS
// Client feedback round 1: the profile's phone1 / phone2 fields carried a
// keyboardType and nothing else — no validator, no length limit. Whatever was
// typed was posted, and the server stored it verbatim (that half is fixed in
// backend/internal/users/registration.go). The rule the sign-in screen already
// applied was private to login.dart's State, so there was nothing to reuse;
// it now lives in core/phone_format.dart as phoneValidationMessage, tested
// directly in test/core/phone_validation_test.dart.
//
// WHY THIS IS A SOURCE TEST
// The same two controllers are bound in SIX places across a 4,800-line form —
// the grantor panel, the recipient panel, and a generic record-driven loop in
// the volunteer panel — each reachable only through role selection and several
// network calls. What is pinned is that no binding is left unvalidated, which
// is a property of the source. Same reasoning as beneficiary_attachments_test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _formPath = 'lib/modules/auth/screens/registration_form.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// The source of the `..._unlessHidden('<ruleKey>', [ ... ])` block, which is
/// how the grantor and recipient panels declare one field each.
///
/// Scoped rather than searched globally: the four phone blocks are textually
/// near-identical (the recipient's phone2 even reuses the grantor's hint key),
/// so an unscoped search would let one block's validator vouch for another's.
String _fieldBlock(String source, String ruleKey) {
  final marker = "..._unlessHidden('$ruleKey', [";
  final start = source.indexOf(marker);
  if (start < 0) {
    fail(
      "the '$ruleKey' field is no longer declared with _unlessHidden — "
      'this test needs re-aiming, not deleting',
    );
  }
  final end = source.indexOf('\n                              ]),', start);
  if (end < 0) fail("could not find the end of the '$ruleKey' block");
  return source.substring(start, end);
}

/// One entry of the volunteer panel's record list, which drives a shared
/// TextFormField builder rather than declaring its own.
String _volunteerRecord(String source, String ruleKey) {
  final marker = "rule: '$ruleKey',";
  final start = source.indexOf(marker);
  if (start < 0) {
    fail(
      "the '$ruleKey' entry is gone from the volunteer contact list — "
      'this test needs re-aiming, not deleting',
    );
  }
  final end = source.indexOf(
    '\n                                        ),',
    start,
  );
  if (end < 0) fail("could not find the end of the '$ruleKey' record");
  return source.substring(start, end);
}

void main() {
  final source = _read(_formPath);

  group('every profile phone field runs the shared phone rule', () {
    // The grantor and recipient panels: one TextFormField per block.
    for (final ruleKey in const [
      'grantor_phone1',
      'grantor_phone2',
      'recipient_phone1',
      'recipient_phone2',
    ]) {
      test(ruleKey, () {
        final block = _fieldBlock(source, ruleKey);
        expect(
          block.contains('TextFormField('),
          isTrue,
          reason: '$ruleKey no longer renders a TextFormField',
        );
        expect(
          block.contains('validator: _profilePhoneMessage'),
          isTrue,
          reason:
              '$ruleKey has no phone validator — anything typed there '
              'reaches the server unchecked',
        );
      });
    }

    // The volunteer panel: the validator travels through the record list into
    // the shared builder, so both halves have to be pinned.
    for (final ruleKey in const ['volunteer_phone1', 'volunteer_phone2']) {
      test(ruleKey, () {
        expect(
          _volunteerRecord(
            source,
            ruleKey,
          ).contains('validator: _profilePhoneMessage'),
          isTrue,
          reason: '$ruleKey carries no validator in the contact record list',
        );
      });
    }

    test('the volunteer builder actually applies the record validator', () {
      expect(
        source.contains('validator: ct.validator'),
        isTrue,
        reason:
            'the shared volunteer field builder drops ct.validator, so '
            'the entries above have no effect',
      );
    });
  });

  group('the shared rule is the only rule', () {
    test('the form imports core/phone_format.dart', () {
      expect(source.contains('core/phone_format.dart'), isTrue);
    });

    test('_profilePhoneMessage delegates to phoneValidationMessage', () {
      // A second, hand-rolled phone rule here would drift away from the
      // sign-in screen and from the server. There must be exactly one.
      final at = source.indexOf('String? _profilePhoneMessage(');
      expect(at, greaterThan(-1), reason: '_profilePhoneMessage is gone');
      final body = source.substring(at, at + 300);
      expect(body.contains('phoneValidationMessage('), isTrue);
      expect(
        body.contains("dialCode: '964'"),
        isTrue,
        reason:
            'these fields have no country picker and the server treats a '
            'bare local number as Iraqi',
      );
      expect(
        body.contains('required: false'),
        isTrue,
        reason:
            'both fields are optional; a blank one is not a malformed '
            'number',
      );
    });
  });
}
