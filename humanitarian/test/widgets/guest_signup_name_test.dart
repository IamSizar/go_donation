// Pins that the guest sheet asks for a NAME and nothing else, and that the
// name reaches the server (J1).
//
// WHY THIS FILE EXISTS
// J1 asks for an "الاسم" box on the guest sign-up sheet. The box could not be
// added honestly until backend 792ded3, because `InsertGuest` wrote a `users`
// row and no `user_profiles` row at all — every `UPDATE user_profiles … WHERE
// user_id` was a silent no-op for a guest, so a name posted there had nowhere
// to land.
//
// WHAT CHANGED, and why these tests were rewritten
// The sheet used to collect a username and a password too — two secrets a
// browsing guest invents once and never uses again. The owner asked for a
// name and nothing else. The server still REQUIRES both (guestUsernameRE is
// ^[A-Za-z0-9_]{3,32}$ and the password floor is 6), so the app generates
// them instead of asking.
//
// THE PART THAT NEEDS PINNING
// Not "is there a text box" — that is visible. What a test has to hold is:
//   • the generated username satisfies the server's rule, because a
//     malformed one is a 400 the user can neither see nor fix;
//   • the typed name still posts under `full_name`, the key GuestRegister
//     actually reads;
//   • a taken username RETRIES rather than surfacing, since the user did not
//     choose it and cannot do anything about it;
//   • nothing on the sheet asks for a credential any more.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/auth/screens/login.dart';

import '../support/fake_http.dart';

/// A successful guest register/login response, shaped like the real one.
const _guestOk =
    '{"status":"success","user_id":42,"registration_status":'
    '"approved","account":{},"access_token":"t","token_type":"Bearer"}';

/// The taken-username failure. The user never sees this now — the app retries.
const _usernameTaken =
    '{"status":"error","error":"That username is taken.","code":'
    '"username_taken"}';

/// The server's own rule, copied from handlers/auth.go guestUsernameRE. A
/// generated name that misses it is a 400 nobody can see or fix.
final _serverUsernameRule = RegExp(r'^[A-Za-z0-9_]{3,32}$');

/// The session token is written through flutter_secure_storage, a platform
/// channel with no implementation in a VM test. Unmocked it throws, and
/// _guestAuthCall catches everything — so registration would silently report
/// failure and every assertion about what happens AFTER a successful register
/// would quietly test nothing. Answering null is what success looks like.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

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

/// The sheet has ONE field now.
Future<void> _fillSheet(WidgetTester tester, {required String name}) =>
    tester.enterText(find.byKey(const Key('guest_full_name_field')), name);

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    Get.reset();
  });

  group('the sheet asks for a name, and only a name', () {
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

    testWidgets('no credential is asked for', (tester) async {
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guest_username_field')), findsNothing);
      expect(find.byKey(const Key('guest_password_field')), findsNothing);
      expect(
        find.byType(TextFormField),
        findsOneWidget,
        reason: 'the owner asked for a name and nothing else',
      );
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

    testWidgets('an empty name is refused', (tester) async {
      // It used to be optional, because the sheet promised "just a username
      // and password". That promise is gone: the name is now the only thing
      // asked for, and a nameless guest is the blank J1 was raised about.
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        await _fillSheet(tester, name: '   ');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      expect(_guestPosts(recorder), isEmpty);
      expect(find.text('guest_full_name_required'.tr), findsOneWidget);
    });
  });

  group('the credentials are generated, not asked for', () {
    testWidgets('the generated username satisfies the server rule', (
      tester,
    ) async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        await _fillSheet(tester, name: 'زيد');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      final posts = _guestPosts(recorder);
      expect(posts, hasLength(1));
      final username = posts.single['username'] as String;
      expect(
        _serverUsernameRule.hasMatch(username),
        isTrue,
        reason:
            'a generated username that misses guestUsernameRE is a 400 the '
            'user can neither see nor fix: got "\$username"',
      );
      expect(
        (posts.single['password'] as String).length,
        greaterThanOrEqualTo(6),
        reason: "the server's floor",
      );
    });

    testWidgets('a taken username is retried, never shown', (tester) async {
      // The user did not choose the name, so a collision is the app's problem.
      // Previously this surfaced as an error plus a "log in instead" button.
      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _usernameTaken,
      );
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        await _fillSheet(tester, name: 'زيد');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      final posts = _guestPosts(recorder);
      expect(
        posts.length,
        greaterThan(1),
        reason: 'a collision must be retried rather than reported',
      );
      final tried = posts.map((p) => p['username']).toSet();
      expect(
        tried.length,
        posts.length,
        reason: 'retrying with the SAME username would fail identically',
      );
    });

    testWidgets('the credentials are remembered for this device', (
      tester,
    ) async {
      // Preserves what the user used to be able to do by retyping the pair
      // they chose: get back into the SAME guest account rather than silently
      // becoming a different person.
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();

      await withHttp(recorder, () async {
        await _fillSheet(tester, name: 'زيد');
        await _tapAndLetItFinish(tester, const Key('guest_submit_button'));
      });

      // The prefs write is awaited inside registerGuestAccount, but it lands
      // in a later microtask than the tap's own frames — pump until it does.
      await tester.pump(const Duration(milliseconds: 200));

      final saved = sharedPreferences.getString(kGuestUsernamePrefsKey);
      expect(saved, isNotNull);
      expect(saved, _guestPosts(recorder).single['username']);
      expect(sharedPreferences.getString(kGuestPasswordPrefsKey), isNotNull);
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
  });
}
