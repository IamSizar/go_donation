// Pins what happens when the server stops accepting the session token.
//
// WHY THIS FILE EXISTS
// Nothing in the app treated a 401 on an authed request as "your session is
// over". Reproduced on main before writing anything: `grep -rn "401" lib/`
// found handling in three places and all three were about a SIGN-IN being
// refused — history_api's identity-code lookup, auth_controller, and
// controllers/login.dart. A 401 on an already signed-in screen fell through to
// `ModuleApi`'s generic non-2xx branch and became
// `Exception('Request failed (401)')`.
//
// What that produced on a device: the token was gone, the app still rendered a
// fully signed-in UI from SharedPreferences nobody had cleared, and every
// authed screen showed its error card with a Retry button that could not
// succeed — retrying without a token returns 401 forever. The only exit was
// Logout, buried in the profile menu.
//
// THE FOUR THINGS WORTH PINNING
//   1. A 401 ends the session: the identity is gone and the user is routed to
//      sign-in. This is the fix.
//   2. It happens ONCE. A screen is many requests — the home tab runs a
//      summary, a campaigns load and a 10s poll — so a dead token produces a
//      burst of 401s in one frame. One sign-out per 401 would be a stack of
//      navigations and a stack of snackbars.
//   3. A 403 does NOT end the session. The two are different answers and this
//      app has already been burnt conflating them: the "self-heal" retry that
//      A16 removed fired on either, so an ordinary permission gate — approval
//      still pending, a guest restriction — signed working users out.
//   4. Sign-in cannot reach the handler. A wrong password legitimately returns
//      401 and must keep showing its own inline message. That holds because
//      the auth calls use a private Dio client and never touch ModuleApi, and
//      that separation is asserted here rather than assumed, because it is the
//      kind of thing a later refactor "tidies up" without noticing.
//
// HOW THE 401 IS INJECTED
// package:http talks to dart:io's HttpClient on the VM, so HttpOverrides can
// stand in a fake without the production code needing a seam for testing (the
// same harness the failure-signalling suite uses). The one seam that does
// exist is the navigation hook: routing needs a navigator and an overlay, and
// the thing under test is the DECISION, not the transition.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/session_expiry.dart';
import 'package:flutter_application_1/localization/app_translations.dart';

import '../support/fake_http.dart';

/// Any authed endpoint — the URL is irrelevant, the status is the whole test.
const String _anyAuthedUrl = 'https://example.test/api/notifications';

