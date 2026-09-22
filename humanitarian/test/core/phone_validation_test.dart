// phone_validation_test.dart — the one phone rule the app applies everywhere.
//
// Client feedback round 1, two findings:
//
//   1. The registration form's profile phone1 / phone2 fields had NO validator
//      at all — only a keyboardType. Anything typed was posted. The rule the
//      sign-in screen already applied lived privately inside login.dart's
//      State, so it could not be reused; it now lives here.
//   2. The app accepted 4-14 digits for a non-Iraqi number while the server
//      requires 7-15 total (backend/internal/auth/phone.go). A 4-digit number
//      passed the form and was then refused by the server — the app must never
//      accept what the server will reject.
//
// The Iraq rule is unchanged and deliberately exact: 10 NSN digits, or 11 with
// the leading trunk 0, matching auth.NormalizePhone's Iraq branch.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/phone_format.dart';

void main() {
  group('Iraq (+964) — exact NSN length', () {
    test('accepts 10 digits, and 11 when it starts with the trunk 0', () {
      expect(phoneValidationMessage('7508582031', dialCode: '964'), isNull);
      expect(phoneValidationMessage('07508582031', dialCode: '964'), isNull);
      // The live formatter groups digits with spaces as the user types.
      expect(phoneValidationMessage('0750 858 2031', dialCode: '964'), isNull);
    });

    test('rejects a number one digit short — the OPOS #25268 shape', () {
      expect(phoneValidationMessage('773800028', dialCode: '964'), isNotNull);
    });

    test('rejects 11 digits that do not start with 0', () {
      expect(phoneValidationMessage('75085820311', dialCode: '964'), isNotNull);
    });
  });

  group('other countries — must not accept what the server rejects', () {
    test('rejects fewer than 7 digits', () {
      // The server floor is 7 total digits. 4, 5 and 6 used to pass here and
      // were then refused by the backend.
      expect(phoneValidationMessage('2025', dialCode: '1'), isNotNull);
      expect(phoneValidationMessage('20255', dialCode: '1'), isNotNull);
      expect(phoneValidationMessage('202555', dialCode: '1'), isNotNull);
    });

    test('accepts 7 through 14 digits', () {
      expect(phoneValidationMessage('2025550', dialCode: '1'), isNull);
      expect(phoneValidationMessage('20255501820000', dialCode: '1'), isNull);
    });

    test('rejects more than 14 digits', () {
      expect(
        phoneValidationMessage('202555018200001', dialCode: '1'),
        isNotNull,
      );
    });
  });

  group('empty input', () {
    test('is a message, not null — the sign-in field is required', () {
      expect(phoneValidationMessage('', dialCode: '964'), isNotNull);
      expect(phoneValidationMessage(null, dialCode: '964'), isNotNull);
      expect(phoneValidationMessage('   ', dialCode: '964'), isNotNull);
    });

    test('is allowed when the caller says the field is optional', () {
      // The registration profile's phone1 / phone2 sit behind per-field rules
      // and are commonly left blank; blank must not be reported as malformed.
      expect(
        phoneValidationMessage('', dialCode: '964', required: false),
        isNull,
      );
      expect(
        phoneValidationMessage(null, dialCode: '964', required: false),
        isNull,
      );
      expect(
        phoneValidationMessage('   ', dialCode: '964', required: false),
        isNull,
      );
    });

    test('still checks a value that IS typed into an optional field', () {
      expect(
        phoneValidationMessage('123', dialCode: '964', required: false),
        isNotNull,
      );
    });
  });
}
