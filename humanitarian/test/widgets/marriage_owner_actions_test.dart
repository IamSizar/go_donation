// Pins the four things a خطوبتي profile's OWNER may do to it (K14).
//
// WHY THIS FILE EXISTS
// Commit 9f6ec79 shipped PATCH /api/marriage/:id, POST .../pause, POST
// .../resume and DELETE /api/marriage/:id. The app had none of them: the
// profile card offered exactly one control, the per-field privacy picker, and
// its own caption sent the user to staff for every change. Its menu entry
// avoided the word "edit" on purpose, because POST /api/marriage inserts a
// SECOND profile rather than updating the first.
//
// THREE THINGS ARE PINNED HERE, AND EACH ONE IS A WAY THIS COULD SHIP BROKEN:
//
//   1. THE VERB. The four routes differ from the existing ones only by method
//      — POST /api/marriage/7 is not "edit profile 7", it is "create another
//      profile". A test that pinned the URL alone would pass while the app
//      quietly created rows, so the method is asserted with the path.
//
//   2. WHICH ACTION IS OFFERED. The server accepts a pause only from the
//      browsable statuses and a resume only from 'paused'. Showing both
//      always would put a control on screen whose only possible outcome is
//      409 not_pausable.
//
//   3. THE LANGUAGE OF A FAILURE. Every failure carries a machine `code`
//      beside an English sentence, and 9f6ec79 states outright that the
//      sentence is a developer fallback. Rendering it would put English on an
//      Arabic screen — this repo's most-repeated defect.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/controllers/marriage_my_profile_controller.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_owner_actions.dart';

import '../support/fake_http.dart';

/// One row of GET /api/marriage/mine, in the shape `marriage.Profile`
/// marshals — nullable columns really do arrive as JSON null.
Map<String, dynamic> _profile({int id = 7, String status = 'active'}) => {
  'id': id,
  'user_id': 3,
  'profile_code': 'ENG-0007',
  'gender': 'Male',
  'age': 28,
  'city': 'الموصل',
  'social_summary': null,
  'marital_status': 'single',
  'religion': null,
  'employment_status': 'employed',
  'weight_kg': null,
  'height_cm': null,
  'photo_url': null,
  'visibility_level': 'employee_only',
  'field_privacy': <String>[],
  'subscription_status': 'none',
  'status': status,
  'created_at': '2026-08-01T10:00:00Z',
};

/// A successful owner write, followed by a `mine` refresh that returns the
/// row. One body serves both because the refresh reads `items` and the write
/// reads `success`.
String _okBody(Map<String, dynamic> row) =>
    '{"success": true, "id": ${row['id']}, "items": [${_encode(row)}]}';

String _encode(Map<String, dynamic> row) {
  final parts = <String>[];
  row.forEach((k, v) {
    final value = v == null
        ? 'null'
        : v is num
        ? '$v'
        : v is List
        ? '[]'
        : '"$v"';
    parts.add('"$k": $value');
  });
  return '{${parts.join(', ')}}';
}

