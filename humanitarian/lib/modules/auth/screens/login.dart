import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // LengthLimitingTextInputFormatter
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/auth_navigation.dart';

import '../../../widgets/auth_ui.dart';
import '../../../controllers/login.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );

    final subtitleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
      height: 1.5,
    );

    return AuthScaffold(
      child: AuthGlassCard(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: AuthBadge(
                icon: Icons.lock_rounded,
                label: 'Secure sign in',
              ),
            ),
            const SizedBox(height: 28),
            Text('Welcome back'.tr, style: titleStyle),
            const SizedBox(height: 10),
            Text(
              'Sign in to manage your impact, stay connected, and continue your humanitarian journey.'
                  .tr,
              style: subtitleStyle,
            ),
            const SizedBox(height: 28),
            const _LoginForm(),
            const SizedBox(height: 14),
            Center(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    "Don't have an account?".tr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Get.toNamed('/register'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    child: Text('Create one'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final LoginController _loginController = Get.isRegistered<LoginController>()
      ? Get.find<LoginController>()
      : Get.put(LoginController());

  final TextEditingController _phoneController = TextEditingController();

  // Phase 19b — OTP delivery mode toggle. 'real' (default) sends via OTPIQ
  // → WhatsApp first, SMS fallback. 'demo' skips OTPIQ and the backend
  // returns the static demo code (123456) for development without burning
  // OTPIQ credit. Demo is only honored when the backend has
  // OTP_DEMO_ENABLED=1; otherwise it falls back to "demo disabled" error.
  String _otpMode = 'real';

  void _completeLogin(Map<String, dynamic> user) {
    sharedPreferences.setString('id_user', user['id'].toString());
    sharedPreferences.setString('phone_user', (user['phone'] ?? '').toString());
    sharedPreferences.setString('name_user', user['name'].toString());
    // Phase 27.3 — now that we know the user id, register the FCM device
    // row so this device can receive push notifications in the user's
    // preferred language. Fire-and-forget so navigation doesn't block.
    unawaited(PushRegistration.registerNow());
    goToPostLoginDestination();
  }

  @override
  void initState() {
    super.initState();
    // Phase 19c — pendingPhone is stored in the full international format
    // ("9647508582031"). Strip the 964 prefix when re-populating so the
    // input field stays local-only ("7508582031") and matches the locked
    // +964 chip beside it.
    final pending = _loginController.pendingPhone.value;
    _phoneController.text = pending.startsWith('964') && pending.length > 3
        ? pending.substring(3)
        : pending;
  }

  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    // Phase 19c — auto-prepend the Iraq country code so the user only ever
    // types their local 10-digit number. Backend's NormalizePhone would
    // accept either format anyway, but normalizing here keeps the
    // pendingPhone display + verify-screen header consistent.
    final localDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final normalizedPhone = _normalizeLocalPhone(localDigits);

    debugPrint('Logging in with phone number: $normalizedPhone (mode=$_otpMode)');

    final sent = await _loginController.sendOtp(normalizedPhone, mode: _otpMode);
    if (sent) {
      Get.toNamed('/verify');
    }
  }

  /// Convert a locally-typed phone to the full international form.
  ///
  ///   7508582031     → 9647508582031   (10 digits → add 964)
  ///   07508582031    → 9647508582031   (11 digits, leading 0 → strip + add 964)
  ///   anything else  → returned as-is (validator should have already rejected)
  String _normalizeLocalPhone(String digits) {
    if (digits.length == 11 && digits.startsWith('0')) {
      return '964${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '964$digits';
    }
    return digits;
  }

  Future<void> _handleGoogleLogin() async {
    final result = await _loginController.signInWithGoogle();
    if (result != null) {
      _completeLogin(result);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(
            () => _loginController.errorMessage.value.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _loginController.errorMessage.value,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Text(
            'Phone number'.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          // Phase 19c — phone field with locked +964 prefix tile. The user
          // types ONLY the local number (e.g. 7508582031, 10-11 digits).
          // _normalizeLocalPhone() prepends 964 before we hand the value
          // to sendOtp(). digitsOnly formatter prevents pasting spaces /
          // + / hyphens that the backend would have to strip anyway.
          TextFormField(
            controller: _phoneController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: Colors.white,
            decoration: authInputDecoration(
              label: 'Phone',
              hintText: '750 858 2031',
              icon: Icons.phone_outlined,
            ).copyWith(
              // Replace the generic phone-icon prefix with a chip that
              // clearly tells the user the country code is already there.
              prefixIcon: const _CountryCodeChip(),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              hintText: '750 858 2031',
            ),
            keyboardType: TextInputType.number,
            // Group digits with spaces as they type ("750 858 2031"). The
            // value is digit-stripped before submit, so the spaces are purely
            // cosmetic. 14 chars fits "0750 858 2031".
            inputFormatters: [
              PhoneSpaceInputFormatter(),
              LengthLimitingTextInputFormatter(14),
            ],
            textInputAction: TextInputAction.done,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number'.tr;
              }
              final digits = value.replaceAll(RegExp(r'\D'), '');
              // Accept 10 digits (e.g. 7508582031) OR 11 with a leading
              // 0 (e.g. 07508582031). Both normalize to +964 + 10 digits.
              if (digits.length == 10) return null;
              if (digits.length == 11 && digits.startsWith('0')) return null;
              return 'Enter 10 digits (or 11 starting with 0)'.tr;
            },
            onFieldSubmitted: (_) => _handleSendOtp(),
          ),
          const SizedBox(height: 18),
          Text(
            'We will send a 6-digit code to verify your number.'.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          // Phase 19b — OTP delivery mode picker. Two visual segments
          // (Real / Demo) so the user can swap between OTPIQ-backed
          // verification and the local-dev "always 123456" flow.
          _OtpModePicker(
            value: _otpMode,
            onChanged: (next) => setState(() => _otpMode = next),
          ),
          const SizedBox(height: 24),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loginController.isLoading.value
                    ? null
                    : _handleSendOtp,
                icon: _loginController.isLoading.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Color(0xFF0B385D),
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.sms_rounded),
                label: Text(
                  'Send OTP'.tr,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B385D),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: Colors.white.withValues(alpha: 0.22),
                  thickness: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or continue with',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: Colors.white.withValues(alpha: 0.22),
                  thickness: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loginController.isLoading.value
                    ? null
                    : _handleGoogleLogin,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _loginController.isLoading.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              'G',
                              style: TextStyle(
                                color: Color(0xFF0B385D),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Continue with Google'.tr,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _OtpModePicker — small segmented control letting the user choose how
/// the next OTP is delivered.
///
///   Real — call OTPIQ; user receives the code via WhatsApp (SMS fallback).
///   Demo — backend skips OTPIQ and returns the static demo code "123456"
///          in the response (only allowed when OTP_DEMO_ENABLED=1 on the
///          server). Use this for development without spending credit.
///
/// Visuals: glass-card style to match the rest of the login screen.
/// Stateless — parent owns the selected mode and re-renders on change.
class _OtpModePicker extends StatelessWidget {
  const _OtpModePicker({required this.value, required this.onChanged});

  final String value; // 'real' | 'demo'
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _Segment(
            label: 'Real OTP'.tr,
            sub: 'WhatsApp · SMS'.tr,
            icon: Icons.verified_rounded,
            selected: value == 'real',
            onTap: () => onChanged('real'),
          ),
          _Segment(
            label: 'Demo OTP'.tr,
            sub: 'Code: 123456'.tr,
            icon: Icons.bug_report_rounded,
            selected: value == 'demo',
            onTap: () => onChanged('demo'),
          ),
        ],
      ),
    );
  }
}

/// _Segment — one of the two pills inside _OtpModePicker. Selected state
/// is the white fill that mirrors the primary CTA button below.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected
                      ? const Color(0xFF0B385D)
                      : Colors.white.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF0B385D)
                        : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF0B385D).withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// _CountryCodeChip — visually-locked Iraq country code shown as the
/// prefix of the phone input. NOT interactive; the user can't change it.
///
/// Layout: 🇮🇶  +964  │   (flag · code · vertical divider)
/// The divider sits flush against the cursor so the typed digits look
/// like a natural continuation of the prefix.
class _CountryCodeChip extends StatelessWidget {
  const _CountryCodeChip();

  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flag emoji — renders the country glyph on platforms that
          // support emoji-flags (iOS, most modern Android). On Android
          // builds without emoji-flag fonts the chip still reads as
          // "+964" so the meaning is intact.
          Text('🇮🇶', style: TextStyle(fontSize: 18, color: fg)),
          const SizedBox(width: 8),
          Text(
            '+964',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          // Vertical divider — purely visual, separates the locked prefix
          // from the editable digits.
          Container(
            width: 1,
            height: 20,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
