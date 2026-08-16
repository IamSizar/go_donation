// Pins the Contact page's real contact details (K13, app half).
//
// WHY THIS FILE EXISTS
// The client asked "تواصل معنا" for a logo, a phone number, WhatsApp, an email
// address, social media links and an address. Backend cea459b + migration 112
// added all six as real columns and serves them on GET /api/content/:slug. The
// app drew none of them: content_page_screen.dart rendered `title` + `body` and
// nothing else, so the Contact page was one sentence with nothing on it to tap.
// Reproduced before writing anything — `grep -rn "contact_phone" lib` found
// nothing.
//
// THE HALF THAT MATTERS MOST IS THE EMPTY ONE
// Every one of these fields is EMPTY in production today: migration 112 added
// no backfill, deliberately, because there is nothing anywhere to derive a
// phone number or an address from. So the state this screen is actually in on
// the day it ships is "all six blank", and the failure to avoid is a Contact
// card carrying an empty row, a `tel:` link that dials nothing, or a WhatsApp
// button with no number behind it. A field that has no value is not drawn at
// all.
//
// The link builders are pure functions and are tested as such, because the bug
// being prevented lives in them: `Uri.tryParse('tel:(0750) 858-2031')` returns
// null for the spaces and brackets a human types into a public phone number,
// and the partner screen's `launchPartnerExternal` then returns in silence — a
// tappable control that does nothing, which this project has already shipped
// once and refuses to ship again.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/shared/utils/contact_links.dart';

import '../support/fake_http.dart';

/// One `GET /api/content/contact` body, in the shape the Go handler returns.
String _contactPage({
  String bodyEn = 'Reach us by email or phone.',
  String logoPath = '',
  String phone = '',
  String whatsapp = '',
  String email = '',
  String socialLinks = '',
  String addressEn = '',
}) => jsonEncode({
  'success': true,
  'content': {
    'slug': 'contact',
    'title_en': 'Contact Us',
    'body_en': bodyEn,
    'logo_path': logoPath,
    'contact_phone': phone,
    'contact_whatsapp': whatsapp,
    'contact_email': email,
    'social_links': socialLinks,
    'address_en': addressEn,
    'address_ar': '',
    'address_ckb': '',
    'address_kmr': '',
  },
  'sections': const [],
});

Widget _screen() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  translations: AppTranslations(),
  locale: const Locale('en', 'US'),
  home: const ContentPageScreen(slug: 'contact', titleKey: 'Contact Us'),
);

