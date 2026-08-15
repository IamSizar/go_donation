// Pins the engagement profile's per-field privacy picker (L19).
//
// WHY THIS FILE EXISTS, AND WHY THE PICKER DID NOT UNTIL NOW
// The engagement form offered ONE whole-profile audience dropdown with three
// values, which cannot express "show my age, hide my photo". An earlier agent
// refused to ship the picker, and was right to: `marriage.Store.List` selected
// every field and masked none, so a row of switches would have changed
// nothing. On a matchmaking profile that is a privacy incident, not a cosmetic
// gap.
//
// Backend 0206ca0 + migration 107 supplied the missing half —
// `marriage_profiles.field_privacy`, a `marriage_privacy_field_options`
// catalogue, and `maskForViewer` blanking the named fields for anyone who is
// not the owner across all four callers. So the switches now govern something,
// and this is what holds them to it:
//
//   GET  /api/marriage/privacy-options → items[] {field_key, label_key,
//        default_hidden, display_order}. The catalogue is the CONTRACT:
//        SetFieldPrivacy drops any key it does not list, so a switch offered
//        from anywhere else would be a switch that silently does nothing.
//   POST /api/marriage/:id/privacy ← {"hidden": [...]}, the whole set, echoed
//        back as stored. Ownership is checked inside the UPDATE, so the ID IN
//        THE PATH is part of the contract — the right list sent to the wrong
//        id is a 403, not a save.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_field_privacy_screen.dart';

import '../support/fake_http.dart';

/// The catalogue as migration 107 seeds it, trimmed to three rows.
String _options({List<Map<String, dynamic>>? items}) => jsonEncode({
  'success': true,
  'items':
      items ??
      [
        {
          'field_key': 'photo_url',
          'label_key': 'marriage_photo',
          'default_hidden': false,
          'display_order': 10,
        },
        {
          'field_key': 'age',
          'label_key': 'marriage_age',
          'default_hidden': false,
          'display_order': 20,
        },
        {
          'field_key': 'religion',
          'label_key': 'marriage_religion',
          'default_hidden': false,
          'display_order': 30,
        },
      ],
  // The POST answers on the same fake, so its echo rides along here.
  'hidden': ['religion', 'photo_url'],
});

/// The owner's own profile card, which already carries `field_privacy`.
const _profileId = 27;

Widget _screen({List<String> hidden = const ['religion']}) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: MarriageFieldPrivacyScreen(
    profileId: _profileId,
    initialHidden: hidden,
  ),
);

Future<void> _open(
  WidgetTester tester,
  FakeHttpOverrides recorder, {
  List<String> hidden = const ['religion'],
}) async {
  await withHttp(recorder, () async {
    await tester.pumpWidget(_screen(hidden: hidden));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

/// Every `{"hidden": […]}` write, paired with the URL it went to.
List<({Uri url, List<String> hidden})> _writes(FakeHttpOverrides recorder) {
  final out = <({Uri url, List<String> hidden})>[];
  // Bodies are only recorded for requests that HAVE one, so the two lists are
  // not parallel; the write is matched to the last POST-able URL seen.
  for (final body in recorder.requestBodies) {
    Map<String, dynamic>? decoded;
    try {
      final d = jsonDecode(body);
      if (d is Map) decoded = Map<String, dynamic>.from(d);
    } catch (_) {
      // Not JSON, so not one of ours. Skipped, not swallowed.
    }
    if (decoded == null || decoded['hidden'] is! List) continue;
    final url = recorder.requestUrls.lastWhere(
      (u) => u.path.endsWith('/privacy'),
      orElse: () => Uri.parse('about:blank'),
    );
    out.add((
      url: url,
      hidden: (decoded['hidden'] as List).map((e) => e.toString()).toList(),
    ));
  }
  return out;
}

const _myProfileScreen =
    'lib/modules/marriage/screens/marriage_my_profile_screen.dart';

String _readSource(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the picker renders the catalogue, and only the catalogue', () {
    testWidgets('one switch per option, in the profile\'s own state', (
      tester,
    ) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.ok, body: _options()));

      final photo = tester.widget<SwitchListTile>(
        find.byKey(const Key('marriage_privacy_photo_url')),
      );
      final religion = tester.widget<SwitchListTile>(
        find.byKey(const Key('marriage_privacy_religion')),
      );
      expect(photo.value, isTrue, reason: 'not in field_privacy → visible');
      expect(
        religion.value,
        isFalse,
        reason:
            'the owner had already hidden religion; drawing it visible would '
            'misreport what strangers can see',
      );
      // profile_code is deliberately not offerable — it is the handle that
      // stands in for a name, and hiding it leaves an unreferenceable card.
      expect(find.byKey(const Key('marriage_privacy_profile_code')), findsNothing);
    });

    testWidgets('labels resolve, never a bare key', (tester) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.ok, body: _options()));

      expect(find.text('marriage_photo'.tr), findsOneWidget);
      expect(find.text('marriage_religion'.tr), findsOneWidget);
      expect(find.text('marriage_photo'), findsNothing);
    });
  });

  group('a switch writes the whole set, to the right profile', () {
    testWidgets('hiding one posts every hidden key to that profile\'s id', (
      tester,
    ) async {
      final recorder = FakeHttpOverrides(HttpBehaviour.ok, body: _options());
      await _open(tester, recorder);

      await withHttp(recorder, () async {
        // Switch the photo OFF — "visible" false means "hidden".
        await tester.tap(find.byKey(const Key('marriage_privacy_photo_url')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      final writes = _writes(recorder);
      expect(writes, hasLength(1));
      expect(
        writes.single.hidden..sort(),
        ['photo_url', 'religion'],
        reason:
            'SetFieldPrivacy REPLACES the column, so omitting religion would '
            'un-hide a field the owner had already hidden',
      );
      expect(
        writes.single.url.path,
        endsWith('/marriage/$_profileId/privacy'),
        reason:
            'ownership is checked inside the UPDATE — the right list sent to '
            'the wrong id is a 403, and a missing profile answers the same '
            'way, so ids cannot be probed',
      );
    });
  });

  group('a failed catalogue says so instead of guessing', () {
    testWidgets('no switches, and a retry', (tester) async {
      await _open(tester, FakeHttpOverrides(HttpBehaviour.serverError));

      expect(
        find.byType(SwitchListTile),
        findsNothing,
        reason:
            'the catalogue is the contract: SetFieldPrivacy drops keys it does '
            'not list, so a guessed switch is a switch that does nothing',
      );
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('retry'.tr), findsOneWidget);
    });

    testWidgets('an empty catalogue is an empty state, not an error', (
      tester,
    ) async {
      await _open(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _options(items: [])),
      );

      expect(find.byType(AppEmpty), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    });
  });

  // A SOURCE test, for the reason partners_doors_test.dart uses one: a picker
  // nobody can open is the same defect as no picker. It belongs on the profile
  // the switches govern, which is the only place an id exists to post to.
  group('the picker is reachable from the profile it governs', () {
    test('the my-profile card opens it', () {
      final source = _readSource(_myProfileScreen);
      expect(source.contains('MarriageFieldPrivacyScreen'), isTrue);
      expect(
        source.contains("item['field_privacy']"),
        isTrue,
        reason:
            'the owner\'s current choices ride along on GET /api/marriage/mine, '
            'so the picker opens knowing them rather than defaulting to '
            '"nothing is hidden"',
      );
    });
  });
}
