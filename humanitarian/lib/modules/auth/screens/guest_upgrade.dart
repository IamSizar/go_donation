import 'dart:async';
import 'dart:convert';

import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../../api/guest_session.dart';
import '../../../api/links.dart';
import '../../../core/auth_navigation.dart';
import '../../../core/phone_format.dart';
import '../../../widgets/auth_ui.dart';

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

class _GuestUpgradeScreenState extends State<GuestUpgradeScreen> {
  _Step _step = _Step.phone;
  String _dialCode = '964';
  String _normalizedPhone = '';
  bool _loading = false;
  String _error = '';

  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _normalizeLocalPhone(String digits) {
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '$_dialCode$national';
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
            body: jsonEncode({'phone': phone, 'mode': 'real'}),
          )
          .timeout(const Duration(seconds: 15));
      final body = _decode(resp.body);
      if (resp.statusCode != 200 || body['status'] != 'success') {
        setState(
          () => _error =
              body['error']?.toString() ?? 'Failed to send verification code.',
        );
        return;
      }
      _normalizedPhone = phone;
      setState(() => _step = _Step.otp);
    } catch (_) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyAndUpgrade() async {
    if (!_otpFormKey.currentState!.validate()) return;
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
      setState(() => _error = result.error ?? 'Something went wrong.');
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
                  ? 'We\'ll text you a one-time code to confirm it\'s yours.'
                        .tr
                  // Isolate the embedded number as LTR (U+2066 LRI ...
                  // U+2069 PDI) so its digit grouping doesn't mirror under
                  // an RTL locale (matches Note #39's fix on the verify
                  // screen).
                  : 'We sent a 6-digit code to @phone'.trParams({
                      'phone':
                          '\u2066${formatPhoneForDisplay(_normalizedPhone)}\u2069',
                    }),
              style: subtitleStyle,
            ),
            const SizedBox(height: 18),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error,
                  style: const TextStyle(
                    color: Colors.redAccent,
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
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: Colors.white,
              decoration: authInputDecoration(
                label: 'Phone',
                hintText: '750 858 2031',
                icon: Icons.phone_outlined,
              ).copyWith(
                prefixIcon: CountryCodePicker(
                  onChanged: (code) => setState(
                    () => _dialCode = (code.dialCode ?? '+964').replaceFirst(
                      '+',
                      '',
                    ),
                  ),
                  initialSelection: 'IQ',
                  favorite: const ['+964', 'IQ'],
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  flagWidth: 22,
                  showDropDownButton: true,
                  textStyle: const TextStyle(
                    color: Colors.white,
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
                PhoneSpaceInputFormatter(),
                LengthLimitingTextInputFormatter(20),
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
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0B385D),
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
          TextFormField(
            controller: _otpController,
            style: const TextStyle(color: Colors.white, fontSize: 20),
            cursorColor: Colors.white,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: authInputDecoration(
              label: 'Verification code',
              hintText: '••••••',
              icon: Icons.password_rounded,
            ).copyWith(counterText: ''),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (value) {
              if (value == null || value.trim().length != 6) {
                return 'Enter the 6-digit code'.tr;
              }
              return null;
            },
            onFieldSubmitted: (_) => _verifyAndUpgrade(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifyAndUpgrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0B385D),
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
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
