import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/core/app_snackbar.dart';

import '../../../api/guest_session.dart';
import '../../../api/links.dart';
import '../../../core/auth_navigation.dart';
import '../../../core/phone_format.dart';
import '../../../widgets/auth_ui.dart';
import '../widgets/localized_country_list.dart';
import '../widgets/otp_boxes.dart';

/// Note #40 — "Account Upgrade and Conversion". A guest enters their phone,
/// verifies it via OTP (reusing the existing public otp/request endpoint),
/// then this screen attaches the verified phone to their guest account
/// (POST /auth/guest/upgrade/verify) and hands off to the SAME
/// "complete your registration" form any brand-new phone signup goes
/// through — full_name/DOB/address/role.
class GuestUpgradeScreen extends StatefulWidget {
  const GuestUpgradeScreen({super.key});

  @override
  State<GuestUpgradeScreen> createState() => _GuestUpgradeScreenState();
}

enum _Step { phone, otp }

class _GuestUpgradeScreenState extends State<GuestUpgradeScreen>
    with LocalizedCountryList<GuestUpgradeScreen> {
  _Step _step = _Step.phone;
  static const String _defaultDialCode = '964';
  String _dialCode = _defaultDialCode;
  String _normalizedPhone = '';
  bool _loading = false;
  String _error = '';

  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // See LocalizedCountryList: without this, the picker below shows every
    // country's own endonym mixed together instead of one language.
    loadCountryList();
  }

  // F3 fix (same race as login.dart) — see
  // LocalizedCountryList.onCountryListLoaded: the picker's key flip
  // rebuilds it at 'IQ' once the localized list resolves, so _dialCode has
  // to be reset back to Iraq's in the same setState or a country picked in
  // the intervening frame silently keeps the wrong dial code.
  @override
  void onCountryListLoaded() => _dialCode = _defaultDialCode;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // Prepend "+" so NormalizePhone treats this as already country-coded
  // instead of falling into its Iraq-assuming bare-input branch.
  String _normalizeLocalPhone(String digits) {
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+$_dialCode$national';
  }

  Future<void> _sendOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final phone = _normalizeLocalPhone(digits);

    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final resp = await http
          .post(
            Uri.parse(otpRequestUrl),
            headers: const {'Content-Type': 'application/json'},
            // R2 #17 — same request as sign-up: 'demo' lets the SERVER pick
            // the delivery (real SMS/WhatsApp when the gateway is set up).
            // Forcing 'real' made this screen fail on its own and show the
            // server's raw English text.
            body: jsonEncode({'phone': phone, 'mode': 'demo'}),
          )
          .timeout(const Duration(seconds: 15));
      final body = _decode(resp.body);
      if (resp.statusCode != 200 || body['status'] != 'success') {
        // Never the server's English: one translated sentence.
        setState(() => _error = 'error_otp_send_failed'.tr);
        return;
      }
      final demoCode = body['demo_code']?.toString();
      if (demoCode != null && demoCode.isNotEmpty) {
        appSnackbar(
          'OTP ready'.tr,
          'Demo OTP: @code'.trParams({'code': demoCode}),
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6),
        );
      }
      _normalizedPhone = phone;
      setState(() => _step = _Step.otp);
    } catch (_) {
      setState(() => _error = 'Network error. Please try again.'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyAndUpgrade() async {
    if (_otpController.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final result = await upgradeGuestVerifyOtp(
      _normalizedPhone,
      _otpController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.ok) {
      setState(() => _error = (result.error ?? 'Something went wrong.').tr);
      return;
    }
    // The account is now a normal 'incomplete' phone account — send it
    // through the exact same registration form any new signup fills in.
    routeByRegistrationStatus('incomplete');
  }

  Map<String, dynamic> _decode(String s) {
    try {
      final d = jsonDecode(s);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: AppThemeConfig.text(context),
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: AppThemeConfig.mutedText(context),
      height: 1.5,
    );

    return AuthScaffold(
      child: AuthGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(
              child: AuthBadge(
                icon: Icons.upgrade_rounded,
                label: 'Upgrade Account',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _step == _Step.phone
                  ? 'Enter your phone number'.tr
                  : 'Verify your phone'.tr,
              style: titleStyle,
            ),
            const SizedBox(height: 6),
            Text(
              _step == _Step.phone
                  // R2 #19 — one short line.
                  ? 'Please confirm your phone number to upgrade your account.'
                        .tr
                  // Isolate the embedded number as LTR (U+2066 LRI ...
                  // U+2069 PDI) so its digit grouping doesn't mirror under
                  // an RTL locale (matches Note #39's fix on the verify
                  // screen).
                  : '${'Enter the verification code sent to'.tr} \u2066${formatPhoneForDisplay(_normalizedPhone)}\u2069',
              style: subtitleStyle,
            ),
            const SizedBox(height: 18),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error,
                  style: TextStyle(
                    color: AppThemeConfig.consequence(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_step == _Step.phone) _buildPhoneStep() else _buildOtpStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextFormField(
              controller: _phoneController,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontSize: 16,
              ),
              cursorColor: AppThemeConfig.primary,
              decoration:
                  authInputDecoration(
                    context,
                    label: 'Phone'.tr,
                    // OPOS #25266 — a format example, not a real person's
                    // number. All-zero, not translatable (it's digits, not
                    // prose).
                    hintText: '000 000 0000',
                    icon: Icons.phone_outlined,
                  ).copyWith(
                    // Was previously built with only `key`/`countryList` —
                    // missing the dialog's own chrome (header/text/box/
                    // barrier), which left it falling back to the
                    // package's hardcoded English "Select Country" heading
                    // even on an Arabic screen (F5). Routed through
                    // [buildLocalizedCountryCodePicker] so this screen and
                    // login.dart share one definition of that chrome and
                    // can't drift apart on it again.
                    prefixIcon: buildLocalizedCountryCodePicker(
                      context,
                      onChanged: (code) => setState(
                        () => _dialCode = (code.dialCode ?? '+964')
                            .replaceFirst('+', ''),
                      ),
                      padding: const EdgeInsetsDirectional.only(
                        start: 14,
                        end: 4,
                      ),
                      flagWidth: 22,
                      textStyle: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                  ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                // R2 #26 — same per-country rule as sign-in.
                NationalNumberInputFormatter(() => _dialCode),
                PhoneSpaceInputFormatter(),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your phone number'.tr;
                }
                final digits = value.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 4 || digits.length > 14) {
                  return 'Enter a valid phone number'.tr;
                }
                return null;
              },
              onFieldSubmitted: (_) => _sendOtp(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                // R2 #18 — was text-colour fill + navy label (black, label
                // unreadable). The app's accent pair, readable in both themes.
                backgroundColor: AppThemeConfig.accent(context),
                foregroundColor: AppThemeConfig.onAccent(context),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF0B385D),
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Send code'.tr,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same 6 boxes as the sign-up code screen (auto-fill, paste,
          // auto-verify on the 6th digit).
          OtpBoxes(
            controller: _otpController,
            enabled: !_loading,
            onCompleted: (_) => _verifyAndUpgrade(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifyAndUpgrade,
              style: ElevatedButton.styleFrom(
                // R2 #18 — was text-colour fill + navy label (black, label
                // unreadable). The app's accent pair, readable in both themes.
                backgroundColor: AppThemeConfig.accent(context),
                foregroundColor: AppThemeConfig.onAccent(context),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF0B385D),
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Verify & Continue'.tr,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _step = _Step.phone;
                      _error = '';
                    }),
              child: Text(
                'Use a different number'.tr,
                style: TextStyle(color: AppThemeConfig.mutedText(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
