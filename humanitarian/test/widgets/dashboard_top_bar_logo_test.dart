// Client note (2026-09-27): "add the app logo inside the app right next to
// the title of the tab", corrected same day with a screenshot of لوحة التحكم —
// the logo belongs beside `_TopBarTitle`, the title used by all 4 bottom-nav
// tabs (Home/لوحة التحكم, Marketplace, Events, City Guide) in
// `DashboardTopBar`, and nowhere else.
//
// `_TopBarTitle` is private and `DashboardTopBar` pulls in
// `RoleDashboardController`, chat and notification controllers this suite
// does not want to stand up just to read one Row — so this checks the source,
// the same convention top_bar_support_button_test.dart already uses for this
// exact class.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dashboardScreen = 'lib/modules/dashboard/screens/dashboard_screen.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// The source of `_TopBarTitle` alone, so a HeaderLogo used somewhere else in
/// this 900-line file cannot pass for "in the tab title itself".
String _titleBody() {
  final src = _read(_dashboardScreen);
  const marker = 'class _TopBarTitle';
  final start = src.indexOf(marker);
  if (start < 0) {
    throw StateError('$marker is gone from $_dashboardScreen — it was renamed or moved');
  }
  final next = src.indexOf('\nclass ', start + 1);
  return next < 0 ? src.substring(start) : src.substring(start, next);
}

void main() {
  test('the 4 bottom-nav tab titles (لوحة التحكم / Marketplace / Events / '
      'City Guide) show the HeaderLogo', () {
    final body = _titleBody();
    if (!body.contains('HeaderLogo')) {
      throw StateError(
        '_TopBarTitle no longer renders HeaderLogo — the owner asked for the '
        'app logo right beside this specific title, on all 4 tabs it serves',
      );
    }
  });

  test('HeaderLogo is imported from the shared widget, not redefined here', () {
    final src = _read(_dashboardScreen);
    if (!src.contains("import 'package:flutter_application_1/core/widgets/app_screen.dart'")) {
      throw StateError(
        'dashboard_screen.dart no longer imports app_screen.dart — HeaderLogo '
        'must stay the one shared definition (also used by its own test file, '
        'header_logo_test.dart) rather than a second copy drifting apart',
      );
    }
  });
}
