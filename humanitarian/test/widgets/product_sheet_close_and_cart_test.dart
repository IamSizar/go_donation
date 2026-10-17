// R2 #65 — the store's product sheet must always have a way out and a way to
// the cart.
//
// (Each test stops the controller's 5-second poll before it ends: a timer still
// running fails the framework's own end-of-test check.)
//
// The client: "selecting a product froze the page, cancel didn't respond, the
// cart only appeared after several tries". The sheet could only be dismissed by
// swiping it or tapping the dimmed strip above it, and it covered the cart bar,
// so after "Add" there was no visible exit and no cart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';

const _item = <String, dynamic>{
  'id': 7,
  'name': 'Test soap',
  'price': '15000',
  'price_after_discount': '15000',
  'currency': 'IQD',
};

Future<MarketplaceController> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  sharedPreferences = await SharedPreferences.getInstance();
  final controller = Get.put(MarketplaceController());
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    ProductDetailsSheet(item: _item, controller: controller),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  // The controller polls every 5 seconds; a timer still running when the test
  // body ends fails the framework's own check, so stop it with the test.
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUp(Get.reset);
  // Deleting the controller stops its 5-second poll timer; a timer left running
  // fails the test framework's end-of-test check.
  tearDown(Get.reset);

  testWidgets('the sheet has a visible close button that dismisses it', (
    tester,
  ) async {
    final controller = await _open(tester);
    expect(find.byType(ProductDetailsSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ProductDetailsSheet), findsNothing);
    controller.stopPolling();
  });

  testWidgets('no cart button until something is in the cart', (tester) async {
    final controller = await _open(tester);
    expect(find.textContaining('View cart'), findsNothing);
    controller.stopPolling();
  });

  testWidgets('after adding, the sheet offers the way to the cart', (
    tester,
  ) async {
    final controller = await _open(tester);
    controller.addProduct(_item);
    await tester.pumpAndSettle();

    expect(find.textContaining('View cart'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    controller.stopPolling();
  });
}
