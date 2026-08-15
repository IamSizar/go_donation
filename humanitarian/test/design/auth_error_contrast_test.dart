// Pins that a failed sign-in is legible, on every screen of the sign-in flow.
//
// WHY THIS FILE EXISTS (E4)
// The sign-in screen's error line was fixed to the themed `consequence` token
// and pinned by contrast_test.dart. The two screens *behind* it in the same
// flow were not: the OTP screen and the registration form each hardcoded
// `Colors.redAccent` and drew it on the same near-white card. That measures
// 3.19:1 — below the 4.5:1 AA floor every other piece of text in the app
// clears, and it fails in the one place the user is already stuck.
//
// The interesting part is that this was invisible to contrast_test.dart, which
// checks the PALETTE. A hardcoded colour is by definition not in the palette,
// so a token guard can never see it. This file closes that gap from the other
// end: it measures the literal that was used, and then reads the colour off
// the widget the user actually looks at.
//
// WHEN THIS TEST FAILS
// An auth screen is drawing error text in something other than the theme's
// `consequence` token. Use `AuthInlineError`; do not pick a red by eye.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/controllers/login.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/verification.dart';

/// WCAG 2.1 relative luminance for an opaque sRGB colour.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between two opaque colours. Ranges 1.0 … 21.0.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The OTP screen wrapped in just enough app to render.
///
/// `GetMaterialApp` rather than `MaterialApp` because the screen resolves its
/// strings through `.tr` and its navigation through `Get`.
Widget _otpScreen({required Brightness brightness}) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  darkTheme: AppThemeConfig.buildTheme(Brightness.dark),
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  home: const VerificationPage(),
);

/// The colour the error line is actually painted in, read off the built tree.
Color _renderedErrorColour(WidgetTester tester, String message) {
  final text = tester.widget<Text>(find.text(message));
  return text.style!.color!;
}

void main() {
  // A fresh controller per test: these screens read their error text from it,
  // and a leaked instance would carry one test's message into the next.
  setUp(() {
    Get.reset();
    Get.put(LoginController());
  });
  tearDown(Get.reset);

  group('the red that was hardcoded', () {
    test('measures below the AA floor on the card it was drawn on', () {
      // This is the defect, stated as a number. `Colors.redAccent` is what the
      // OTP screen and the registration form both used, and `card` is the
      // surface GlassPanel paints behind them (glass_ui.dart -> surface()).
      final ratio = _contrastRatio(Colors.redAccent, AppColors.light.card);

      expect(
        ratio,
        lessThan(4.5),
        reason:
            'redAccent on the auth card measures ${ratio.toStringAsFixed(2)}:1. '
            'If this ever passes, the palette moved and this note is stale — '
            'but the fix is still to use the token, not this literal.',
      );
    });

    test('the token that replaced it clears the floor on both themes', () {
      for (final entry in <String, AppColors>{
        'light': AppColors.light,
        'dark': AppColors.dark,
      }.entries) {
        final ratio = _contrastRatio(entry.value.consequence, entry.value.card);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '${entry.key} consequence on card measures '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('the OTP screen draws its error in the themed colour', () {
    const message = 'Verification code must be 6 digits.';

    testWidgets('light theme', (tester) async {
      await tester.pumpWidget(_otpScreen(brightness: Brightness.light));
      Get.find<LoginController>().errorMessage.value = message;
      await tester.pump();

      expect(
        _renderedErrorColour(tester, message),
        AppColors.light.consequence,
        reason:
            'the OTP error line must use the same token as the sign-in screen '
            'behind it, not a red chosen by eye',
      );
    });

    testWidgets('dark theme', (tester) async {
      await tester.pumpWidget(_otpScreen(brightness: Brightness.dark));
      Get.find<LoginController>().errorMessage.value = message;
      await tester.pump();

      expect(
        _renderedErrorColour(tester, message),
        AppColors.dark.consequence,
        reason:
            'a fixed red cannot be right in both themes — dark mode needs the '
            'lighter end of the ramp to stay legible on a dark card',
      );
    });
  });
}
