// R2 #63 — the logout row must scroll fully ABOVE the phone's navigation
// buttons.
//
// On an Android phone that draws the app edge to edge, the system navigation
// bar overlaps the bottom of the window and Flutter reports its height as
// viewPadding.bottom. The profile menu ended with a flat 24pt of padding, so
// the last row — «تسجيل الخروج» — stopped under the buttons. This simulates
// that overlap (a 56pt bar) and checks the row ends above it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/auth/screens/profile_menu_screen.dart';

import '../support/fake_http.dart';

const _navBar = 56.0;

Future<double> _logoutBottomGap(WidgetTester tester, double inset) async {
  SharedPreferences.setMockInitialValues({'id_user': '12'});
  sharedPreferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  // The inset goes through the WINDOW, because GetMaterialApp builds its own
  // MediaQuery from it (a MediaQuery wrapped around the app is overridden).
  tester.view.viewPadding = FakeViewPadding(bottom: inset * 3);
  tester.view.padding = FakeViewPadding(bottom: inset * 3);
  addTearDown(tester.view.reset);

  await withHttp(FakeHttpOverrides(HttpBehaviour.networkError), () async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        home: const ProfileMenuScreen(),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pump(const Duration(milliseconds: 500));
  });

  final rowBottom = tester.getBottomLeft(find.text('Log out')).dy;
  return 800 - rowBottom;
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  testWidgets('an overlapping navigation bar pushes the last row up by its '
      'height, so it clears the buttons', (tester) async {
    final without = await _logoutBottomGap(tester, 0);
    // Rebuild from scratch with the bar present.
    await tester.pumpWidget(const SizedBox());
    final withBar = await _logoutBottomGap(tester, _navBar);

    // The row must end ABOVE the bar: its distance from the screen edge has to
    // grow by (at least) the bar's height. Before the fix both were equal and
    // the row stopped under the buttons.
    expect(
      withBar - without,
      greaterThanOrEqualTo(_navBar - 1),
      reason:
          'gap without the bar: $without, with it: $withBar — the page '
          'ignored the system navigation inset',
    );
  });

  testWidgets('the extra space is the inset and no more (no dead space)', (
    tester,
  ) async {
    final without = await _logoutBottomGap(tester, 0);
    await tester.pumpWidget(const SizedBox());
    final withBar = await _logoutBottomGap(tester, _navBar);
    expect(withBar - without, lessThan(_navBar + 8));
  });
}
