// The app must not compose the sentences the dashboard shows.
//
// WHAT WENT WRONG
// Every AppEventFirestore.log call wrote an English sentence into `note` —
// "password login succeeded", "Guest sign-in succeeded", "Marketplace order
// from app cart" — and the admin dashboard's live feed prints an event's note
// verbatim. So an operator working entirely in Arabic read English sentences
// down the feed, which is exactly what the owner reported.
//
// The rule now, stated in EventsFeed.tsx and followed by the admin events
// since the start: the app sends MACHINE VALUES, the dashboard composes the
// sentence in the reader's language.
//
// WHY THIS IS A SOURCE TEST
// The call sites are spread across api/, controllers/ and modules/, and what
// matters is that NONE of them writes prose — a property of the whole set, not
// of any one function. Pumping them would need a fake backend per call site
// and would still only cover the ones somebody remembered to pump.
//
// Notes that carry DATA — a case title, an item name, a city, a user's own
// donation message — are untouched and must stay: they are content, not
// sentences, and the dashboard is right to print them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every file that logs an app event.
const _sources = <String>[
  'lib/controllers/login.dart',
  'lib/api/guest_session.dart',
  'lib/api/profile_api.dart',
  'lib/api/module_api.dart',
];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

/// [source] with whole-line comments removed.
///
/// The comments at these call sites QUOTE the prose they replaced — that is
/// the record of why the line looks the way it does. Without this the test
/// fails on its own documentation, which teaches the next person to delete
/// the explanation rather than keep the fix.
String _codeOnly(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// The prose that used to reach an Arabic screen, verbatim.
const _bannedProse = <String>[
  'login succeeded',
  'registration succeeded',
  'sign-in succeeded',
  'User updated profile details',
  'Marketplace order from app cart',
];

void main() {
  group('the app sends machine values, not English sentences', () {
    test('no event note carries English prose', () {
      final offenders = <String>[];
      for (final path in _sources) {
        final source = _codeOnly(_read(path));
        for (final phrase in _bannedProse) {
          if (source.contains("'$phrase") || source.contains(" $phrase'")) {
            offenders.add('$path: "$phrase"');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these strings are printed verbatim by the dashboard feed, so an '
            'Arabic operator reads them in English. Send a machine value and '
            'add a body key in admin-web (npm run check:feed-bodies enforces '
            'the pair).',
      );
    });

    test('the auth method travels as a machine value', () {
      final source = _read('lib/controllers/login.dart');
      expect(
        source.contains("metadata: {'method': method.toLowerCase()}"),
        isTrue,
        reason:
            'the dashboard renders "signed in with a password" from this; '
            'without it the method is only inside the English label and the '
            'sentence cannot be localized',
      );
    });

    test('notes that carry real content are left alone', () {
      // The guard above must not tempt anyone into stripping the useful notes
      // as well: a case title tells the operator WHICH case, and no localized
      // sentence can replace it.
      final source = _read('lib/api/module_api.dart');
      expect(
        source.contains("note: requestBody['public_title']?.toString()"),
        isTrue,
        reason:
            'the case title is content, not prose — the feed is right to print '
            'it, and removing it would make every case row identical',
      );
    });
  });
}
