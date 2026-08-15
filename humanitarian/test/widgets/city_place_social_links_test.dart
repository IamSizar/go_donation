// Pins that a place's social links are links, and that one parser reads them.
//
// WHY THIS FILE EXISTS (K17)
// The client listed the fields a City Guide place must carry, ending with
// "روابط التواصل الاجتماعي". They were there — and inert. The phone dialled,
// the email opened mail, the website opened a browser, and the social links
// rendered as a plain `_DetailLine`: a label and a run of text, with nothing to
// tap. On a screen where the three fields beside it are all tappable, that
// reads as broken rather than as absent.
//
// Migration 100 says the column exists to "match partners.social_links, which
// already holds the same kind of value", and the partner page has parsed and
// rendered exactly that value as tappable chips since it shipped. So the fix
// was to stop having two answers to one question: the parser and the network
// labels move to shared/utils and both screens read from there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/shared/utils/social_links.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing — this test needs updating, not deleting');
  }
  return file.readAsStringSync();
}

void main() {
  group('a place\'s social links can be opened', () {
    test('the detail screen renders them as an action, not as text', () {
      final source = _read(
        'lib/modules/community/screens/community_detail_screen.dart',
      );

      expect(
        source.contains('openSocialLink'),
        isTrue,
        reason:
            'the phone, email and website on this screen all launch something; '
            'a social link that only sits there is the odd one out',
      );
      // The specific shape of the old bug: the links handed to the read-only
      // line widget as one blob of text.
      expect(
        RegExp(
          r"_DetailLine\(\s*icon: Icons\.public_rounded,\s*label: 'city_social_links',\s*value: socials,",
        ).hasMatch(source),
        isFalse,
        reason: 'that is the inert rendering this row is about',
      );
    });

    test('one parser serves both screens', () {
      // Two copies of "split on newlines and commas" would drift the moment
      // someone pasted a semicolon-separated list into one of them.
      final partners = _read(
        'lib/modules/proposal/screens/partners_screen.dart',
      );
      expect(
        partners.contains('List<String> partnerSocialLinks('),
        isFalse,
        reason:
            'the partners screen should now read the shared parser rather than '
            'own a private one',
      );
      expect(partners.contains('socialLinksFrom'), isTrue);
    });
  });

  group('the shared parser', () {
    test('splits the stored value on newlines and commas', () {
      // Both separators are real: migration 035 documents "one URL per line",
      // and the admin form lets staff comma-separate them.
      expect(
        socialLinksFrom(
          'https://facebook.com/a\nhttps://t.me/b, https://x.com/c',
        ),
        ['https://facebook.com/a', 'https://t.me/b', 'https://x.com/c'],
      );
    });

    test('an empty or absent value yields nothing to render', () {
      expect(socialLinksFrom(null), isEmpty);
      expect(socialLinksFrom('   '), isEmpty);
      // Trailing separators are what a half-finished paste leaves behind; they
      // must not become an empty chip that opens nothing.
      expect(socialLinksFrom('https://x.com/c,,\n'), ['https://x.com/c']);
    });

    test('each link is named by its network, not by its URL', () {
      expect(socialNetworkLabel('https://www.facebook.com/place'), 'Facebook');
      expect(socialNetworkLabel('https://wa.me/9647700000000'), 'WhatsApp');
      expect(socialNetworkLabel('https://t.me/place'), 'Telegram');
      expect(socialNetworkLabel('https://x.com/place'), 'X');
      // Unknown hosts still get a word rather than a raw address in a chip.
      expect(socialNetworkLabel('https://example.org/place'), 'Social');
    });
  });
}
