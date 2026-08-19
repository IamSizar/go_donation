// Pins that the guest sign-in popup speaks the reader's language.
//
// THE BUG, reported from an Arabic guest session: "when it shows the popup
// window to tell me to login, it shows in english".
//
// The popup's title and both buttons were translated in all four languages.
// Its MESSAGE line was missing from every map INCLUDING English, and GetX
// `.tr` returns the key unchanged when it is missing. Both keys happened to
// read as English prose, so the popup looked translated except for the one
// line silently printing its own key.
//
// WHY A RENDERED TEST AND NOT A KEY-PRESENCE CHECK
// A key-presence check is what failed to catch this. The literals are not
// adjacent to their `.tr`: one is inside `(reason ?? '...').tr`, the other is
// passed as an argument at one call site and translated at another. Scanning
// for `'literal'.tr` finds neither. Rendering the actual dialog and reading
// what is on it cannot be fooled that way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';

/// Latin letters, which must not appear in Arabic UI copy.
final _latin = RegExp(r'[A-Za-z]');

/// Every text the dialog is currently showing.
List<String> _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.trim().isNotEmpty)
    .toList();

void main() {
  setUp(() async {
    // The real key is 'is_guest' (kGuestModePrefsKey). Getting this wrong
    // makes every test here VACUOUS: isGuestMode() returns false, the gate
    // returns true without ever opening a dialog, and an assertion that "no
    // English is on screen" passes because nothing is on screen at all.
    SharedPreferences.setMockInitialValues({kGuestModePrefsKey: true});
    sharedPreferences = await SharedPreferences.getInstance();
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('ar', 'SA');
  });

  Future<void> pumpGate(
    WidgetTester tester,
    Future<bool> Function(BuildContext) gate,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('ar', 'SA'),
        fallbackLocale: const Locale('en', 'US'),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => gate(context),
            child: const Text('افتح'),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Proof the gate actually fired. Without this every assertion below
    // passes when no dialog opens, which is precisely how a language test
    // can look green while testing nothing.
    expect(
      find.byType(Dialog).evaluate().isNotEmpty ||
          _visibleText(tester).length > 1,
      isTrue,
      reason: 'the guest gate did not open a dialog, so nothing was checked',
    );
  }

  testWidgets('the upgrade popup is entirely Arabic', (tester) async {
    await pumpGate(tester, (c) => requireUpgrade(c));

    final english = _visibleText(
      tester,
    ).where((s) => _latin.hasMatch(s)).toList();

    expect(
      english,
      isEmpty,
      reason:
          'these lines rendered in English on an Arabic screen: $english\n'
          'A missing key is invisible here — GetX echoes the key, and these '
          'keys read as English prose.',
    );
  });

  testWidgets('the City Directory reason is Arabic too', (tester) async {
    // The one call site that passes its own reason, and the one the owner
    // actually hit: the City Guide tab is a hard block for guests.
    await pumpGate(
      tester,
      (c) => requireUpgrade(
        c,
        reason: 'Full registration is required to view the City Directory.',
      ),
    );

    final english = _visibleText(
      tester,
    ).where((s) => _latin.hasMatch(s)).toList();

    expect(english, isEmpty, reason: 'rendered in English: $english');
  });

  testWidgets('the sign-in popup is entirely Arabic', (tester) async {
    await pumpGate(tester, requireSignIn);

    final english = _visibleText(
      tester,
    ).where((s) => _latin.hasMatch(s)).toList();

    expect(english, isEmpty, reason: 'rendered in English: $english');
  });
}