Widget _host(Widget child) => GetMaterialApp(
  locale: const Locale('ar', 'SA'),
  fallbackLocale: const Locale('en', 'US'),
  translations: AppTranslations(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Pumps the action row with every request answered per [overrides].
///
/// `HttpOverrides.global` rather than `runZoned`, for the same reason
/// browse_filter_states_test gives: the widget's own callbacks fire inside the
/// tester's zone and would not inherit a zone established around the pump.
Future<MarriageMyProfileController> _pumpActions(
  WidgetTester tester,
  FakeHttpOverrides overrides, {
  String status = 'active',
  int id = 7,
}) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);

  // Constructed directly and NOT registered with Get: Get.put runs the
  // GetX lifecycle, and this controller's onInit both fetches and starts a
  // 5s poll timer — which would leave a pending timer after the tree is
  // disposed and record a GET nobody in the test asked for. The widget takes
  // its controller as a parameter, so nothing here needs the container.
  final controller = MarriageMyProfileController();

  await tester.pumpWidget(
    _host(
      MarriageOwnerActions(
        controller: controller,
        profile: _profile(id: id, status: status),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  setUp(() async {
    Get.reset();
    // AppHaptics reads AppMute, which reads the global sharedPreferences —
    // so every action in this file needs one, exactly as the field-privacy
    // suite does.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('ar', 'SA');
    Get.fallbackLocale = const Locale('en', 'US');
  });
  tearDown(Get.reset);

  group('the actions the card offers', () {
    testWidgets('an active profile can be edited, hidden and removed', (
      tester,
    ) async {
      await _pumpActions(tester, FakeHttpOverrides(HttpBehaviour.ok));

      expect(
        find.byKey(const Key('marriage_owner_edit')),
        findsOneWidget,
        reason: 'the whole of K14: the app offered no edit at all',
      );
      expect(find.byKey(const Key('marriage_owner_pause')), findsOneWidget);
      expect(find.byKey(const Key('marriage_owner_delete')), findsOneWidget);
      expect(
        find.byKey(const Key('marriage_owner_resume')),
        findsNothing,
        reason: 'resume from active can only answer 409 not_pausable',
      );
    });

    testWidgets('a paused profile offers resume, not pause', (tester) async {
      await _pumpActions(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok),
        status: 'paused',
      );

      expect(find.byKey(const Key('marriage_owner_resume')), findsOneWidget);
      expect(find.byKey(const Key('marriage_owner_pause')), findsNothing);
    });

    testWidgets('a rejected profile offers neither, and says why', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok),
        status: 'rejected',
      );

      expect(find.byKey(const Key('marriage_owner_pause')), findsNothing);
      expect(find.byKey(const Key('marriage_owner_resume')), findsNothing);
      expect(
        find.text('marriage_owner_pause_unavailable'.tr),
        findsOneWidget,
        reason:
            'a row that simply drops the control leaves the user looking for '
            'a button that is not there',
      );
      // Removing a rejected profile is still the owner's to do.
      expect(find.byKey(const Key('marriage_owner_delete')), findsOneWidget);
    });
  });

  group('the request that is actually sent', () {
    testWidgets('pause is POST /api/marriage/:id/pause', (tester) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: _okBody(_profile(status: 'paused')),
      );
      await _pumpActions(tester, overrides);

      await tester.tap(find.byKey(const Key('marriage_owner_pause')));
      await tester.pumpAndSettle();

      expect(
        overrides.requestSignatures.first,
        'POST /api/marriage/7/pause',
        reason: 'the pause route is the only one that records the previous '
            'status; anything else loses what resume restores',
      );
    });

    testWidgets('removing is DELETE /api/marriage/:id, never a POST', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: '{"success": true, "id": 7, "removed": true, '
            '"recoverable": true, "items": []}',
      );
      await _pumpActions(tester, overrides);

      await tester.tap(find.byKey(const Key('marriage_owner_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('marriage_owner_delete_confirm')));
      await tester.pumpAndSettle();

      expect(
        overrides.requestSignatures,
        contains('DELETE /api/marriage/7'),
        reason:
            'POST /api/marriage/7 is a different handler entirely — it would '
            'insert a second profile instead of removing this one',
      );

      // The success snackbar runs a 5s dismissal timer of its own, which the
      // tester counts as pending work after the tree is torn down.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('cancelling the confirmation sends nothing at all', (
      tester,
    ) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok);
      await _pumpActions(tester, overrides);

      await tester.tap(find.byKey(const Key('marriage_owner_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'.tr));
      await tester.pumpAndSettle();

      expect(
        overrides.requestMethods,
        isEmpty,
        reason: 'a destructive action that fires before the answer is not a '
            'confirmation',
      );
    });
  });

  group('a named failure is read in the user\'s language', () {
    /// The 409 the server answers when the owner pauses a profile whose
    /// status is not pausable — code AND English sentence, exactly as
    /// handlers.writeOwnerError writes it.
    const notPausable =
        '{"success": false, "code": "not_pausable", "error": "This engagement '
        'profile cannot be switched on or off while it is in its current '
        'state."}';

    test('not_pausable becomes Arabic copy, not the server\'s sentence',
        () async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.serverError,
        status: 409,
        body: notPausable,
      );
      final controller = MarriageMyProfileController();

      final message = await withHttp(overrides, () => controller.pauseProfile(7));

      expect(message, 'marriage_owner_error_not_pausable'.tr);
      expect(
        message,
        isNot(contains('engagement')),
        reason: '9f6ec79: the English string is a developer fallback and must '
            'not reach an Arabic screen',
      );
      expect(
        RegExp(r'[A-Za-z]').hasMatch(message!),
        isFalse,
        reason: 'the Arabic interface contains no English (project rule)',
      );
    });

    test('403 not_owner does not borrow the not_pausable sentence', () async {
      final overrides = FakeHttpOverrides(
        HttpBehaviour.serverError,
        status: 403,
        body: '{"success": false, "code": "not_owner", '
            '"error": "This engagement profile is not yours."}',
      );
      final controller = MarriageMyProfileController();

      final message = await withHttp(overrides, () => controller.deleteProfile(7));

      expect(message, 'marriage_owner_error_not_owner'.tr);
      expect(message, isNot('marriage_owner_error_not_pausable'.tr));
    });

    test('a code nobody has copy for degrades to the generic sentence',
        () async {
      // A code added server-side tomorrow. The failure mode being guarded is
      // `'marriage_owner_error_$code'.tr`, which GetX answers with the KEY —
      // so an Arabic reader would see the literal text
      // `marriage_owner_error_teapot`.
      final overrides = FakeHttpOverrides(
        HttpBehaviour.serverError,
        status: 418,
        body: '{"success": false, "code": "teapot", "error": "Nope."}',
      );
      final controller = MarriageMyProfileController();

      final message = await withHttp(overrides, () => controller.resumeProfile(7));

      expect(message, 'marriage_owner_error_generic'.tr);
      expect(message, isNot(contains('marriage_owner_error_')));
      expect(RegExp(r'[A-Za-z]').hasMatch(message!), isFalse);
    });

    test('an unreachable server still answers in the right language',
        () async {
      final controller = MarriageMyProfileController();

      final message = await withHttp(
        FakeHttpOverrides(HttpBehaviour.networkError),
        () => controller.pauseProfile(7),
      );

      expect(message, 'marriage_owner_error_generic'.tr);
      expect(RegExp(r'[A-Za-z]').hasMatch(message!), isFalse);
    });
  });

  group('the copy the owner reads before removing', () {
    test('the confirmation does not promise permanent deletion', () {
      // The server keeps the row, the mediated chat history and the
      // subscription purchase record; it stamps owner_deleted_at and closes
      // the profile. A dialog saying "permanently" would be the same untrue
      // sentence 11c7acb removed from the dashboard.
      for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
        Get.locale = locale;
        final body = 'marriage_owner_delete_body'.tr;
        expect(body, isNot('marriage_owner_delete_body'));
        expect(body.toLowerCase(), isNot(contains('permanent')));
        expect(body.toLowerCase(), isNot(contains('نهائي')));
      }
    });

    test('and it says the staff team can bring it back', () {
      Get.locale = const Locale('en', 'US');
      expect(
        'marriage_owner_delete_body'.tr.toLowerCase(),
        contains('staff'),
        reason: 'recoverable is the fact that makes this decision reversible; '
            'omitting it makes the dialog scarier than the truth',
      );
      Get.locale = const Locale('ar', 'SA');
      expect('marriage_owner_delete_body'.tr, contains('الموظفين'));
    });
  });
}
