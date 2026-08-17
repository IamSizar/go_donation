// Pins the identity code: the user seeing their own, and looking a history up
// by one (K21, app half).
//
// WHY THIS FILE EXISTS
// The registration form promises a code "يتم إنشاؤه تلقائياً بعد التسجيل" and
// the client asked to "استعلام بالكود التعريفي لاستعراض سجل (التبرعات وحالة
// الدعم)". Backend 5eee718 + migration 113 cleared both server blocks:
// `Account.identity_code` reports the account's own GR-/ER-/VL- code on
// /api/auth/me and /api/profile, and GET /api/history?code=… resolves a code.
//
// The app used neither. Reproduced on main before writing anything:
// `grep -rn "identity_code" lib` found nothing at all, and `ModuleApi.roleHistory`
// built its URL with `{'user_id': '$userId'}` and no other parameter — so the
// code was reported to an app that never read it, and the lookup existed with
// nothing to ask it.
//
// THE TWO THINGS WORTH PINNING
//   1. A code that has gone away must stop being shown. The code is written to
//      preferences so the profile card can render without waiting on a fetch,
//      and a cached code for the wrong account is worse than no code — so an
//      account that reports an EMPTY code clears the stored one, while a server
//      too old to report the field at all leaves it alone.
//   2. A refusal must reach the user as a sentence. `getObject` throws
//      `Exception('Request failed (404)')`, and the history controller assigns
//      `e.toString()` straight into the message it renders — so without a
//      dedicated reader, looking up somebody else's code would have printed
//      "Exception: Request failed (404)" onto the screen.
//
// The 404 wording is deliberately the server's own, and deliberately vague: the
// server answers "no such code" and "that is someone else's" IDENTICALLY on
// purpose, because the codes are sequential and confirming one confirms the
// range. The app must not undo that by guessing which happened.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/history_api.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/auth/screens/profile.dart';
import 'package:flutter_application_1/modules/history/controllers/role_history_controller.dart';
import 'package:flutter_application_1/modules/history/screens/role_history_screen.dart';

import '../support/fake_http.dart';

/// A `GET /api/history` success body, in the shape the Go handler returns.
String _historyBody() => jsonEncode({
  'success': true,
  'role': 'donor',
  'summary': const <String, dynamic>{},
  'kind_options': const ['all'],
  'status_options': const ['all'],
  'items': const <Map<String, dynamic>>[],
});

Widget _historyScreen() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const RoleHistoryScreen(),
);

Widget _profileScreen() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const Scaffold(body: ProfileSection()),
);

