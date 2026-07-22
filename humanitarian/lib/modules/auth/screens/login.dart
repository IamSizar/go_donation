import 'dart:async';

import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // LengthLimitingTextInputFormatter
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/routes/app_routes.dart';

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
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: AuthBadge(
                icon: Icons.lock_rounded,
                label: 'Secure sign in',
              ),
            ),
            const SizedBox(height: 18),
            Text('Welcome back'.tr, style: titleStyle),
            const SizedBox(height: 6),
            Text(
              'Sign in to continue.'.tr,
              style: subtitleStyle,
            ),
            const SizedBox(height: 18),
            const _LoginForm(),
            const SizedBox(height: 8),
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

  // #39 — international phone support: the selected country's dial code
  // (no "+"), defaulting to Iraq. Changed via the CountryCodePicker.
  String _dialCode = '964';

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

  /// Convert a locally-typed phone (with the selected _dialCode) to the
  /// full international form: strip a leading national trunk "0" if present
  /// (standard when combining a local number with its country code), then
  /// prepend the selected dial code.
  ///
  ///   964 + 7508582031    → 9647508582031
  ///   964 + 07508582031   → 9647508582031  (leading trunk 0 stripped)
  ///   44  + 07700900000   → 447700900000
  String _normalizeLocalPhone(String digits) {
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '$_dialCode$national';
  }

  Future<void> _handleGoogleLogin() async {
    final result = await _loginController.signInWithGoogle();
    if (result != null) {
      _completeLogin(result);
    }
  }

  /// Note #40 — Guest Registration Process. Opens a lightweight
  /// username+password sheet; on success the guest lands straight in Home
  /// (no sub-page detour), same as the old anonymous guest mode did.
  Future<void> _continueAsGuest() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuestAccessSheet(),
    );
    if (ok == true) {
      Get.offAllNamed(AppRoutes.home);
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
          // #39 — phone field with an interactive country-code picker
          // (defaults to Iraq). The user types ONLY the local number;
          // _normalizeLocalPhone() prepends the selected dial code before
          // we hand the value to sendOtp().
          //
          // Forced LTR: a phone number is a fixed left-to-right digit
          // group ("0750 858 2031"); under the ambient RTL Directionality
          // of an Arabic/Kurdish locale, the bidi algorithm mirrors that
          // grouping ("2031 858 0750"), which reads as a different number.
          // Locking this whole field to LTR keeps the digits — and the
          // hint text — in the same order in every locale.
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
              // Replace the generic phone-icon prefix with a picker that
              // shows the selected country's flag + dial code. The picker
              // dialog is restyled to match the app's dark glass look (the
              // package default is a plain white Material dialog) and its
              // header spells out that Iraq is just the default — the full
              // list of 200+ countries is one tap away.
              prefixIcon: CountryCodePicker(
                onChanged: (code) => setState(
                  () => _dialCode = (code.dialCode ?? '+964').replaceFirst(
                    '+',
                    '',
                  ),
                ),
                initialSelection: 'IQ',
                favorite: const ['+964', 'IQ'],
                showCountryOnly: false,
                showOnlyCountryWhenClosed: false,
                alignLeft: false,
                padding: const EdgeInsets.only(left: 14, right: 4),
                flagWidth: 22,
                // A visible chevron on the closed state itself hints that
                // Iraq is just the current pick, not the only option.
                showDropDownButton: true,
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                flagDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 3,
                    ),
                  ],
                ),
                dialogSize: const Size(360, 520),
                boxDecoration: BoxDecoration(
                  color: const Color(0xFF0E3B5C),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                barrierColor: Colors.black.withValues(alpha: 0.55),
                closeIcon: const Icon(Icons.close_rounded, color: Colors.white70),
                headerText: 'Select your country · 200+ available'.tr,
                headerTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                topBarPadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                searchPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                searchDecoration: InputDecoration(
                  hintText: 'Search country'.tr,
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white70,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.10),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                searchStyle: const TextStyle(color: Colors.white),
                dialogTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                dialogItemPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              hintText: '750 858 2031',
            ),
            keyboardType: TextInputType.number,
            // Group digits with spaces as they type ("750 858 2031"). The
            // value is digit-stripped before submit, so the spaces are
            // purely cosmetic. 20 chars comfortably fits the longest
            // international national numbers plus grouping spaces.
            inputFormatters: [
              PhoneSpaceInputFormatter(),
              LengthLimitingTextInputFormatter(20),
            ],
            textInputAction: TextInputAction.done,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your phone number'.tr;
              }
              final digits = value.replaceAll(RegExp(r'\D'), '');
              if (_dialCode == '964') {
                // Iraq keeps its precise NSN-length check (10 digits, or 11
                // with a leading trunk 0).
                if (digits.length == 10) return null;
                if (digits.length == 11 && digits.startsWith('0')) {
                  return null;
                }
                return 'Enter 10 digits (or 11 starting with 0)'.tr;
              }
              // Other countries: no client-side per-country length table —
              // a generic sanity range; the backend applies the
              // authoritative E.164 check.
              if (digits.length >= 4 && digits.length <= 14) return null;
              return 'Enter a valid phone number'.tr;
            },
            onFieldSubmitted: (_) => _handleSendOtp(),
            ),
          ),
          const SizedBox(height: 14),
          // Phase 19b — OTP delivery mode picker. Two visual segments
          // (Real / Demo) so the user can swap between OTPIQ-backed
          // verification and the local-dev "always 123456" flow.
          _OtpModePicker(
            value: _otpMode,
            onChanged: (next) => setState(() => _otpMode = next),
          ),
          const SizedBox(height: 16),
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
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                  'or continue with'.tr,
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
          const SizedBox(height: 12),
          // Section 27 — Guest Mode: browse without an account.
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _loginController.isLoading.value
                  ? null
                  : _continueAsGuest,
              icon: Icon(
                Icons.person_outline_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 20,
              ),
              label: Text(
                'Continue as guest'.tr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
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

/// #40 — the guest access sheet. One username + one password field, "quickly
/// access" the app: the primary action always tries to REGISTER a new guest
/// account first; if that username is already taken, a secondary "Log in
/// instead" action appears using the same two fields. Pops `true` on success
/// so the caller knows to navigate to Home.
class _GuestAccessSheet extends StatefulWidget {
  const _GuestAccessSheet();

  @override
  State<_GuestAccessSheet> createState() => _GuestAccessSheetState();
}

class _GuestAccessSheetState extends State<_GuestAccessSheet> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String _error = '';
  bool _usernameTaken = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool asLogin}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final result = asLogin
        ? await loginGuest(username, password)
        : await registerGuest(username, password);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _usernameTaken = result.code == 'username_taken';
      _error = result.ok ? '' : (result.error ?? 'Something went wrong.');
    });
    if (result.ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            24,
            22,
            24,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0E3B5C), Color(0xFF114C72)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Continue as guest'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Just a username and password to quickly browse.'.tr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
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
                TextFormField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: authInputDecoration(
                    label: 'Username',
                    hintText: 'guest_name',
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.length < 3 || s.length > 32) {
                      return 'Use 3-32 letters, numbers or underscore'.tr;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  obscureText: _obscure,
                  decoration:
                      authInputDecoration(
                        label: 'Password',
                        hintText: '••••••',
                        icon: Icons.lock_outline_rounded,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white70,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                  validator: (v) => (v ?? '').length < 6
                      ? 'At least 6 characters'.tr
                      : null,
                  onFieldSubmitted: (_) => _submit(asLogin: false),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _submit(asLogin: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0B385D),
                      padding: const EdgeInsets.symmetric(vertical: 15),
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
                            'Continue as guest'.tr,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                if (_usernameTaken) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _submit(asLogin: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        'That\'s me — log in instead'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
