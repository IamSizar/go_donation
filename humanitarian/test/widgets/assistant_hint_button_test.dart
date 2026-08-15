// Pins that every main section carries an AI affordance, and that tapping it
// asks about THAT section.
//
// WHY THIS FILE EXISTS (K28)
// The client asked for two things: an AI chatbot, and "an AI icon beside each
// menu offering a short explanation of that section and answering FAQs". The
// chatbot half was built and is good — a role-aware assistant with a
// four-language FAQ table, a Claude-backed endpoint, and one-tap routing into
// the screen an answer talks about.
//
// The icon half did not exist. `BotChatScreen` had exactly ONE entry point in
// the whole app: a card at the top of الرسائل. So a user standing on دليل
// المدينة wondering what it is had no way to ask, and the shared page frame
// (`AppScreen`, which every section header goes through) had no slot for one.
//
// WHY THE TOPIC IS A ROUTE KEY
// `BotNavigation` already keys every destination in the app ('donate',
// 'market', 'kafala', …) and every `BotQA` that leads somewhere carries the
// matching `actionRoute`. Resolving a section's question from that existing
// data means no second mapping table to drift, and it works per role for free:
// a donor gets the donor QA for 'market', an eligible gets theirs, and a role
// with no QA for a section simply opens the assistant on its normal welcome.
// That last case is why resolution returns null rather than a placeholder —
// seeding a question no role table can answer would produce the assistant's
// "I didn't understand" bubble as a greeting.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/modules/bot/data/bot_strings.dart';
import 'package:flutter_application_1/modules/bot/widgets/assistant_hint_button.dart';

/// Every pushed section a user browses, with the assistant topic it must carry.
///
/// The five bottom-nav TABS are not in this list and are checked separately:
/// their titles live in the persistent `_DashboardTopBar`, not in their own
/// SectionScaffold (each passes `title: ''`), so their icon belongs in that bar
/// beside the tab title — putting it in the page header instead would draw a
/// second, empty header row under the real one.
const _sectionsThatNeedAnIcon = <String, String>{
  'lib/modules/donations/screens/donations_section.dart': 'donate',
  'lib/modules/donations/screens/my_donations_page.dart': 'my_donations',
  'lib/modules/marriage/screens/marriage_search_screen.dart': 'marriage',
  'lib/modules/sponsorship/screens/sponsorship_section.dart': 'kafala',
  'lib/modules/chat/screens/messages_screen.dart': 'messages',
  'lib/modules/support/screens/technical_support_screen.dart': 'support',
  'lib/modules/support/screens/support_section.dart': 'volunteer',
  'lib/modules/proposal/screens/proposal_services_section.dart': 'services',
};

/// The bottom-nav tabs, whose icon lives in the persistent top bar.
const _tabRoutes = <String>['market', 'city_guide', 'marriage'];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('an AI icon sits beside each main section', () {
    test('every listed section declares its assistant topic', () {
      final missing = <String>[];
      _sectionsThatNeedAnIcon.forEach((path, route) {
        if (!_read(path).contains("assistantRoute: '$route'")) {
          missing.add('$path (expected assistantRoute: \'$route\')');
        }
      });

      expect(
        missing,
        isEmpty,
        reason:
            'the client asked for the icon beside EACH menu, not one card in '
            'الرسائل:\n${missing.join('\n')}',
      );
    });

    test('the bottom-nav tabs get one from the persistent top bar', () {
      final topBar = _read(
        'lib/modules/dashboard/screens/dashboard_screen.dart',
      );
      expect(
        topBar.contains('AssistantHintButton'),
        isTrue,
        reason:
            'the tab screens pass title: \'\' because their title is in this '
            'bar — the icon has to be here too, or the four tabs a user spends '
            'most of their time on are the four with no way to ask',
      );
      for (final route in _tabRoutes) {
        expect(
          topBar.contains("'$route'"),
          isTrue,
          reason: 'the top bar has no assistant topic for the $route tab',
        );
      }
    });

    test('the shared page frame is what carries it', () {
      // If the icon were bolted onto each screen's own header, the next
      // section added would quietly ship without one. AppScreen is the single
      // chrome every section header goes through.
      final frame = _read('lib/core/widgets/app_screen.dart');
      expect(frame.contains('assistantRoute'), isTrue);
      expect(
        _read('lib/shared/widgets/glass_ui.dart').contains('assistantRoute'),
        isTrue,
        reason:
            'SectionScaffold is the compatibility shell 46 screens still use; '
            'without a pass-through none of them can offer the icon',
      );
    });
  });

  group('the icon knows which section it is on', () {
    test('a route with a QA in this role resolves to that question', () {
      final topic = assistantTopicFor('donate', roleId: '1', lang: 'en');
      expect(topic, isNotNull);
      expect(topic!.intentId.isNotEmpty, isTrue);
      expect(topic.question.isNotEmpty, isTrue);
    });

    test('the question comes back in the reader\'s language', () {
      final en = assistantTopicFor('donate', roleId: '1', lang: 'en')!;
      final ar = assistantTopicFor('donate', roleId: '1', lang: 'ar')!;

      expect(ar.intentId, en.intentId, reason: 'same intent, different words');
      expect(
        RegExp(r'[A-Za-z]').hasMatch(ar.question),
        isFalse,
        reason:
            'the assistant is opened by typing this question into the chat as '
            'the user — in Arabic it must not be an English sentence',
      );
    });

    test('a role with no QA for the section seeds nothing', () {
      // Volunteers have no marketplace QA. Sending the donor's question with
      // the donor's intent id would land on the assistant's error bubble,
      // because the offline resolver only searches the current role's table.
      expect(assistantTopicFor('marriage', roleId: '3', lang: 'en'), isNull);
    });

    test('an unknown route seeds nothing rather than guessing', () {
      expect(assistantTopicFor('not_a_route', roleId: '1', lang: 'en'), isNull);
    });
  });

  group('the button says what it is', () {
    testWidgets('it is labelled with the assistant, not left as a bare icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        const GetMaterialApp(
          home: Scaffold(body: AssistantHintButton(route: 'donate')),
        ),
      );
      await tester.pump();

      // A lone sparkle glyph is not an explanation of anything. The label is
      // the assistant's own localized name, which is already translated in all
      // four languages — no new vocabulary was invented for this.
      expect(
        find.bySemanticsLabel(BotStrings.of('title', 'en')),
        findsOneWidget,
      );
    });
  });
}
