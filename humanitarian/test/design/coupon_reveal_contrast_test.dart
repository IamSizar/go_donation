// Contrast guard for كوبون الحظ's revealed coupon.
//
// WHY THIS FILE EXISTS
// The revealed coupon is a bright amber card, #F59E0B, and the challenge was
// written across it in white. That is 2.15:1 — measured from rendered pixels on
// an iPhone 17 Pro simulator, on the wheel's identically-coloured slice, since
// the coupon's own reveal cannot be reached without scratching it and writing a
// challenge record to a real account.
//
// 2.15:1 is below even the 3:1 floor for non-text UI. This is 16px w800, which
// is ordinary text — WCAG's large-text allowance starts at 18.66px bold — so
// the bar is 4.5:1 and white missed it by more than half.
//
// It went unnoticed because the reveal is behind an interaction: the screen
// LOOKS fine until you scratch it, and scratching it on the real app is exactly
// what a tester avoids doing to a production account. A widget test has no such
// problem — the scratch is local state with no API call behind it — so this
// reads the colour off the widget that actually renders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/dashboard/screens/lucky_coupon_screen.dart';

/// The revealed card's fill, mirrored from the screen.
const _amber = Color(0xFFF59E0B);

/// WCAG floor for body text. The challenge is 16px w800.
const _kTextFloor = 4.5;

Widget _app(Locale locale) => GetMaterialApp(
  translations: AppTranslations(),
  locale: locale,
  home: const LuckyCouponScreen(),
);

void main() {
  group('the revealed challenge is readable on the amber coupon', () {
    for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
      testWidgets('in ${locale.languageCode}', (tester) async {
        await tester.pumpWidget(_app(locale));
        await tester.pump();

        // Scratch it. Local state only — nothing leaves the device.
        await tester.tap(find.byIcon(Icons.card_giftcard_rounded));
        await tester.pumpAndSettle();

        final revealed = tester.widget<Icon>(
          find.byIcon(Icons.celebration_rounded),
        );
        expect(
          revealed.color,
          isNotNull,
          reason: 'the reveal did not render',
        );

        // The challenge text shares the card with that icon.
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.style?.fontSize == 16 && t.style?.color != null)
            .toList();
        expect(texts, isNotEmpty, reason: 'no challenge text on the coupon');

        for (final text in texts) {
          final ratio = contrastRatio(text.style!.color!, _amber);
          expect(
            ratio,
            greaterThanOrEqualTo(_kTextFloor),
            reason:
                'the challenge renders at ${ratio.toStringAsFixed(2)}:1 on the '
                'amber coupon — white here measures 2.15:1',
          );
        }
      });
    }

    test('the amber fill itself is left alone', () {
      // The fix flips the ink, not the card: the amber is the reward's
      // identity and is shared with the wheel's prize slice.
      expect(inkOn(_amber), isNot(Colors.white));
      expect(
        contrastRatio(inkOn(_amber), _amber),
        greaterThanOrEqualTo(_kTextFloor),
      );
    });

    test('the un-scratched grey card keeps its white text', () {
      // #6B7280 measured 4.83:1 with white on the device — already passing, so
      // it must NOT be flipped along with the amber.
      const grey = Color(0xFF6B7280);
      expect(inkOn(grey), Colors.white);
    });
  });
}
