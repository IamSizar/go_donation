// Guards the removal of the "Main menu" hamburger button (J7 follow-up).
//
// WHY THIS FILE EXISTS
// J7 originally asked for a hamburger button beside Back on every screen,
// unwinding the stack to the dashboard. The owner later looked at a header
// showing "≡" next to ">" and reported it as two controls that both "just go
// back" — and he was right: `AppMainMenuButton` popped the navigation stack
// to its root, the same direction as the back chevron, just further. It never
// opened a drawer or a menu (this app has none — see the removed widget's own
// header comment). So it was deleted from `AppScreen`'s shared header and
// from every screen that built its own `AppBar` with it in `actions`.
//
// This file used to prove the button was everywhere; it now proves the
// opposite — that it is nowhere — so an accidental re-add fails a test
// instead of silently reintroducing the duplicate control.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/localization/app_translations.dart';

/// Screens that used to build their own `AppBar` with the button in
/// `actions`. Kept as a named list so the guard states exactly which files
/// must stay clean, rather than a vague "search everywhere".
const _formerOwnAppBarPages = <String>[
  'lib/modules/auth/screens/edit_profile.dart',
  'lib/modules/bot/screens/bot_chat_screen.dart',
  'lib/modules/chat/screens/case_chat_conversation_screen.dart',
  'lib/modules/chat/screens/chat_conversation_screen.dart',
  'lib/modules/donations/screens/donation_details_screen.dart',
  'lib/modules/donations/screens/donations_screen.dart',
  'lib/modules/marriage/screens/marriage_chat_conversation_screen.dart',
  'lib/widgets/firebase_screen_add.dart',
];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('the shared frame no longer carries a menu button', () {
    Widget harness() => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const AppScreen(title: 'Inner', child: SizedBox()),
                ),
              ),
              child: const Text('open inner page'),
            ),
          ),
        ),
      ),
    );

    testWidgets('a pushed page shows Back but not a hamburger', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open inner page'));
      await tester.pumpAndSettle();

      expect(find.text('Inner'), findsOneWidget);
      // Back must still work — this is the header's only exit now.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      // The hamburger duplicated Back; it must not still be drawn.
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
    });

    testWidgets('tapping Back on the pushed page returns to the root', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open inner page'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('open inner page'),
        findsOneWidget,
        reason: 'Back must remain the sole, working way out of the screen',
      );
    });
  });

  group('the screens that used to build their own AppBar stayed clean', () {
    test('none of them reference the removed widget any more', () {
      final stillReferencing = _formerOwnAppBarPages
          .where((p) => _read(p).contains('AppMainMenuButton'))
          .toList();
      expect(
        stillReferencing,
        isEmpty,
        reason:
            'these screens used to opt a duplicate "goes back" button into '
            'their own AppBar; none of them should reference the removed '
            'widget any more — each already has its own back affordance '
            '(a Material AppBar auto-back, or an explicit leading back '
            'button on bot_chat_screen)',
      );
    });

    test('the widget file itself is gone', () {
      expect(
        File(
          'lib/core/widgets/app_main_menu_button.dart',
        ).existsSync(),
        isFalse,
        reason: 'dead code left behind after the button was removed',
      );
    });
  });
}