/// `logout()` clears the token through flutter_secure_storage, which is a
/// platform channel with no implementation in a VM test. Answering null is
/// what a successful delete looks like to the plugin.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// How many times the handler asked to be taken to sign-in.
  var routedToSignIn = 0;

  setUp(() async {
    Get.reset();
    routedToSignIn = 0;
    resetSessionExpiryForTest();
    sessionExpiryNavigator = () async => routedToSignIn++;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
    // A signed-in account: `id_user` is what makes the app render the
    // authenticated UI, so it is also what "there is a session to end" means.
    SharedPreferences.setMockInitialValues({
      'id_user': '7',
      'name_user': 'Sara',
      'role_id': '2',
    });
    sharedPreferences = await SharedPreferences.getInstance();
  });

  tearDown(() {
    resetSessionExpiryForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    Get.reset();
  });

  group('a 401 on an authed request ends the session', () {
    test('the identity is cleared and the user is sent to sign in', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, status: 401),
        () async {
          await expectLater(
            const ModuleApi().getItems(_anyAuthedUrl),
            throwsA(isA<Object>()),
          );
        },
      );

      expect(
        sharedPreferences.getString('id_user'),
        isNull,
        reason:
            'this pref is what kept a fully signed-in UI on screen after the '
            'token was gone; leaving it is the bug',
      );
      expect(sharedPreferences.getString('name_user'), isNull);
      expect(routedToSignIn, 1);
    });

    test(
      'the caller still gets its failure, so the screen still reacts',
      () async {
        await withHttp(
          FakeHttpOverrides(HttpBehaviour.ok, status: 401),
          () async {
            // The sign-out is a side effect, NOT a substitute for throwing: a
            // handler that swallowed the error would leave the calling screen
            // waiting on a future that never completes, which is the frozen
            // skeleton the request timeout exists to prevent.
            await expectLater(
              const ModuleApi().getObject(_anyAuthedUrl),
              throwsA(isA<Exception>()),
            );
          },
        );
      },
    );

    test('a write path signs out too, not just the reads', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, status: 401),
        () async {
          await expectLater(
            const ModuleApi().postJson(_anyAuthedUrl, const {'x': 1}),
            throwsA(isA<Object>()),
          );
        },
      );

      expect(routedToSignIn, 1);
      expect(sharedPreferences.getString('id_user'), isNull);
    });
  });

  group('it fires once, however many requests fail', () {
    test('a burst of simultaneous 401s produces one sign-out', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, status: 401),
        () async {
          // Five in flight at once, which is roughly what the home tab does on
          // open. Each is expected to fail; what is being asserted is that they
          // do not each start their own sign-out.
          await Future.wait([
            for (var i = 0; i < 5; i++)
              const ModuleApi()
                  .getItems(_anyAuthedUrl)
                  .catchError((Object _) => const <Map<String, dynamic>>[]),
          ]);
        },
      );

      expect(
        routedToSignIn,
        1,
        reason:
            'five navigations and five snackbars for one dead token is the '
            'loop the re-entrancy guard exists to prevent',
      );
    });

    test('a later 401, once already signed out, does nothing', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, status: 401),
        () async {
          await expectLater(
            const ModuleApi().getItems(_anyAuthedUrl),
            throwsA(isA<Object>()),
          );
          // A poll that was already scheduled lands after the sign-out.
          await expectLater(
            const ModuleApi().getItems(_anyAuthedUrl),
            throwsA(isA<Object>()),
          );
        },
      );

      expect(routedToSignIn, 1);
    });

    test('there is nothing to end when nobody is signed in', () async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();

      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, status: 401),
        () async {
          await expectLater(
            const ModuleApi().getItems(_anyAuthedUrl),
            throwsA(isA<Object>()),
          );
        },
      );

      expect(
        routedToSignIn,
        0,
        reason:
            'a guest browsing public content must not be thrown at the sign-in '
            'screen by an endpoint that happens to require a token',
      );
    });
  });

  group('a 403 is a different answer and is left alone', () {
    test('a permission refusal does not sign anyone out', () async {
      await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, status: 403),
        () async {
          await expectLater(
            const ModuleApi().getItems(_anyAuthedUrl),
            throwsA(isA<Object>()),
          );
        },
      );

      expect(routedToSignIn, 0);
      expect(
        sharedPreferences.getString('id_user'),
        '7',
        reason:
            'a pending approval and a guest restriction both answer 403 to a '
            'perfectly valid session — A16 removed the retry that conflated '
            'them for exactly this reason',
      );
    });

    test('isSessionExpiredStatus names only 401', () {
      expect(isSessionExpiredStatus(401), isTrue);
      expect(isSessionExpiredStatus(403), isFalse);
      expect(isSessionExpiredStatus(404), isFalse);
      expect(isSessionExpiredStatus(500), isFalse);
      expect(isSessionExpiredStatus(200), isFalse);
    });
  });

  group('the sign-in flows cannot reach the handler', () {
    test('LoginController never calls ModuleApi', () {
      // A wrong password legitimately returns 401. If sign-in ever went
      // through this file's choke points, typing a password wrong would sign
      // the user out of a session they do not have and replace the inline
      // "Incorrect phone number or password" with a snackbar about expiry.
      //
      // The separation is structural — controllers/login.dart owns a private
      // Dio client with its own cookie jar — so it is asserted structurally.
      final source = File('lib/controllers/login.dart').readAsStringSync();

      expect(
        source.contains('module_api.dart'),
        isFalse,
        reason: 'importing it is the first step towards calling it',
      );
      for (final call in ['ModuleApi(', 'getItems(', 'getObject(']) {
        expect(
          source.contains(call),
          isFalse,
          reason: '$call would route a sign-in refusal into the expiry handler',
        );
      }
    });
  });

  group('the user is told what happened, in their own language', () {
    test('both keys exist in English and Arabic', () {
      // `.tr` returns the key itself when it is missing — silently — so a
      // missing entry shows the literal "session_expired_message" on screen.
      final translations = AppTranslations().keys;
      final en = translations['en_US']!;
      final ar = translations['ar_SA']!;

      for (final key in [kSessionExpiredTitleKey, kSessionExpiredMessageKey]) {
        expect(en.containsKey(key), isTrue, reason: '$key missing from _en');
        expect(ar.containsKey(key), isTrue, reason: '$key missing from _ar');
        expect(
          ar[key],
          isNot(en[key]),
          reason: '$key still holds the English string in _ar',
        );
      }
      // The copy has to name the recovery, not just the fault (rule 5.7): a
      // message that says the session ended and stops there is a dead end.
      expect(en[kSessionExpiredMessageKey], contains('sign in'));
      expect(ar[kSessionExpiredMessageKey], contains('تسجيل الدخول'));
    });
  });
}
