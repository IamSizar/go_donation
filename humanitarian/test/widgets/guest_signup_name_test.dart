// Pins that the guest sign-up sheet collects a name, and that the name it
// collects actually reaches the server (J1).
//
// WHY THIS FILE EXISTS
// J1 asks for an "الاسم" box on the guest sign-up sheet. The box could not be
// added honestly until backend 792ded3, because `InsertGuest` wrote a `users`
// row and no `user_profiles` row at all — every `UPDATE user_profiles … WHERE
// user_id` was a silent no-op for a guest, so a name posted there had nowhere
// to land. That commit creates both rows and teaches
// POST /api/auth/guest/register to read the name from either `full_name` (the
// canonical key across this API) or `name`.
//
// THE PART THAT NEEDS PINNING
// Not "is there a third text box" — that is visible. What a test has to hold
// is WHICH KEY the box posts under and ON WHICH CALL. Read the handlers:
//
//   • handlers/auth.go GuestRegister  → reads req.guestFullName() and passes
//     it to InsertGuest. The name is stored here and only here.
//   • handlers/auth.go GuestLogin     → parses the same struct and NEVER
//     reads the name. Sending one would be posting a value the server drops.
//
// So the sheet's primary action (register) must carry the name, and its
// "log in instead" recovery path must not pretend to. Both directions are
// asserted below, because a box that posts under a key nobody reads looks
// exactly like a box that works.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/auth/screens/login.dart';

import '../support/fake_http.dart';

/// A successful guest register/login response, shaped like the real one.
const _guestOk = '{"status":"success","user_id":42,"registration_status":'
    '"approved","account":{},"access_token":"t","token_type":"Bearer"}';

/// The taken-username failure that reveals the "log in instead" button.
const _usernameTaken =
    '{"status":"error","error":"That username is taken.","code":'
    '"username_taken"}';

Widget _sheet() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const Scaffold(body: GuestAccessSheet()),
);

/// Every JSON body posted to the guest endpoints, decoded.
///
/// The analytics logger POSTs to /api/events on the same fake client, so the
/// recorder holds more than the auth call; filtering on `username` keeps this
/// pointed at the request under test.
List<Map<String, dynamic>> _guestPosts(FakeHttpOverrides recorder) => recorder
    .requestBodies
    .map((b) {
      try {
        final decoded = jsonDecode(b);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        // A non-JSON body is not one of ours; skipping it is the point of
        // the filter, not a swallowed failure.
        return null;
      }
    })
    .whereType<Map<String, dynamic>>()
    .where((b) => b.containsKey('username'))
    .toList();

Future<void> _fillSheet(
  WidgetTester tester, {
  required String name,
  String username = 'zaid_guest',
  String password = 'secret123',
}) async {
  await tester.enterText(find.byKey(const Key('guest_full_name_field')), name);
  await tester.enterText(
    find.byKey(const Key('guest_username_field')),
    username,
  );
  await tester.enterText(
    find.byKey(const Key('guest_password_field')),
    password,
  );
}

/// Taps [button] and lets the request finish.
///
/// Deliberately NOT `pumpAndSettle`: the in-button spinner is a
/// CircularProgressIndicator, which never stops animating, so settling waits
/// for a frame that by design never comes.
Future<void> _tapAndLetItFinish(WidgetTester tester, Key button) async {
  await tester.tap(find.byKey(button));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the sheet asks for a name', () {
    testWidgets('a name box is on the sign-up sheet', (tester) async {
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('guest_full_name_field')),
        findsOneWidget,
        reason: 'J1 — the client asked for an الاسم box on this sheet',
      );
      // Labelled with a key that exists in all four locales (pf_full_name),
      // so the Arabic sheet shows Arabic rather than a bare English word.
      expect(find.text('pf_full_name'.tr), findsWidgets);
    });

    testWidgets('an over-long name is refused before it is sent', (
      tester,
    ) async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        // 201 runes — one past user_profiles.full_name VARCHAR(200), which the
        // handler rejects with a 400. The client refuses first so the user is
        // told at the field instead of by a round trip.
        await _fillSheet(tester, name: 'ز' * 201);
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      expect(
        _guestPosts(recorder),
        isEmpty,
        reason: 'a doomed request must never fire',
      );
    });
  });

  group('the name reaches the server', () {
    testWidgets('registering posts it under full_name', (tester) async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        await _fillSheet(tester, name: '  زيد العراقي  ');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      final posts = _guestPosts(recorder);
      expect(posts, hasLength(1));
      expect(
        posts.single['full_name'],
        'زيد العراقي',
        reason:
            'GuestRegister reads guestFullName(), which prefers full_name; '
            'and it trims, so the client sends trimmed rather than relying '
            'on it',
      );
    });

    testWidgets('an empty name is left out rather than sent blank', (
      tester,
    ) async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        await _fillSheet(tester, name: '   ');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      final posts = _guestPosts(recorder);
      expect(posts, hasLength(1));
      expect(
        posts.single.containsKey('full_name'),
        isFalse,
        reason:
            'the box is optional; an omitted key is what "no name given" '
            'looks like on the wire, and the handler treats it as valid',
      );
    });

    testWidgets('logging in does not pretend the name is used', (tester) async {
      // First call fails with username_taken, revealing the login button.
      final taken = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _usernameTaken,
      );
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(taken, () async {
        await _fillSheet(tester, name: 'زيد');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      final login = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await withHttp(login, () async {
        await _tapAndLetItFinish(
          tester,
          const Key('guest_login_instead_button'),
        );
      });

      final posts = _guestPosts(login);
      expect(posts, hasLength(1));
      expect(
        posts.single.containsKey('full_name'),
        isFalse,
        reason:
            'GuestLogin parses the name and never reads it — sending one '
            'would be a field the user believes they changed and did not',
      );
    });
  });
}
