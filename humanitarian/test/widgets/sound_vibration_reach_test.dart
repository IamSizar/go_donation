// Pins that the sounds & vibration control is reachable from a settings menu.
//
// WHY THIS FILE EXISTS (K26)
// The client asked for "full user control over sounds and vibration from an
// app-settings menu — enable or mute". The control itself was already built
// and correct: `AppMute` persists the choice and `AppSound`, `AppHaptics` and
// `AppVoice` each return early when it is set, so one switch really does
// silence chimes, vibration and spoken summaries.
//
// What was missing was a door. Its only UI was `_MutePreferenceCard` inside
// `ProfileSection` (lib/modules/auth/screens/profile.dart), and the only thing
// in the app that navigates to `ProfileSection` is the AI assistant's
// 'profile' deep link (lib/modules/bot/bot_navigation.dart). So the setting
// existed, worked, and could only be found by asking a chatbot to open your
// profile — neither the الإعدادات tab nor the profile menu offered it.
//
// WHY THIS IS A SOURCE TEST AND NOT ONLY A WIDGET TEST
// Same reasoning as partners_doors_test.dart: the defect is not what a screen
// renders, it is which screens offer a route to a setting at all. A widget
// test can only check the screen it was pointed at, and the failure mode here
// is precisely that nobody pointed at the right screen. The widget group below
// then pins the behaviour of the row itself, which a source test cannot see.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_mute.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/widgets/sound_vibration_row.dart';

/// The menus a user browses looking for a setting.
///
/// `profile_menu_screen.dart` is the account hub behind the top-right avatar —
/// it already holds the Language, Dark mode and Notifications switches.
/// `settings_section.dart` was the الإعدادات bottom-nav tab and is now a
/// shared widget toolkit with no screen of its own (that tab was removed and
/// folded into Profile), kept in the list in case a sound door is ever added
/// there directly. A sound switch belongs in one of them; `profile.dart`
/// (assistant-only) does not count, which is the whole point.
// control_settings_screen.dart joined the list — and profile_menu_screen left
// it — when the loose preference rows moved off the profile menu and into
// Settings & Preferences. The RULE this test enforces is unchanged: the
// control must live in exactly one settings hub. Only the hub moved.
const _settingsHubs = <String>[
  'lib/modules/auth/screens/control_settings_screen.dart',
  'lib/widgets/settings_section.dart',
];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// How many times [source] places the sounds & vibration control on screen.
int _muteDoors(String source) =>
    RegExp(r'SoundVibrationRow\(\)').allMatches(source).length;

void main() {
  group('the sounds & vibration switch is reachable from settings', () {
    test('a settings hub offers it', () {
      final doorsPerHub = <String, int>{
        for (final path in _settingsHubs) path: _muteDoors(_read(path)),
      };
      final total = doorsPerHub.values.fold(0, (a, b) => a + b);

      expect(
        total,
        1,
        reason:
            'found $doorsPerHub. The control must be in exactly one settings '
            'menu: zero means it is still assistant-only (K26), and more than '
            'one is the menu duplication the redesign removed.',
      );
    });

    test('it is not left behind the assistant deep link alone', () {
      // The assistant route still opens ProfileSection, and that screen keeps
      // its own mute card — that is fine, it is the same setting, not a second
      // destination. What must never again be true is that the deep link is
      // the ONLY way there.
      final botOnly =
          _read('lib/modules/bot/bot_navigation.dart').contains('ProfileSection');
      final inSettings = _settingsHubs
          .map((p) => _muteDoors(_read(p)))
          .fold(0, (a, b) => a + b);

      expect(
        botOnly && inSettings == 0,
        isFalse,
        reason:
            'the assistant deep link is not a settings menu — a user who never '
            'opens the chatbot has no way to mute the app',
      );
    });
  });

  group('the row controls the real mute state', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();
      await AppMute.set(false);
    });

    Widget harness() => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: const Scaffold(body: SoundVibrationRow()),
    );

    testWidgets('it says what it controls, in words', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // Not "Mute" alone: an icon plus a one-word label leaves the user
      // guessing whether vibration is included, which is exactly what the
      // client asked to be able to control.
      expect(find.text('Mute sounds & vibration'), findsOneWidget);
    });

    testWidgets('flipping it mutes sounds and haptics for real', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(AppMute.isMuted, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        AppMute.isMuted,
        isTrue,
        reason:
            'the switch must drive AppMute itself — AppSound, AppHaptics and '
            'AppVoice all gate on it, so a row with its own local bool would '
            'look like it worked and silence nothing',
      );
      expect(
        sharedPreferences.getBool('app_muted'),
        isTrue,
        reason: 'the choice has to survive a restart',
      );
    });

    testWidgets('it reflects a choice made earlier', (tester) async {
      await AppMute.set(true);

      await tester.pumpWidget(harness());
      await tester.pump();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(
        toggle.value,
        isTrue,
        reason:
            'a settings row that opens in the wrong position tells the user '
            'their app is unmuted when it is silent',
      );
    });
  });
}
