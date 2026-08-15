import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/controllers/login.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/widgets/auth_inline_error.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final LoginController _loginController = Get.isRegistered<LoginController>()
      ? Get.find<LoginController>()
      : Get.put(LoginController());
  final TextEditingController _otpController = TextEditingController();

  /// A16 — the code no longer signs anybody in. A correct one earns the right
  /// to choose a password (the next screen); a number that ALREADY has one is
  /// told to use it, because a code must never stand in for a password.
  ///
  /// What used to live here — persisting the session, refreshing the profile,
  /// registering for push, routing by registration status — moved to
  /// completeSignInAndRoute() in core/auth_navigation.dart, because three
  /// screens now finish a sign-in and they must all finish it the same way.
  Future<void> _verifyOtp() async {
    final outcome = await _loginController.verifyOtp(
      _otpController.text.trim(),
    );
    if (!mounted) return;
    switch (outcome) {
      case OtpVerifyOutcome.setPassword:
        AppHaptics.success();
        // Keep the code screen off the back stack: the ticket is single-use, so
        // returning here would only offer a code that can no longer be spent.
        Get.offNamed(AppRoutes.authCreatePassword);
      case OtpVerifyOutcome.passwordAlreadySet:
        // Not a failure the user can fix here. The message is already set; the
        // button below turns into the way out (see _passwordAlreadySet).
        AppHaptics.error();
        setState(() => _passwordAlreadySet = true);
      case OtpVerifyOutcome.failed:
        if (_loginController.errorMessage.value.isNotEmpty) {
          AppHaptics.error();
        }
    }
  }

  /// True once the server has said this number signs in with a password. The
  /// screen then stops offering a code and offers the sign-in screen instead —
  /// an error with no way out is a dead end (5.7).
  bool _passwordAlreadySet = false;

  Future<void> _resendOtp() async {
    await _loginController.resendOtp();
  }

  // ─── Resend control (E5) ────────────────────────────────────────────────

  /// A remaining wait, written the way a person reads a duration.
  ///
  /// `m:ss`, not a bare second count: the server's escalating lockout answers
  /// in hours, so "7200" would be shown where "120:00" is meant.
  ///
  /// Wrapped in an LTR isolate for the same reason the phone number above is
  /// (#39): under an Arabic or Kurdish locale the ambient RTL direction would
  /// otherwise mirror "1:05" into "05:1". Written as escapes, not as the
  /// literal characters, because invisible direction marks in source are a
  /// lint (`text_direction_code_point_in_literal`) and rightly so.
  static String _formatCooldown(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '\u2066$minutes:$seconds\u2069';
  }

  /// The button under the Verify action — either "resend the code" or, once
  /// there is nothing left to verify, the way back to sign-in.
  ///
  /// The two modes are built as one control so the label and the action can
  /// never disagree. They previously could: while a resend was in flight the
  /// button still read "Resend OTP" but its tap handler navigated away to the
  /// login screen, throwing away the code that was mid-send.
  Widget _buildResendControl(bool hasPendingPhone) {
    final canOfferResend = hasPendingPhone && !_passwordAlreadySet;
    if (!canOfferResend) {
      return TextButton(
        onPressed: () => Get.offAllNamed(AppRoutes.authLogin),
        child: Text('Back to login'.tr),
      );
    }

    final secondsLeft = _loginController.resendCooldown.value;
    final waiting = secondsLeft > 0;
    final busy = _loginController.isLoading.value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          // Disabled, not hidden: a control that vanishes and returns is
          // harder to find than one that visibly counts down (5.8).
          onPressed: (waiting || busy) ? null : _resendOtp,
          child: Text(
            waiting
                ? 'Resend in @time'.trParams({
                    'time': _formatCooldown(secondsLeft),
                  })
                : 'Resend OTP'.tr,
          ),
        ),
        if (waiting)
          // The reason, once, under the button — the countdown alone says
          // "wait" without saying why anything is being withheld (5.9).
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'A code was just sent. You can ask for another shortly.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageTopBar(title: 'Secure Verification'),
              const SizedBox(height: 18),
              GlassPanel(
                padding: const EdgeInsets.all(24),
                child: Obx(() {
                  final pendingPhone = _loginController.pendingPhone.value;
                  final hasPendingPhone = pendingPhone.isNotEmpty;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPendingPhone
                            ? 'Enter the 6-digit code sent to @phone'.trParams({
                                // #39 — isolate the embedded number as LTR
                                // (U+2066 LRI ... U+2069 PDI) so its digit
                                // grouping doesn't mirror when this sentence
                                // renders inside an RTL (Arabic/Kurdish)
                                // locale, while the rest of the sentence
                                // still flows RTL normally.
                                'phone':
                                    '\u2066${formatPhoneForDisplay(pendingPhone)}\u2069',
                              })
                            : 'Request an OTP from the login page first.'.tr,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        enabled:
                            hasPendingPhone &&
                            !_passwordAlreadySet &&
                            !_loginController.isLoading.value,
                        maxLength: 6,
                        onSubmitted: (_) => _verifyOtp(),
                        decoration: InputDecoration(
                          labelText: 'Verification code'.tr,
                          hintText: 'Enter the 6-digit code'.tr,
                          counterText: '',
                        ),
                      ),
                      // E4 — this line used to hardcode `Colors.redAccent`,
                      // which measures 3.19:1 on this card. The shared widget
                      // draws it in the themed `consequence` token instead,
                      // the same one the sign-in screen behind it uses.
                      AuthInlineError(
                        message: _loginController.errorMessage.value,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              hasPendingPhone &&
                                  !_passwordAlreadySet &&
                                  !_loginController.isLoading.value
                              ? _verifyOtp
                              : (_passwordAlreadySet
                                    ? () => Get.offAllNamed(AppRoutes.authLogin)
                                    : null),
                          child: _loginController.isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _passwordAlreadySet
                                      ? 'Go to sign in'.tr
                                      : 'Verify OTP'.tr,
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(child: _buildResendControl(hasPendingPhone)),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
