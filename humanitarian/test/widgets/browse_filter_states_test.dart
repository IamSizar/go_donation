// Pins that the two filter rows on Home and the City Guide never disappear
// in silence.
//
// WHY THIS FILE EXISTS (C2)
// The client reported "lists on the City Guide that do not appear". Two
// separate rows vanish, and both vanish the same way: their loader treats a
// failure as an empty result, and an empty result renders nothing.
//
//   1. The City Guide's sector chips sat behind `if (sectors.isNotEmpty)`,
//      and `fetchSectors` ended in `catch (_) { sectors.clear(); }`. A failed
//      request and an empty taxonomy were indistinguishable, and neither
//      offered a retry — while the map region right below them showed a
//      proper error state with one, so the screen contradicted itself.
//
//   2. Home printed the heading "Browse by category" unconditionally above
//      capsules that render `SizedBox.shrink()` when empty. A heading with
//      nothing under it is worse than either state on its own: it tells the
//      user there are categories AND that they have none.
//
// WHAT THE SECOND ONE CHANGES ABOUT THE FIRST
// `fetchCaseCategories` deliberately swallowed its errors, with a comment
// arguing the row "states nothing untrue" because it is a browse filter and
// not the user's data. That argument was sound for a bare row and stopped
// being sound the moment a heading was put above it. The heading and the row
// now belong to one widget, so they cannot disagree again.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';
import 'package:flutter_application_1/shared/widgets/case_category_capsules.dart';

import '../support/fake_http.dart';

/// Two categories, in the shape GET /api/case-categories really answers with.
const _twoCategories =
    '{"items": ['
    '{"id": 1, "slug": "orphans", "name_en": "Orphans", "name_ar": "الأيتام", '
    '"name_ckb": "", "name_kmr": ""},'
    '{"id": 2, "slug": "widows", "name_en": "Widows", "name_ar": "الأرامل", '
    '"name_ckb": "", "name_kmr": ""}]}';

Widget _wrap(Widget child) =>
    GetMaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// Pumps [child] with every HTTP request answered per [overrides].
///
/// `HttpOverrides.global` rather than `runZoned`, because the widget's own
/// `initState` fires inside the tester's zone and would not inherit a zone
/// established around the pump call.
Future<void> _pumpWithHttp(
  WidgetTester tester,
  FakeHttpOverrides overrides,
  Widget child,
) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);
  await tester.pumpWidget(_wrap(child));
  await tester.pumpAndSettle();
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  group('Home — "Browse by category"', () {
    testWidgets('a failed load offers a retry instead of vanishing', (
      tester,
    ) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.networkError),
        CaseCategoryCapsules(
          header: const Text('Browse by category'),
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(
        find.byType(AppErrorState),
        findsOneWidget,
        reason: 'a row that silently disappears is the whole of C2',
      );
    });

    testWidgets('the heading does not survive an empty taxonomy', (
      tester,
    ) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: '{"items": []}'),
        CaseCategoryCapsules(
          header: const Text('Browse by category'),
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(
        find.text('Browse by category'),
        findsNothing,
        reason: 'a heading over nothing claims there are categories to browse',
      );
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('real categories render under the heading', (tester) async {
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoCategories),
        CaseCategoryCapsules(
          header: const Text('Browse by category'),
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(find.text('Browse by category'), findsOneWidget);
      expect(find.text('Orphans'), findsOneWidget);
      expect(find.text('Widows'), findsOneWidget);
    });

    testWidgets('with no header it renders the row alone, as before', (
      tester,
    ) async {
      // The case-list screen uses these capsules as a bare filter with its own
      // page heading. That call site must not sprout a second one.
      await _pumpWithHttp(
        tester,
        FakeHttpOverrides(HttpBehaviour.ok, body: _twoCategories),
        CaseCategoryCapsules(selected: null, onSelected: (_) {}),
      );

      expect(find.text('Orphans'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    });
  });

  group('City Guide — sector filter chips', () {
    testWidgets('a failed sector load is recorded, not swallowed', (
      tester,
    ) async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = FakeHttpOverrides(HttpBehaviour.networkError);
      addTearDown(() => HttpOverrides.global = previous);

      final controller = CommunityController();
      await controller.fetchSectors();

      expect(
        controller.sectorsError.value,
        isNotNull,
        reason:
            'catch (_) { sectors.clear(); } made a failure look like a guide '
            'with no sectors in it',
      );
      expect(controller.sectorsLoading.value, isFalse);
    });

    testWidgets('a successful empty taxonomy is not an error', (tester) async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = FakeHttpOverrides(
        HttpBehaviour.ok,
        body: '{"success": true, "items": []}',
      );
      addTearDown(() => HttpOverrides.global = previous);

      final controller = CommunityController();
      await controller.fetchSectors();

      expect(
        controller.sectorsError.value,
        isNull,
        reason:
            'over-throwing here would replace a legitimately empty filter row '
            'with a permanent error banner',
      );
      expect(controller.sectors, isEmpty);
    });
  });
}
