// Pins that entering as a guest asks for NOTHING and posts nothing but the
// generated credentials.
//
// WHY THIS FILE EXISTS
// Guest entry has been narrowed twice. It first collected a username and a
// password — two secrets a browsing guest invents once and never uses again —
// then just a name (J1), and now nothing at all: "Continue as guest" is a
// single tap. The credentials the server still requires are generated on the
// device (api/guest_credentials.dart).
//
// THE PART THAT NEEDS PINNING
// Not "is the sheet gone" — that is visible. What a test has to hold is:
//   • the generated username satisfies the server's rule, because a malformed
//     one is a 400 the user can neither see nor fix;
//   • nothing but username and password is posted — no name is invented on
//     the user's behalf;
//   • a taken username RETRIES rather than surfacing, since the user did not
//     choose it and cannot do anything about it;
//   • the credentials are remembered, so a returning guest is the SAME guest.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';

import '../support/fake_http.dart';

/// A successful guest register response, shaped like the real one.
const _guestOk =
    '{"status":"success","user_id":42,"registration_status":'
    '"approved","account":{},"access_token":"t","token_type":"Bearer"}';

/// The taken-username failure. The user never sees this — the app retries.
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

void main() {
  // registerGuestAccount touches SharedPreferences and a platform channel, so
  // the binding has to exist even though nothing here pumps a widget.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('the guest is asked for nothing', () {
    test('the request carries credentials and nothing else', () async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);

      await withHttp(recorder, () async {
        final result = await registerGuestAccount();
        expect(result.ok, isTrue);
      });

      final posts = _guestPosts(recorder);
      expect(posts, hasLength(1));
      expect(
        posts.single.keys.toSet(),
        {'username', 'password'},
        reason:
            'the sheet is gone: there is no name to send, and inventing one '
            'would put a made-up string in front of staff',
      );
    });

    test('the generated username satisfies the server rule', () async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);

      await withHttp(recorder, () async => registerGuestAccount());

      final posts = _guestPosts(recorder);
      expect(posts, hasLength(1));
      final username = posts.single['username'] as String;
      expect(
        _serverUsernameRule.hasMatch(username),
        isTrue,
        reason:
            'a generated username that misses guestUsernameRE is a 400 the '
            'user can neither see nor fix: got "$username"',
      );
      expect(
        (posts.single['password'] as String).length,
        greaterThanOrEqualTo(6),
        reason: "the server's floor",
      );
    });
  });

  group('the credentials are generated, not asked for', () {
    test('a taken username is retried, never shown', () async {
      // The user did not choose the name, so a collision is the app's problem.
      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _usernameTaken,
      );

      await withHttp(recorder, () async => registerGuestAccount());

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

    test('the credentials are remembered for this device', () async {
      // So a guest whose session ends gets back into the SAME account rather
      // than silently becoming a different person.
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _guestOk);

      await withHttp(recorder, () async => registerGuestAccount());

      final saved = sharedPreferences.getString(kGuestUsernamePrefsKey);
      expect(saved, isNotNull);
      expect(saved, _guestPosts(recorder).single['username']);
      expect(sharedPreferences.getString(kGuestPasswordPrefsKey), isNotNull);
    });

    test('a failure leaves no credentials behind', () async {
      // A remembered pair for an account that was never created would send a
      // returning guest to guest/login with credentials the server rejects.
      final recorder = FakeHttpOverrides(HttpBehaviour.serverError);

      await withHttp(recorder, () async {
        final result = await registerGuestAccount();
        expect(result.ok, isFalse);
      });

      expect(sharedPreferences.getString(kGuestUsernamePrefsKey), isNull);
      expect(sharedPreferences.getString(kGuestPasswordPrefsKey), isNull);
      expect(isGuestMode(), isFalse);
    });
  });
}