Future<void> _open(WidgetTester tester, String body) async {
  await withHttp(FakeHttpOverrides(HttpBehaviour.ok, body: body), () async {
    await tester.pumpWidget(_screen());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  group('nothing supplied yet degrades to nothing drawn', () {
    testWidgets('no contact card at all when all six fields are empty', (
      tester,
    ) async {
      await _open(tester, _contactPage());

      expect(
        find.byKey(const Key('contact_details')),
        findsNothing,
        reason:
            'this is the state every Contact page is in today; an empty card '
            'is worse than no card',
      );
      expect(find.byKey(const Key('contact_phone')), findsNothing);
      expect(find.byKey(const Key('contact_whatsapp')), findsNothing);
      expect(find.byKey(const Key('contact_email')), findsNothing);
      expect(find.byKey(const Key('contact_address')), findsNothing);
      expect(find.byKey(const Key('contact_logo')), findsNothing);
      expect(find.byKey(const Key('contact_socials')), findsNothing);
      // The page's own prose still renders — this is not an empty page.
      expect(find.text('Reach us by email or phone.'), findsOneWidget);
    });

    testWidgets('a single supplied field draws only that field', (
      tester,
    ) async {
      await _open(tester, _contactPage(email: 'info@example.org'));

      expect(find.byKey(const Key('contact_details')), findsOneWidget);
      expect(find.byKey(const Key('contact_email')), findsOneWidget);
      expect(find.text('info@example.org'), findsOneWidget);
      // Not a blank row each.
      expect(find.byKey(const Key('contact_phone')), findsNothing);
      expect(find.byKey(const Key('contact_whatsapp')), findsNothing);
      expect(find.byKey(const Key('contact_address')), findsNothing);
    });

    testWidgets('contact details alone are content, not an empty page', (
      tester,
    ) async {
      // The owner may fill in the details and leave the prose blank. That page
      // has something on it, so the K12 empty state must not claim otherwise.
      await _open(tester, _contactPage(bodyEn: '', phone: '0750 858 2031'));

      expect(find.byType(AppEmpty), findsNothing);
      expect(find.byKey(const Key('contact_phone')), findsOneWidget);
    });
  });

  group('every supplied field is drawn, and drawn as an action', () {
    testWidgets('phone, WhatsApp, email, address, socials and logo', (
      tester,
    ) async {
      await _open(
        tester,
        _contactPage(
          logoPath: 'uploads/logo.png',
          phone: '0750 858 2031',
          whatsapp: '+964 750 858 2031',
          email: 'info@example.org',
          socialLinks: 'https://facebook.com/us\nhttps://t.me/us',
          addressEn: 'Mosul, Al-Majmoua Al-Thaqafiya',
        ),
      );

      expect(find.byKey(const Key('contact_logo')), findsOneWidget);
      expect(find.byKey(const Key('contact_phone')), findsOneWidget);
      expect(find.byKey(const Key('contact_whatsapp')), findsOneWidget);
      expect(find.byKey(const Key('contact_email')), findsOneWidget);
      expect(find.byKey(const Key('contact_address')), findsOneWidget);
      expect(find.byKey(const Key('contact_socials')), findsOneWidget);

      // The number is shown exactly as the owner typed it — it was written for
      // a human to read, not normalized for a database.
      expect(find.text('0750 858 2031'), findsOneWidget);
      expect(find.text('Mosul, Al-Majmoua Al-Thaqafiya'), findsOneWidget);

      // Social links go through the SHARED parser and are named by network,
      // never printed as a raw address (K17's rule, same column shape).
      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
    });

    testWidgets('the address is localized like every other text column', (
      tester,
    ) async {
      await _open(
        tester,
        _contactPage(addressEn: 'Mosul', phone: '', email: ''),
      );

      expect(find.text('Mosul'), findsOneWidget);
    });
  });

  group('a value that cannot make a working link is not offered as one', () {
    test('a phone a human typed still dials', () {
      // The server accepts this on purpose: a public line is legitimately
      // "(0750) 858-2031 ext. 12". Uri.tryParse rejects it verbatim.
      expect(contactDialUri('(0750) 858-2031')?.toString(), 'tel:07508582031');
      expect(contactDialUri('  +964 750 858 2031 ')?.toString(),
          'tel:+9647508582031');
    });

    test('a phone with no digits in it is not a dial action', () {
      expect(contactDialUri('call us any time'), isNull);
      expect(contactDialUri('   '), isNull);
      expect(contactDialUri(''), isNull);
    });

    test('WhatsApp needs a bare number, not a formatted one', () {
      // wa.me accepts digits only; the + and the spaces produce a dead link.
      expect(
        contactWhatsAppUri('+964 750 858 2031')?.toString(),
        'https://wa.me/9647508582031',
      );
      expect(contactWhatsAppUri('ask for Ahmed'), isNull);
      expect(contactWhatsAppUri(''), isNull);
    });

    test('email needs an address, not a sentence', () {
      expect(
        contactEmailUri(' Info@Example.org ')?.toString(),
        'mailto:Info@Example.org',
      );
      expect(contactEmailUri('write to us'), isNull);
      expect(contactEmailUri(''), isNull);
    });

    testWidgets('an undialable phone is shown but not made tappable', (
      tester,
    ) async {
      // Pre-112 rows carry no validation, and a value that reaches the screen
      // without a digit in it must not become a button that dials nothing.
      await _open(tester, _contactPage(phone: 'call us any time'));

      expect(find.text('call us any time'), findsOneWidget);
      expect(
        find.byKey(const Key('contact_phone')),
        findsNothing,
        reason:
            'the keyed row is the ACTION; the value is still readable as text',
      );
    });
  });
}
