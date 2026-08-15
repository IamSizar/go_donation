// Pins the fork between مساعدات عامة and التبرع حسب مشروع محدد (M4).
//
// WHY THIS FILE EXISTS
// M4 asks for a donation to branch into two named paths, with projects
// hideable from the dashboard while the general donation stays available.
// Both destinations already worked and neither was ever offered as a choice:
// checkout drew a bare project dropdown, so general aid was a DEFAULT rather
// than a decision, and the dropdown had no null item — the client's own
// reproduction is "choose a project, then try to change your mind: there is no
// way back".
//
// THE THIRD FAILURE, WHICH THE CLIENT COULD NOT SEE
// The project list was loaded behind a `catch` that hid the whole section. A
// hidden section is invisible when the picker is an optional refinement, and
// becomes a lie the moment a tile says "donate to a specific project" — tap it
// and nothing appears. `fetchProjectCategories` throws now, and the tests
// below hold both halves of that contract: a failure is a retry, an empty
// catalogue is not.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/project_categories_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/donations/widgets/aid_target_field.dart';

import '../support/fake_http.dart';

/// Two projects, in the shape GET /api/project-categories really answers with.
///
/// The fake answers EVERY request with this body, including the
/// GET /api/donation-options call the widget makes first. That is harmless and
/// deliberate: `getDonationOptions` reads `projects_visible` with a
/// `!= false` test, so a body without the key means "visible", which is the
/// state these cases are about.
const _twoProjects =
    '{"items": ['
    '{"id": 1, "slug": "orphan_sponsorship", "name_en": "Orphan sponsorship", '
    '"name_ar": "كفالة يتيم", "name_ckb": "", "name_kmr": ""},'
    '{"id": 2, "slug": "food_baskets", "name_en": "Food baskets", '
    '"name_ar": "السلال الغذائية", "name_ckb": "", "name_kmr": ""}]}';

/// The dashboard switch turned off. `projects_visible: false` is answered to
/// every request, so the project list is never even asked for.
/// `success: true` is load-bearing — ModuleApi.getObject rejects any body
/// without it, and a rejected body sends getDonationOptions to its "everything
/// on" fallback, which is the opposite of what this case is testing.
const _projectsHidden =
    '{"success": true, "projects_visible": false, "items": []}';

