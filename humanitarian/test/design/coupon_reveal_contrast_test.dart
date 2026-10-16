// Contrast guard for كوبون الحظ's revealed coupon.
//
// WHY THIS FILE EXISTS
// The revealed coupon used to be amber with white text (2.15:1). R2 #46 moved
// the coupon to the brand's ivory back face; this keeps the original guard —
// the challenge must clear 4.5:1 on whatever the back face is — and reads the
// colour off the widget that actually renders after the reveal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/modules/dashboard/screens/lucky_coupon_screen.dart';

/// The revealed card's fill, mirrored from the screen.
const _ivory = Color(0xFFF3EFE4);

/// WCAG floor for body text. The challenge is 18px w800.
const _kTextFloor = 4.5;

Widget _app(Locale locale) => GetMaterialApp(
  translations: AppTranslations(),
  locale: locale,
  home: const LuckyCouponScreen(),
);

void main() {
  setUp(() async {
    // The reveal plays a haptic, which reads the app's mute setting.
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  group('the revealed challenge is readable on the coupon', () {
    for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
      testWidgets('in ${locale.languageCode}', (tester) async {
        await tester.pumpWidget(_app(locale));
        await tester.pump();

        // Reveal it. Local state only — nothing leaves the device.
        await tester.tap(find.text('Tap to scratch'.tr));
        await tester.pumpAndSettle();

        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.style?.fontSize == 18 && t.style?.color != null)
            .toList();
        expect(texts, isNotEmpty, reason: 'no challenge text on the coupon');

        for (final text in texts) {
          final ratio = contrastRatio(text.style!.color!, _ivory);
          expect(
            ratio,
            greaterThanOrEqualTo(_kTextFloor),
            reason:
                'the challenge renders at ${ratio.toStringAsFixed(2)}:1 on '
                'the coupon',
          );
        }
      });
    }

    test('the front face keeps white text on the brand green', () {
      const green = Color(0xFF2F5D4A);
      expect(inkOn(green), Colors.white);
      expect(
        contrastRatio(Colors.white, green),
        greaterThanOrEqualTo(_kTextFloor),
      );
    });
  });
}
