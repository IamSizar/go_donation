// Pins that a donor's Facebook / Instagram / Telegram links actually land
// somewhere (L2).
//
// WHY THIS FILE EXISTS
// L2 asks the donor registration form for "optional Facebook / Instagram /
// Telegram links". Two separate things were wrong.
//
// 1. The form never rendered the boxes for a donor. The Social Media Accounts
//    panel is inside the `_roleId == 2` branch, and the volunteer form has its
//    own; role 1 had none.
//
// 2. Adding boxes alone would have been WORSE than leaving them out, because
//    POST /api/registration/submit drops them for a donor. The handler only
//    persists social_facebook/instagram/telegram inside its `RoleID == 2`
//    branch (backend/internal/handlers/registration.go:224 →
//    SetRecipientHealthDetails), so a donor's links are parsed off the wire and
//    thrown away. Three inputs that silently discard what you type are a lying
//    form, not a fixed one.
//
// POST /api/profile/privacy-extras writes THE SAME user_profiles columns with
// no role gate at all (backend/internal/users/users.go:201-218) — it is where
// the Privacy Settings screen already sends these three values. So the donor's
// links are routed there and land in exactly the same columns a recipient's do.
//
// THE DANGEROUS PART, AND WHY THE FIRST TEST BELOW EXISTS
// That endpoint also writes display_name_mode. field_privacy_screen.dart
// records what happens when it is written blind: posting a default 'real' over
// a user who had chosen an alias un-anonymises them, server-side, silently.
// So the save READS the current extras first and echoes back whatever it
// found. If the read fails, nothing is written at all.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';

import '../support/fake_http.dart';

const _registrationForm = 'lib/modules/auth/screens/registration_form.dart';

String _readSource(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// A user who had already chosen to appear under a pseudonym.
String _extrasBody({String mode = 'alias', String alias = 'Abu Ali'}) =>
    jsonEncode({
      'success': true,
      'extras': {
        'display_name_mode': mode,
        'alias_name': alias,
        'social_facebook': '',
        'social_instagram': '',
        'social_telegram': '',
      },
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  group('saving a donor\'s social links', () {
    test('it preserves a pseudonym instead of publishing the real name', () async {
      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _extrasBody(mode: 'alias', alias: 'Abu Ali'),
      );

      final saved = await withHttp(
        recorder,
        () => saveRegistrationSocialLinks(
          facebook: 'https://facebook.com/someone',
          instagram: '',
          telegram: '',
        ),
      );

      expect(saved, isTrue);
      final posted = recorder.requestBodies
          .map((b) => jsonDecode(b) as Map<String, dynamic>)
          .where((b) => b.containsKey('social_facebook'))
          .toList();
      expect(
        posted,
        hasLength(1),
        reason: 'exactly one write, carrying the links',
      );
      expect(
        posted.single['display_name_mode'],
        'alias',
        reason:
            'writing the default "real" here would un-anonymise a donor who '
            'had chosen a pseudonym — the exact disclosure field_privacy_'
            'screen.dart guards against at _loadExtras()',
      );
      expect(posted.single['alias_name'], 'Abu Ali');
      expect(posted.single['social_facebook'], 'https://facebook.com/someone');
    });

    test('a failed read writes nothing at all', () async {
      final recorder = FakeHttpOverrides(HttpBehaviour.serverError);

      final saved = await withHttp(
        recorder,
        () => saveRegistrationSocialLinks(
          facebook: 'https://facebook.com/someone',
          instagram: '',
          telegram: '',
        ),
      );

      expect(
        saved,
        isFalse,
        reason:
            'the caller has to be able to tell the user their links did not '
            'save — silently returning true is how the photo upload bug '
            'happened',
      );
      expect(
        recorder.requestBodies.any(
          (b) => b.contains('display_name_mode'),
        ),
        isFalse,
        reason:
            'not knowing the current display-name choice means not writing '
            'one; guessing is what discloses a real name',
      );
    });

    test('an unreachable server is reported, not swallowed', () async {
      final saved = await withHttp(
        FakeHttpOverrides(HttpBehaviour.networkError),
        () => saveRegistrationSocialLinks(
          facebook: 'https://facebook.com/someone',
          instagram: '',
          telegram: '',
        ),
      );

      expect(saved, isFalse);
    });

    test('three empty boxes cost no request', () async {
      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _extrasBody(),
      );

      final saved = await withHttp(
        recorder,
        () => saveRegistrationSocialLinks(
          facebook: '',
          instagram: '  ',
          telegram: '',
        ),
      );

      expect(saved, isTrue, reason: 'nothing to save is not a failure');
      expect(
        recorder.requestBodies,
        isEmpty,
        reason:
            'the links are optional; leaving all three blank must not fire a '
            'write, let alone one that rewrites display_name_mode',
      );
    });
  });

  group('the donor form offers the three boxes and uses the working path', () {
    test('the donor branch renders social link fields', () {
      final src = _readSource(_registrationForm);
      for (final rule in const [
        'grantor_social_facebook',
        'grantor_social_instagram',
        'grantor_social_telegram',
      ]) {
        expect(
          src.contains("'$rule'"),
          isTrue,
          reason:
              'L2 asks for optional Facebook / Instagram / Telegram links on '
              'the المانح form. Without $rule the panel is still recipient- '
              'and volunteer-only.',
        );
      }
    });

    test('it does not route the donor through the path that drops them', () {
      final src = _readSource(_registrationForm);
      expect(
        src.contains('saveRegistrationSocialLinks('),
        isTrue,
        reason:
            'the registration submit discards a donor\'s social links '
            '(handlers/registration.go gates them on RoleID == 2), so boxes '
            'wired only to submitRegistration would be three inputs that '
            'silently throw away what the user types',
      );
      expect(
        RegExp(r'socialFacebook: _valueOf\(\s*.grantor_social').hasMatch(src),
        isFalse,
        reason:
            'the registration body must not pretend to carry the donor\'s '
            'links — that field is only persisted for role 2',
      );
    });

    test('the failure message reads in Arabic, not English', () {
      // Rule: an Arabic screen shows no English. `.tr` returns the key when
      // the entry is missing, so a missing _ar value renders the sentence in
      // English to an Arabic reader.
      const key =
          'Your registration was saved, but your social links did not. You can add them from Privacy settings.';
      final ar = AppTranslations().keys['ar_SA']![key];
      expect(ar, isNotNull, reason: 'no Arabic entry for the L2 snackbar');
      expect(
        ar,
        isNot(key),
        reason: 'the Arabic entry is still the English sentence',
      );
    });
  });
}