Widget _wrap(Widget child) => GetMaterialApp(
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _pumpWithHttp(
  WidgetTester tester,
  FakeHttpOverrides overrides,
  Widget child, {
  bool settle = true,
}) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);
  await tester.pumpWidget(_wrap(child));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  // AppHaptics reads the global mute flag, which reads SharedPreferences, so a
  // tap on any tile below throws a LateInitializationError without this.
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the two paths are both named', () {
    testWidgets('general aid is a choice, not what happens if you do nothing', (
      tester,
    ) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoProjects),
        AidTargetField(
          selectedProject: null,
          accentColor: Colors.teal,
          onChanged: (_) {},
        ),
      );

      expect(find.text('General aid'), findsOneWidget);
      expect(
        find.text('Our team distributes it by priority and real need.'),
        findsOneWidget,
        reason:
            'the client asked for staff distribution by priority and need to '
            'be what this option SAYS, not an internal policy',
      );
      expect(find.text('Donate to a specific project'), findsOneWidget);
    });

    testWidgets('the project picker only appears once you ask for it', (
      tester,
    ) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoProjects),
        AidTargetField(
          selectedProject: null,
          accentColor: Colors.teal,
          onChanged: (_) {},
        ),
      );

      expect(
        find.byType(DropdownButtonFormField<ProjectCategory>),
        findsNothing,
      );

      await tester.tap(find.text('Donate to a specific project'));
      await tester.pumpAndSettle();

      expect(
        find.byType(DropdownButtonFormField<ProjectCategory>),
        findsOneWidget,
      );
    });

    testWidgets('there is a way back from a project to general aid', (
      tester,
    ) async {
      // The exact defect the client reported: once a project was picked there
      // was no null item in the dropdown and no other route back.
      ProjectCategory? sent = const ProjectCategory(
        id: 1,
        slug: 'orphan_sponsorship',
        nameEn: 'Orphan sponsorship',
        nameAr: '',
        nameCkb: '',
        nameKmr: '',
      );
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoProjects),
        AidTargetField(
          selectedProject: sent,
          accentColor: Colors.teal,
          onChanged: (p) => sent = p,
        ),
      );

      await tester.tap(find.text('General aid'));
      await tester.pumpAndSettle();

      expect(
        sent,
        isNull,
        reason:
            'switching back to general aid must clear the project, or the '
            'gift is still filed against it',
      );
    });

    testWidgets('a project the organization has retired is dropped', (
      tester,
    ) async {
      // Regression, found by the test above rather than by reading the code:
      // ProjectCategory has no `==`, so a held instance is never identical to
      // a freshly fetched one. Handing it to DropdownButton as its value threw
      // "there should be exactly one item with this value" and took the whole
      // checkout screen down. The value is resolved by slug now — and a slug
      // that resolves to nothing means the project is gone, so the form must
      // stop holding it.
      ProjectCategory? sent = const ProjectCategory(
        id: 99,
        slug: 'a_project_since_retired',
        nameEn: 'Retired project',
        nameAr: '',
        nameCkb: '',
        nameKmr: '',
      );
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoProjects),
        AidTargetField(
          selectedProject: sent,
          accentColor: Colors.teal,
          onChanged: (p) => sent = p,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        sent,
        isNull,
        reason: 'a withdrawn slug must not travel with the donation',
      );
    });
  });

  group('the four states of the project list', () {
    testWidgets('it opens on a skeleton', (tester) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoProjects),
        AidTargetField(
          selectedProject: null,
          accentColor: Colors.teal,
          onChanged: (_) {},
        ),
        settle: false,
      );

      expect(find.byType(AppSkeleton), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a failed load offers a retry instead of hiding the fork', (
      tester,
    ) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.serverError),
        AidTargetField(
          selectedProject: null,
          accentColor: Colors.teal,
          onChanged: (_) {},
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(
        find.text('Donate to a specific project'),
        findsNothing,
        reason:
            'a tile promising a list we could not read is a control that does '
            'nothing when tapped',
      );
    });

    testWidgets(
      'an empty catalogue is not an error, and says where the money goes',
      (tester) async {
        await _pumpWithHttp(
          tester,
          FakeHttpOverrides(HttpBehaviour.ok, body: '{"items": []}'),
          AidTargetField(
            selectedProject: null,
            accentColor: Colors.teal,
            onChanged: (_) {},
          ),
        );

        expect(find.byType(AppErrorState), findsNothing);
        expect(find.text('General aid'), findsOneWidget);
        expect(
          find.textContaining('No project is open for donation right now'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'hiding projects from the dashboard leaves general aid working',
      (tester) async {
        // This is the second half of M4 in one assertion: "projects hideable
        // from the dashboard while the general donation stays available".
        await _pumpWithHttp(
          tester,
          FakeHttpOverrides(HttpBehaviour.ok, body: _projectsHidden),
          AidTargetField(
            selectedProject: null,
            accentColor: Colors.teal,
            onChanged: (_) {},
          ),
        );

        expect(find.byType(AppErrorState), findsNothing);
        expect(find.text('Donate to a specific project'), findsNothing);
        expect(find.text('General aid'), findsOneWidget);
        expect(
          find.textContaining('Project donations are switched off'),
          findsOneWidget,
        );
      },
    );
  });

  group('the branch reads as words in Arabic', () {
    final en = AppTranslations().keys['en_US']!;
    final ar = AppTranslations().keys['ar_SA']!;

    const keys = <String>[
      'Who should this help?',
      'General aid',
      'Our team distributes it by priority and real need.',
      'Donate to a specific project',
      "Choose one of the organization's open projects.",
      'We could not load the projects.',
      'Choose a project, or go back to general aid.',
      'No project is open for donation right now, so your gift goes to general aid.',
      'Project donations are switched off right now, so your gift goes to general aid.',
    ];

    test('each has an English entry, so `.tr` is not a no-op', () {
      for (final key in keys) {
        expect(en.containsKey(key), isTrue, reason: key);
      }
    });

    test('none of them renders English on an Arabic screen', () {
      for (final key in keys) {
        expect(ar[key], isNotNull, reason: key);
        expect(
          RegExp(r'[A-Za-z]').hasMatch(ar[key]!),
          isFalse,
          reason: 'Latin letters reached the Arabic label for $key',
        );
      }
    });
  });
}
