// Pins the Menu button the client asked for on every page (J7).
//
// WHY THIS FILE EXISTS
// J7: "a Menu button on every app page and a Back button on every page and
// section — بحيث يمكن للمستخدم الوصول إلى القائمة الرئيسية في أي وقت", so the
// user can reach the main menu at any time.
//
// Back was largely unified already: AppScreen draws one whenever the route can
// pop, and 46 screens reach that frame through SectionScaffold. The menu half
// did not exist anywhere — `openDrawer`, `endDrawer` and `Drawer(` returned
// zero hits across the whole app, so from a screen three pushes deep the only
// way back to the main menu was pressing Back three times.
//
// WHAT "THE MAIN MENU" IS HERE
// This app has no drawer. Its main menu is the dashboard: AppRoutes.home, the
// five-tab screen everything else is pushed on top of. So the button pops back
// to it rather than sliding a panel out — and it lands on the Home tab, because
// arriving at the main menu on whichever tab you last touched is not "the main
// menu", it is where you were.
//
// WHY BOTH A WIDGET TEST AND A SOURCE TEST
// The widget group proves the behaviour: the button appears exactly where Back
// appears, and pressing it really does unwind the stack. The source group
// covers the screens that build their own AppBar instead of using the shared
// frame — a widget test cannot tell you which files forgot to opt in, and
// "eleven files never picked up the shared chrome" was the actual defect.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/widgets/app_main_menu_button.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/localization/app_translations.dart';

/// Screens that build their own `AppBar` and are PAGES — somewhere the user
/// navigates to, reads, and may want to leave. Every one of these needs the
/// button, because none of them goes through AppScreen.
const _ownAppBarPages = <String>[
  'lib/modules/auth/screens/edit_profile.dart',
  'lib/modules/bot/screens/bot_chat_screen.dart',
  'lib/modules/chat/screens/case_chat_conversation_screen.dart',
  'lib/modules/chat/screens/chat_conversation_screen.dart',
  'lib/modules/donations/screens/donation_details_screen.dart',
  'lib/modules/donations/screens/donations_screen.dart',
  'lib/modules/marriage/screens/marriage_chat_conversation_screen.dart',
  'lib/widgets/firebase_screen_add.dart',
];

/// The other three `AppBar` users are full-screen IMAGE VIEWERS — a transparent
/// bar over a pinch-to-zoom gallery, opened on top of the page you were already
/// reading. They are deliberately excluded: a menu jump from a lightbox would
/// throw the user out of the gallery AND off the page underneath it, which is
/// not what "reach the main menu" asks for. Listed here so the exclusion is a
/// recorded decision rather than three files someone forgot.
const _lightboxes = <String>[
  'lib/modules/community/screens/community_detail_screen.dart',
  'lib/modules/community/screens/community_services_section.dart',
  'lib/modules/receipts/screens/aid_receipts_screen.dart',
];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('the shared frame carries the menu button', () {
    setUp(() => dashboardTabNotifier.value = 3);

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

    testWidgets('it is not shown on the main menu itself', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // The root route cannot pop, so there is neither a Back nor a Menu
      // button — you are already there.
      expect(find.byType(AppMainMenuButton), findsNothing);
    });

    testWidgets('it appears on a pushed page, beside Back', (tester) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open inner page'));
      await tester.pumpAndSettle();

      expect(find.text('Inner'), findsOneWidget);
      expect(find.byType(AppMainMenuButton), findsOneWidget);
      // The glyph matters as much as the widget: ☰ is what "زر القائمة" means
      // to the person holding the phone.
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    });

    testWidgets('pressing it returns to the main menu', (tester) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open inner page'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('open inner page'),
        findsOneWidget,
        reason:
            'the stack must be unwound to the root — a menu button that only '
            'pops one route is a second Back button',
      );
      expect(
        dashboardTabNotifier.value,
        0,
        reason:
            'arriving at the main menu on whichever tab you last opened is '
            'not the main menu, it is where you already were',
      );
    });
  });

  group('the screens with their own AppBar opted in', () {
    test('every page that builds its own AppBar offers the button', () {
      final missing = _ownAppBarPages
          .where((p) => !_read(p).contains('AppMainMenuButton'))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'these screens never go through AppScreen, so they inherit '
            'nothing — J7 reproduced precisely because eleven files were in '
            'this position',
      );
    });

    test('the image viewers are left out on purpose', () {
      for (final path in _lightboxes) {
        expect(
          _read(path).contains('AppMainMenuButton'),
          isFalse,
          reason:
              '$path is a full-screen image viewer opened over a page. A menu '
              'jump from a lightbox drops the user out of the gallery and off '
              'the page beneath it. If this is ever reconsidered, change the '
              'decision here first.',
        );
      }
    });
  });

  group('the label is real in Arabic', () {
    test('it does not render English on an Arabic screen', () {
      final keys = AppTranslations().keys;
      const key = 'Main menu';
      expect(keys['en_US']![key], isNotNull);
      final ar = keys['ar_SA']![key];
      expect(ar, isNotNull, reason: 'no Arabic entry for the menu button');
      expect(
        ar,
        isNot(key),
        reason: '`.tr` returns the key when the entry is missing',
      );
    });
  });
}
