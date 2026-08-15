// Pins how many ways there are into the partners section, and where the
// Home-screen logos lead.
//
// WHY THIS FILE EXISTS (C1)
// The client counted "شركاؤنا" three or four times over — profile menu,
// خدماتنا, and the bottom of Home — and asked for it in one place. Earlier
// passes removed two duplicates; four navigations to the same screen were
// still standing.
//
// WHY THIS IS A SOURCE TEST AND NOT A WIDGET TEST
// The defect is not what any one screen renders. It is how many screens
// render a door to the same place — a property of the codebase, not of a
// widget tree, and a widget test can only ever check the door it was told to
// look at. The mistake this guards against is someone adding a fifth entry in
// a file nobody thought to write a test for, which is exactly how the
// duplicates accumulated in the first place.
//
// WHAT COUNTS AS A DOOR
// A menu or hub entry, i.e. a standing list of destinations the user browses.
// Deliberately NOT counted: the global search screen and the notification
// router. Those are address lookups — they take the user to whatever they
// asked for or were told about — and a search result for "partners" landing
// on the partners screen is the feature working, not a duplicate menu.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app's two competing navigation hubs.
///
/// `settings_section.dart` is the Settings bottom-nav tab's drawer;
/// `proposal_services_section.dart` is the خدماتنا directory reached from the
/// profile. Partners was listed in BOTH — the only destination in the app that
/// was, which is what marked it out as a mistake rather than a pattern.
const _hubFiles = <String>[
  'lib/widgets/settings_section.dart',
  'lib/modules/proposal/screens/proposal_services_section.dart',
];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// How many times [source] navigates to the partners list screen.
int _partnersScreenDoors(String source) =>
    RegExp(r'const PartnersScreen\(\)').allMatches(source).length;

void main() {
  group('one door into the partners section', () {
    test('exactly one navigation hub offers it', () {
      final doorsPerHub = <String, int>{
        for (final path in _hubFiles) path: _partnersScreenDoors(_read(path)),
      };
      final total = doorsPerHub.values.fold(0, (a, b) => a + b);

      expect(
        total,
        1,
        reason:
            'the partners screen is listed in ${doorsPerHub.entries.where((e) => e.value > 0).map((e) => e.key).join(' and ')}. '
            'The client asked for one place; a second door from a competing '
            'hub is the exact duplication the redesign set out to remove.',
      );
    });

    test('the surviving door is the Settings tab, not the nested one', () {
      // Settings is a bottom-nav tab — one tap from anywhere. خدماتنا is
      // reached through the profile, so keeping that one instead would have
      // buried a section the client specifically asked to feature, and would
      // have broken the check path recorded for K6.
      expect(
        _partnersScreenDoors(_read('lib/widgets/settings_section.dart')),
        1,
      );
      expect(
        _partnersScreenDoors(
          _read('lib/modules/proposal/screens/proposal_services_section.dart'),
        ),
        0,
      );
    });
  });

  group('a partner logo on Home opens that partner', () {
    test('the logo card navigates to the detail screen, not the list', () {
      final source = _read('lib/widgets/dashboard.dart');

      expect(
        source.contains('PartnerDetailScreen(partner: partner)'),
        isTrue,
        reason:
            'tapping a named, pictured organisation and landing on an '
            'undifferentiated list is a mis-wired path, not a redundant one — '
            'PartnerDetailScreen already exists and takes exactly this map',
      );
      expect(
        _partnersScreenDoors(source),
        1,
        reason:
            'the strip should keep its "See all" and nothing else: the logo '
            'now has a destination of its own',
      );
    });
  });
}
