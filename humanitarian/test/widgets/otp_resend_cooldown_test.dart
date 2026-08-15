// Pins that "Resend" tells the user when it will work again.
//
// WHY THIS FILE EXISTS (E5)
// The OTP screen offered a Resend button that was tappable the instant the
// screen opened and every instant after. The server has enforced a 60-second
// per-phone cooldown the whole time (auth.OTPResendCooldown, applied in
// handlers/auth.go), so the second tap was never going to produce a code — it
// produced a 429 whose `retry_after` the app then threw away and rendered as a
// bare "Please wait before requesting another code."
//
// So the user's model was "this button is broken" when the truth was "this
// button works in 47 seconds". That is the whole defect: not a missing limit,
// a missing *statement* of a limit that already existed.
//
// TWO SOURCES, ONE COUNTDOWN
// The countdown is seeded from a successful send (the client knows the
// server's cooldown constant) and re-seeded from a 429's `retry_after` (the
// server knows better — a progressive phone lockout can be hours, not
// seconds). That is why the client's constant is a starting guess and never
// the authority, and why the longer of the two always wins.
//
// TIME IN THESE TESTS
// Everything here runs under `testWidgets`, whose binding installs a fake
// clock: `tester.pump(duration)` advances the periodic timer without the suite
// actually waiting. A cooldown test that slept would take minutes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/controllers/login.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/verification.dart';

Widget _otpScreen() => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  home: const VerificationPage(),
);

/// The resend control, found by role rather than by its (changing) label.
Finder get _resendButton => find.byType(TextButton);

void main() {
  late LoginController controller;

  setUp(() {
    Get.reset();
    controller = Get.put(LoginController());
  });
  tearDown(Get.reset);

  group('the controller owns the cooldown', () {
    testWidgets('a fresh controller is not cooling down', (tester) async {
      expect(controller.resendCooldown.value, 0);
      expect(controller.canResendOtp, isTrue);
    });

    testWidgets('a cooldown blocks resend, then clears itself', (tester) async {
      controller.startResendCooldown(3);
      expect(controller.resendCooldown.value, 3);
      expect(controller.canResendOtp, isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(controller.resendCooldown.value, 1);
      expect(controller.canResendOtp, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(controller.resendCooldown.value, 0);
      expect(
        controller.canResendOtp,
        isTrue,
        reason: 'the button has to become usable again on its own',
      );
    });

    testWidgets('a longer server cooldown replaces a shorter running one', (
      tester,
    ) async {
      // The progressive per-phone lockout answers `retry_after` in hours. The
      // client's 60-second guess must never shorten that.
      controller.startResendCooldown(LoginController.resendCooldownSeconds);
      controller.startResendCooldown(7200);
      await tester.pump(const Duration(seconds: 90));

      expect(
        controller.resendCooldown.value,
        greaterThan(LoginController.resendCooldownSeconds),
        reason: 'a 2-hour lockout was overwritten by the local guess',
      );
      controller.clearPendingOtp();
    });

    testWidgets('a shorter value never shortens a running cooldown', (
      tester,
    ) async {
      controller.startResendCooldown(120);
      controller.startResendCooldown(5);
      expect(
        controller.resendCooldown.value,
        120,
        reason:
            'the longer wait is the true one; taking the smaller would invite '
            'a tap the server will refuse',
      );

      await tester.pump(const Duration(seconds: 121));
      expect(controller.resendCooldown.value, 0);
    });

    testWidgets('clearing the pending OTP ends the cooldown with it', (
      tester,
    ) async {
      controller.startResendCooldown(60);
      controller.clearPendingOtp();
      expect(
        controller.resendCooldown.value,
        0,
        reason: "a new number must not inherit the previous number's wait",
      );
    });
  });

  group('the OTP screen shows the remaining wait', () {
    testWidgets('a cooling-down resend is disabled and says when', (
      tester,
    ) async {
      controller.pendingPhone.value = '9647701111111';
      await tester.pumpWidget(_otpScreen());
      controller.startResendCooldown(45);
      await tester.pump();

      expect(
        find.textContaining('0:45'),
        findsOneWidget,
        reason: 'the wait has to be visible, not merely enforced',
      );
      expect(
        tester.widget<TextButton>(_resendButton).onPressed,
        isNull,
        reason: 'a button that cannot do anything must not look tappable',
      );

      // Stop the ticker, or the tree is torn down with a timer still pending.
      controller.clearPendingOtp();
      await tester.pump();
    });

    testWidgets('with no cooldown it offers the plain resend label', (
      tester,
    ) async {
      controller.pendingPhone.value = '9647701111111';
      await tester.pumpWidget(_otpScreen());
      await tester.pump();

      expect(find.text('Resend OTP'), findsOneWidget);
      expect(tester.widget<TextButton>(_resendButton).onPressed, isNotNull);
    });

    testWidgets('the countdown is minutes:seconds, not raw seconds', (
      tester,
    ) async {
      controller.pendingPhone.value = '9647701111111';
      await tester.pumpWidget(_otpScreen());
      controller.startResendCooldown(125);
      await tester.pump();

      expect(
        find.textContaining('2:05'),
        findsOneWidget,
        reason: '"125" is not a duration a person reads at a glance',
      );

      controller.clearPendingOtp();
      await tester.pump();
    });
  });
}
