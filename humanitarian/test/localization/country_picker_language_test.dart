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
import 'package:flutter_application_1/modules/auth/screens/guest_upgrade.dart';
import 'package:flutter_application_1/modules/auth/screens/login.dart';

/// Latin letters — must not appear in the dialog's country names under `ar`.
final _latin = RegExp(r'[A-Za-z]');

/// Arabic-script letters — must not appear under `en`.
final _arabic = RegExp(r'[؀-ۿ]');

/// Matches a real, selectable country row's rendered Text — e.g.
/// "+93 أفغانستان" — as opposed to the dialog's header or search-box copy.
/// `showCountryOnly: false` renders the dial code and the country name as
/// ONE Text (`CountryCode.toLongString()`), so a row is never just the
/// digits: it always starts with '+' immediately followed by a digit. (An
/// earlier version of this file tried to isolate country rows by excluding
/// anything starting with '+' — which, given that shape, excluded every
/// real row and left the language checks silently testing nothing.)
final _countryRow = RegExp(r'^\+\d');

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

/// F1 regression guard — same setup as [_pumpLoginUnder], but for
/// guest_upgrade.dart's screen, which had the identical mixed-language bug
/// with no fix at all until it was moved onto the same shared
/// `LocalizedCountryList` mixin login.dart uses.
Future<void> _pumpGuestUpgradeUnder(WidgetTester tester, Locale locale) async {
  Get.reset();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    GetMaterialApp(
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      home: const GuestUpgradeScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the country-code chip beside the phone field to open the dialog.
Future<void> _openCountryPicker(WidgetTester tester) async {
  // The chip renders as "+964" (the Iraq default) beside the flag; the
  // whole row is the tap target the package wires up internally.
  await tester.tap(find.text('+964'));
  await tester.pumpAndSettle();
}

/// F4 — every real country row (see [_countryRow]) inside the dialog,
/// collected across the WHOLE scrollable list rather than just what's on
/// screen.
///
/// The package's dialog body is a `ListView(children: [...])`: not a
/// `ListView.builder`, so every country is already a widget in that list —
/// but Flutter's sliver machinery still only realizes (mounts as an
/// Element) the rows within the current viewport plus a small cache area,
/// same as any scrollable. `_visibleDialogText` right after opening the
/// dialog therefore only sees the ~10 rows that fit the fixed 360x520
/// dialog, not the full ~250-country list — which is exactly the gap F4's
/// ">50" check exists to catch, so the check has to look at the whole list,
/// not one screenful of it. This drags the dialog's scrollable up a
/// fixed number of times, unioning the newly-realized names into a set
/// after each drag, until a full pass adds nothing more (the list bottomed
/// out).
Future<Set<String>> _collectAllCountryNames(WidgetTester tester) async {
  // Two Scrollables live under the dialog: the search TextField's own
  // internal (horizontal) EditableText scrollable, found first, and the
  // vertical country ListView itself, found last — `.last` is the one that
  // actually needs dragging.
  final scrollable = find
      .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
      .last;
  final names = <String>{};
  void capture() =>
      names.addAll(_visibleDialogText(tester).where(_countryRow.hasMatch));

  capture();
  // ~250 countries at ~10 rows/screen is ~25 screenfuls; 40 iterations
  // leaves headroom, and the early-exit below stops as soon as a drag adds
  // nothing new (i.e. the list has bottomed out).
  for (var i = 0; i < 40; i++) {
    final before = names.length;
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
    capture();
    if (names.length == before) break;
  }
  return names;
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

    // F4 — a non-empty list alone would also pass if the picker rendered
    // only its favourites ("+964 العراق") and silently failed to load the
    // other ~240 entries. Requiring more than 50 real country rows (see
    // [_countryRow]) pins that the full localized list actually loaded, not
    // just the favourite row — scrolled through in full by
    // _collectAllCountryNames, since the dialog's viewport only shows ~10
    // at a time.
    final countryNames = await _collectAllCountryNames(tester);
    expect(
      countryNames.length,
      greaterThan(50),
      reason:
          'the dialog should list the full localized country set, not just '
          'the favourites; found only ${countryNames.length} entries',
    );

    final latinNames = countryNames.where((t) => _latin.hasMatch(t)).toList();
    expect(
      latinNames,
      isEmpty,
      reason:
          'every country name must read in Arabic under an Arabic locale; '
          'found Latin-script entries: $latinNames',
    );
  });

  testWidgets(
    'guest-upgrade screen: under ar, no country name renders in Latin script',
    (tester) async {
      _ignoreOverflowErrors();
      await _pumpGuestUpgradeUnder(tester, const Locale('ar', 'SA'));
      await _openCountryPicker(tester);

      final texts = _visibleDialogText(tester);
      expect(
        texts,
        isNotEmpty,
        reason: 'the dialog should be open and listing countries',
      );

      final countryNames = await _collectAllCountryNames(tester);
      expect(
        countryNames.length,
        greaterThan(50),
        reason:
            'the dialog should list the full localized country set, not '
            'just the favourites; found only ${countryNames.length} entries',
      );

      final latinNames = countryNames
          .where((t) => _latin.hasMatch(t))
          .toList();
      expect(
        latinNames,
        isEmpty,
        reason:
            'every country name must read in Arabic under an Arabic locale '
            'on the guest-upgrade screen too (F1); found Latin-script '
            'entries: $latinNames',
      );
    },
  );

  testWidgets('under en, no country name renders in Arabic script', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _pumpLoginUnder(tester, const Locale('en', 'US'));
    await _openCountryPicker(tester);

    final texts = _visibleDialogText(tester);
    expect(texts, isNotEmpty, reason: 'the dialog should be open and listing countries');

    // F4 — see the `ar` test above for why >50 (not just non-empty) matters,
    // and why the full list has to be scrolled through to count it.
    final countryNames = await _collectAllCountryNames(tester);
    expect(
      countryNames.length,
      greaterThan(50),
      reason:
          'the dialog should list the full localized country set, not just '
          'the favourites; found only ${countryNames.length} entries',
    );

    final arabicNames = countryNames.where((t) => _arabic.hasMatch(t)).toList();
    expect(
      arabicNames,
      isEmpty,
      reason:
          'every country name must read in English under the English '
          'locale; found Arabic-script entries: $arabicNames',
    );
  });
}
