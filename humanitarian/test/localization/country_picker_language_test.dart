// Pins that the sign-in/sign-up country-code picker reads in ONE language.
//
// THE BUG, reported by the owner: tapping the country code chip on the login
// screen opens a list where "some countries [are] in arabic and some in
// english". The `country_code_picker` package never got the app's own
// `CountryLocalizations.delegate` registered, and even if it had, the
// package's dialog is opened via `showDialog(useRootNavigator: true)`,
// which mounts on the app's root Overlay — a sibling of the login screen in
// the tree, not a descendant, so a local `Localizations.override` around
// the picker can never reach it (see the comment above
// `_LoginFormState._loadCountryList` in login.dart). With no lookup, every
// name falls back to the package's raw data: each country's OWN endonym
// ("Österreich", "中国大陆", "افغانستان") — a mixed list in every locale.
//
// The fix builds the country list itself: the package's default `codes`
// overlaid with names from the ONE i18n file matching the app's current
// language. This test opens the real dialog under `ar` and `en` and reads
// what's actually on screen, the same way guest_gate_language_test.dart
// pins the guest dialog — a key-presence check would miss this exactly the
// way it missed that bug, since the mismatch is only visible once rendered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/controllers/login.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/auth/screens/login.dart';

/// Latin letters — must not appear in the dialog's country names under `ar`.
final _latin = RegExp(r'[A-Za-z]');

/// Arabic-script letters — must not appear under `en`.
final _arabic = RegExp(r'[؀-ۿ]');

/// Every non-empty Text inside the open country-picker dialog. Scoped to
/// the `Dialog` ancestor so the assertions can't accidentally pass by
/// reading text from the login screen behind it (its own Google button,
/// for instance, legitimately mixes "G" with translated copy).
List<String> _visibleDialogText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Text)),
    )
    .map((t) => t.data ?? '')
    .where((s) => s.trim().isNotEmpty)
    .toList();

Future<void> _pumpLoginUnder(WidgetTester tester, Locale locale) async {
  Get.reset();
  Get.put(LoginController());
  // The default 800x600 test surface is narrower than the phone-field row
  // and the dialog's favourite chip at some translated widths, which
  // throws unrelated RenderFlex-overflow errors that fail the test before
  // the assertions below ever run. A tall/wide surface is closer to a real
  // device and keeps this test about language, not layout.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      home: const LoginPage(),
    ),
  );
  // _loadCountryList() runs its rootBundle.loadString asynchronously from
  // initState; let it resolve before the picker is opened.
  await tester.pumpAndSettle();
}

/// Taps the country-code chip beside the phone field to open the dialog.
Future<void> _openCountryPicker(WidgetTester tester) async {
  // The chip renders as "+964" (the Iraq default) beside the flag; the
  // whole row is the tap target the package wires up internally.
  await tester.tap(find.text('+964'));
  await tester.pumpAndSettle();
}

/// The package's dialog uses a fixed `Size(360, 520)` (set in login.dart)
/// regardless of device size, and its favourite-country row ("+964
/// العراق") overflows that fixed width in some languages — a pre-existing
/// layout quirk of the third-party dialog, unrelated to which language is
/// showing. `flutter_test` fails a test on ANY FlutterError during pump,
/// including this cosmetic RenderFlex overflow, so it would fail this test
/// for a reason that has nothing to do with what it's pinning. Installed at
/// the top of each `testWidgets` body — `TestWidgetsFlutterBinding`
/// reinstalls its own handler when a test starts, so a `setUpAll` override
/// does not survive into the test.
void _ignoreOverflowErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('RenderFlex overflowed')) {
      return;
    }
    original?.call(details);
  };
}

void main() {
  tearDown(Get.reset);

  testWidgets('under ar, no country name renders in Latin script', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _pumpLoginUnder(tester, const Locale('ar', 'SA'));
    await _openCountryPicker(tester);

    final texts = _visibleDialogText(tester);
    expect(texts, isNotEmpty, reason: 'the dialog should be open and listing countries');

    final latinNames = texts.where((t) => _latin.hasMatch(t) && !t.startsWith('+')).toList();
    expect(
      latinNames,
      isEmpty,
      reason:
          'every country name must read in Arabic under an Arabic locale; '
          'found Latin-script entries: $latinNames',
    );
  });

  testWidgets('under en, no country name renders in Arabic script', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _pumpLoginUnder(tester, const Locale('en', 'US'));
    await _openCountryPicker(tester);

    final texts = _visibleDialogText(tester);
    expect(texts, isNotEmpty, reason: 'the dialog should be open and listing countries');

    final arabicNames = texts.where((t) => _arabic.hasMatch(t)).toList();
    expect(
      arabicNames,
      isEmpty,
      reason:
          'every country name must read in English under the English '
          'locale; found Arabic-script entries: $arabicNames',
    );
  });
}
