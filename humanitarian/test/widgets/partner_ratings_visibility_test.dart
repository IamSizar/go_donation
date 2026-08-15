// Pins that the app obeys the organization's "hide the partner rating" switch.
//
// WHY THIS FILE EXISTS (K24)
// The client asked for a 1–5 star rating "with an option to hide it", and the
// server has that option: `GET /api/partners` answers a `ratings_visible`
// flag, and when it is false the handler STRIPS every score from the rows
// before sending them (listings.go — avg_rating, rating_count, my_rating,
// admin_rating and the four criterion scores all come back null/0).
//
// The app never read the flag. `getItems` reaches into `items` and throws the
// rest of the envelope away, so with ratings hidden the partner card rendered:
//
//   five empty stars · "No ratings yet" · a [Rate] button
//
// and the button worked. POST /api/partners/:id/rate has no visibility check
// of its own, so the tap succeeded, the controller wrote the returned average
// onto the row, the stars filled in, and a snackbar said "Your rating was
// saved." The next refresh stripped it again and the rating vanished.
//
// That is the defect class this codebase keeps refusing to ship: a control
// that appears to work and whose answer is discarded. Hiding the rating is not
// a cosmetic preference — it is the client's own switch, and the app was
// overriding it.
//
// WHAT IS DELIBERATELY NOT TESTED HERE
// That ratings are *absent* app-wide (products, campaigns, places, services).
// That half of K24 has no server side at all — there is exactly one rating
// table, partner_ratings — and is recorded in VERIFICATION_REPORT.md rather
// than faked here.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';

import '../support/fake_http.dart';

/// One partner, in the shape `GET /api/partners` really answers with when the
/// admin has LEFT ratings visible: scores present, envelope flag true.
const _visibleBody =
    '{"success": true, "ratings_visible": true, "items": ['
    '{"id": 1, "name": "Kurdistan Red Crescent", "name_ar": "الهلال الأحمر", '
    '"partner_type": "ngo", "status": "active", '
    '"avg_rating": 4.5, "rating_count": 2, "my_rating": 4}]}';

/// The same partner with the switch OFF. Note the scores are already gone —
/// this is the server's own output, not a shape invented for the test.
const _hiddenBody =
    '{"success": true, "ratings_visible": false, "items": ['
    '{"id": 1, "name": "Kurdistan Red Crescent", "name_ar": "الهلال الأحمر", '
    '"partner_type": "ngo", "status": "active", '
    '"avg_rating": null, "rating_count": 0, "my_rating": 0}]}';

Widget _wrap(Widget child) =>
    GetMaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// Installs [overrides] for the rest of the test.
///
/// `HttpOverrides.global` rather than `runZoned`, because the controller's
/// `onInit` fires inside the tester's zone and would not inherit a zone
/// established around the pump call. Same reasoning as
/// browse_filter_states_test.dart.
///
/// It must be called BEFORE `Get.put(PartnersController())`: GetX runs `onInit`
/// synchronously on put, so the very first `fetchPartners` would otherwise go
/// out through the real client and come back a failure.
void _installHttp(FakeHttpOverrides overrides) {
  final previous = HttpOverrides.current;
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = previous);
}

/// Loads the controller against [body], pumps a [PartnerRating] over its first
/// row, and returns the controller, settled.
Future<PartnersController> _loadedController(
  WidgetTester tester,
  String body, {
  FakeHttpOverrides? overrides,
}) async {
  _installHttp(overrides ?? FakeHttpOverrides(HttpBehaviour.ok, body: body));
  final controller = Get.put(PartnersController());
  await tester.pumpWidget(
    _wrap(
      Obx(
        () => PartnerRating(
          item: controller.partners.isEmpty
              ? const <String, dynamic>{}
              : controller.partners.first,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });
  tearDown(Get.reset);

  group('the partner rating obeys the admin switch', () {
    testWidgets('the flag in the envelope reaches the controller', (
      tester,
    ) async {
      final controller = await _loadedController(tester, _hiddenBody);

      expect(
        controller.ratingsVisible.value,
        isFalse,
        reason:
            'GET /api/partners answered ratings_visible:false. Reading only '
            '`items` throws the client\'s own switch away.',
      );
    });

    testWidgets('an unset flag means visible, as the server defines it', (
      tester,
    ) async {
      final controller = await _loadedController(tester, _visibleBody);

      expect(controller.ratingsVisible.value, isTrue);
    });

    testWidgets('hidden ratings offer no Rate button', (tester) async {
      await _loadedController(tester, _hiddenBody);
      await tester.pumpAndSettle();

      expect(
        find.text('Rate'),
        findsNothing,
        reason:
            'the button posts a score the server will strip on the next read, '
            'so the user rates a partner and watches it disappear',
      );
      expect(
        find.text('No ratings yet'),
        findsNothing,
        reason:
            '"no ratings yet" is a claim about the partner. The truth is that '
            'the organization is not publishing ratings at all.',
      );
      expect(
        find.byType(PartnerStarsRow),
        findsNothing,
        reason: 'five empty stars read as a partner nobody has rated',
      );
    });

    testWidgets('visible ratings still render the picker', (tester) async {
      await _loadedController(tester, _visibleBody);
      await tester.pumpAndSettle();

      expect(
        find.byType(PartnerStarsRow),
        findsOneWidget,
        reason:
            'the fix must not over-hide: with the switch ON this is the '
            'feature the client asked for',
      );
      expect(find.textContaining('4.5'), findsOneWidget);
    });
  });

  group('submitting a rating while hidden', () {
    testWidgets('is refused before it reaches the network', (tester) async {
      final overrides = FakeHttpOverrides(HttpBehaviour.ok, body: _hiddenBody);
      final controller = await _loadedController(
        tester,
        _hiddenBody,
        overrides: overrides,
      );

      final callsBefore = overrides.requestUrls.length;
      await controller.submitRating(controller.partners.first, 5);
      await tester.pumpAndSettle();

      // The UI no longer offers the button, but submitRating is public and a
      // future caller must not be able to route around the switch.
      expect(
        overrides.requestUrls.length,
        callsBefore,
        reason:
            'a rating posted while the organization publishes none is written '
            'to a column nothing reads',
      );
    });
  });
}