/// Pumps the profile tab with the network unreachable, so its background
/// account refresh fails fast instead of hanging the test on a real socket.
Future<void> _openProfile(WidgetTester tester) async {
  await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
    await tester.pumpWidget(_profileScreen());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the account\'s own code reaches the app', () {
    test('a reported code is stored', () async {
      await applyUserAccountToSharedPreferences({
        'user_id': 7,
        'identity_code': 'ER-000123',
      });

      expect(sharedPreferences.getString('identity_code'), 'ER-000123');
    });

    test('an account with no code clears a previously stored one', () async {
      await sharedPreferences.setString('identity_code', 'ER-000123');

      await applyUserAccountToSharedPreferences({
        'user_id': 7,
        'identity_code': '',
      });

      expect(
        sharedPreferences.getString('identity_code'),
        isNull,
        reason:
            'staff and guests carry no code; showing them the last one this '
            'device saw would name the wrong person',
      );
    });

    test('a server too old to report the field leaves the code alone', () async {
      await sharedPreferences.setString('identity_code', 'ER-000123');

      await applyUserAccountToSharedPreferences({'user_id': 7});

      expect(
        sharedPreferences.getString('identity_code'),
        'ER-000123',
        reason:
            'absent and empty are different: only the second is the server '
            'saying this account has none',
      );
    });
  });

  group('the user can see their own code', () {
    testWidgets('the profile card shows it', (tester) async {
      SharedPreferences.setMockInitialValues({
        'id_user': '7',
        'name_user': 'Sara',
        'role_id': '1',
        'identity_code': 'ER-000123',
      });
      sharedPreferences = await SharedPreferences.getInstance();

      await _openProfile(tester);

      expect(find.byKey(const Key('identity_code_chip')), findsOneWidget);
      expect(find.text('ER-000123'), findsOneWidget);
    });

    testWidgets('an account with no code shows no empty chip', (tester) async {
      SharedPreferences.setMockInitialValues({
        'id_user': '7',
        'name_user': 'Sara',
        'role_id': '1',
      });
      sharedPreferences = await SharedPreferences.getInstance();

      await _openProfile(tester);

      expect(
        find.byKey(const Key('identity_code_chip')),
        findsNothing,
        reason: 'a labelled chip with nothing in it is worse than no chip',
      );
    });
  });

  group('a history can be looked up by code', () {
    test('the request carries ?code=, not ?user_id=', () async {
      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _historyBody(),
      );

      await withHttp(recorder, () => fetchHistoryByCode('  er-000002 '));

      final asked = recorder.requestUrls.last;
      expect(asked.path, endsWith('/history/'));
      expect(
        asked.queryParameters['code'],
        'er-000002',
        reason:
            'the server trims and compares case-insensitively, so the app '
            'sends what was typed rather than inventing a normalisation',
      );
      expect(asked.queryParameters.containsKey('user_id'), isFalse);
    });

    test('200 is the person\'s timeline', () async {
      final result = await withHttp(
        FakeHttpOverrides(HttpBehaviour.ok, body: _historyBody()),
        () => fetchHistoryByCode('ER-000002'),
      );

      expect(result.outcome, HistoryLookupOutcome.ok);
      expect(result.data?['role'], 'donor');
    });

    test('404 is "no history for that code", never an exception string', () async {
      final result = await withHttp(
        FakeHttpOverrides(
          HttpBehaviour.ok,
          status: 404,
          body: jsonEncode({
            'success': false,
            'error': 'No history is available for that code.',
            'code': 'history_code_not_found',
          }),
        ),
        () => fetchHistoryByCode('ER-999999'),
      );

      expect(result.outcome, HistoryLookupOutcome.notFound);
      expect(result.messageKey, 'history_code_not_found');
      expect(result.data, isNull);
    });

    test('403 is a permission refusal, told apart from 404', () async {
      final result = await withHttp(
        FakeHttpOverrides(
          HttpBehaviour.ok,
          status: 403,
          body: jsonEncode({
            'success': false,
            'error': "You don't have permission for this action.",
            'code': 'permission_denied',
          }),
        ),
        () => fetchHistoryByCode('ER-000002'),
      );

      expect(result.outcome, HistoryLookupOutcome.notPermitted);
      expect(result.messageKey, 'history_code_not_permitted');
    });

    test('a server fault and an unreachable network both read as a failure',
        () async {
      final broken = await withHttp(
        FakeHttpOverrides(HttpBehaviour.serverError),
        () => fetchHistoryByCode('ER-000002'),
      );
      final offline = await withHttp(
        FakeHttpOverrides(HttpBehaviour.networkError),
        () => fetchHistoryByCode('ER-000002'),
      );

      expect(broken.outcome, HistoryLookupOutcome.failed);
      expect(offline.outcome, HistoryLookupOutcome.failed);
      expect(broken.messageKey, 'history_code_failed');
    });
  });

  group('the history screen carries the lookup, and says whose it shows', () {
    testWidgets('typing a code sends it, and the header names it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'id_user': '7'});
      sharedPreferences = await SharedPreferences.getInstance();

      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _historyBody(),
      );

      await withHttp(recorder, () async {
        await tester.pumpWidget(_historyScreen());
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        await tester.enterText(find.byType(TextField), 'ER-000002');
        // Past AppListSearchField's 350ms debounce.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      expect(
        recorder.requestUrls.last.queryParameters['code'],
        'ER-000002',
        reason: 'this is the whole of "send ?code= where the client asked"',
      );
      // "My history" and "Review YOUR recent activity" stop being true the
      // moment a code names somebody else, and the endpoint returns no name,
      // so the code itself has to be on screen.
      expect(find.text('ER-000002'), findsWidgets);

      // Dispose so the controller's 10s poll timer is cancelled with it.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('the history controller reports a refusal as a sentence', () {
    test('a 404 becomes the friendly message, not "Exception: …"', () async {
      SharedPreferences.setMockInitialValues({'id_user': '7'});
      sharedPreferences = await SharedPreferences.getInstance();
      Get.locale = const Locale('en', 'US');
      Get.addTranslations(AppTranslations().keys);

      final controller = RoleHistoryController();
      controller.setIdentityCode('ER-999999');

      await withHttp(
        FakeHttpOverrides(
          HttpBehaviour.ok,
          status: 404,
          body: jsonEncode({'success': false, 'code': 'history_code_not_found'}),
        ),
        () => controller.fetchHistory(),
      );

      expect(controller.errorMessage.value, 'history_code_not_found'.tr);
      expect(
        controller.errorMessage.value,
        isNot(contains('Exception')),
        reason:
            'the screen renders this string; a status code is not something a '
            'user can act on',
      );
      expect(controller.items, isEmpty);
    });

    test('clearing the code goes back to the caller\'s own history', () async {
      SharedPreferences.setMockInitialValues({'id_user': '7'});
      sharedPreferences = await SharedPreferences.getInstance();

      final controller = RoleHistoryController();
      controller.setIdentityCode('ER-000002');
      controller.setIdentityCode('');

      final recorder = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _historyBody(),
      );
      await withHttp(recorder, () => controller.fetchHistory());

      final asked = recorder.requestUrls.last;
      expect(asked.queryParameters.containsKey('code'), isFalse);
      // The absence of BOTH parameters is what "my own history" now means.
      //
      // This used to assert user_id == '7', reading the id out of
      // SharedPreferences and naming the caller in their own request. GET
      // /api/history already defaults to the bearer's account and answers 401
      // when a supplied user_id disagrees with the token — so sending it added
      // no capability and one way to fail, against a local value that does
      // drift (role_id in the same store was seen holding 1 for an account the
      // server reports as role 2).
      //
      // The test's intent is unchanged: clearing the code goes back to the
      // caller's own history. Only the mechanism it pins has moved, from
      // "names itself" to "asks as itself".
      expect(
        asked.queryParameters.containsKey('user_id'),
        isFalse,
        reason:
            'the caller must not name itself; the bearer already identifies it, '
            'and a stale local id would turn "my record" into a 401',
      );
    });
  });
}
