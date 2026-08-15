import 'dart:async';

import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
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
      color: AppThemeConfig.text(context),
      fontWeight: FontWeight.w800,
      height: 1.1,
    );

    final subtitleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: AppThemeConfig.mutedText(context),
      height: 1.5,
    );

    return AuthScaffold(
      // No card. A panel drawn on a background of the same colour is just a
      // floating box with padding — it added a border and a shadow around the
      // form without separating it from anything. The form sits on the page
      // now, which is what every sign-in screen worth copying does.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Brand mark. The screen had no logo at all — the only branding was
          // a decorative "Secure sign in" pill that told the user nothing.
          Center(
            child: ClipOval(
              child: Image.asset(
                'assets/branding/balancenex_icon.png',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text('Welcome back'.tr, style: titleStyle),
          const SizedBox(height: 8),
          // Says what pressing the button will actually do. The old subtitle
          // ("Sign in to continue.") restated the title.
          Text(
            'Enter your phone number and we will send you a verification code.'
                .tr,
            style: subtitleStyle,
          ),
          const SizedBox(height: 26),
          const _LoginForm(),
        ],
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

  // Validation message for the phone control. Held here rather than left to
  // the TextFormField's own errorText because the visible field is the
  // surrounding container, not the inner borderless input.
  String? _phoneError;

  String? _validatePhone(String? value) {
    final msg = _phoneMessage(value);
    // Surface it under the whole control on the next frame; returning a
    // non-null string is still what makes Form.validate() fail.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phoneError != msg) setState(() => _phoneError = msg);
    });
    return msg;
  }

  String? _phoneMessage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number'.tr;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (_dialCode == '964') {
      // Iraq keeps its precise NSN-length check (10 digits, or 11 with a
      // leading trunk 0).
      if (digits.length == 10) return null;
      if (digits.length == 11 && digits.startsWith('0')) return null;
      return 'Enter 10 digits (or 11 starting with 0)'.tr;
    }
    // Other countries: a generic sanity range; the backend applies the
    // authoritative E.164 check.
    if (digits.length >= 4 && digits.length <= 14) return null;
    return 'Enter a valid phone number'.tr;
  }

  // Phase 19b — OTP delivery mode toggle. 'real' sends via OTPIQ (WhatsApp
  // first, SMS fallback); 'demo' skips OTPIQ and the backend returns the
  // static demo code, honoured only while OTP_DEMO_ENABLED=1 on the server.
  //
  // Defaulted to 'demo' at the client's request while OTPIQ_API_KEY is unset
  // on the backend: real delivery returns 502 "Failed to send verification
  // code." for every number, so 'real' as the default made Continue fail on
  // the first tap for everyone. Switch this back to 'real' the moment the
  // key is configured — the Delivery row below still offers both, so no code
  // change is needed to test real delivery once it works.
  String _otpMode = 'demo';

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
    // ("+9647508582031"). Strip the leading "+964" when re-populating so
    // the input field stays local-only ("7508582031") and matches the
    // locked +964 chip beside it.
    final pending = _loginController.pendingPhone.value;
    final pendingDigits = pending.startsWith('+')
        ? pending.substring(1)
        : pending;
    _phoneController.text =
        pendingDigits.startsWith('964') && pendingDigits.length > 3
        ? pendingDigits.substring(3)
        : pending;
  }

  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    // Phase 19c — auto-prepend the selected country's dial code so the
    // user only ever types their local number. The leading "+" tells
    // backend's NormalizePhone this is already country-coded (its
    // bare-input branch otherwise assumes Iraq), and normalizing here also
    // keeps the pendingPhone display + verify-screen header consistent.
    final localDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final normalizedPhone = _normalizeLocalPhone(localDigits);

    debugPrint(
      'Logging in with phone number: $normalizedPhone (mode=$_otpMode)',
    );

    final sent = await _loginController.sendOtp(
      normalizedPhone,
      mode: _otpMode,
    );
    if (sent) {
      Get.toNamed('/verify');
    }
  }

  /// Convert a locally-typed phone (with the selected _dialCode) to the
  /// full international form: strip a leading national trunk "0" if present
  /// (standard when combining a local number with its country code), then
  /// prepend "+" and the selected dial code so NormalizePhone treats it as
  /// already country-coded.
  ///
  ///   964 + 7508582031    → +9647508582031
  ///   964 + 07508582031   → +9647508582031  (leading trunk 0 stripped)
  ///   44  + 07700900000   → +447700900000
  String _normalizeLocalPhone(String digits) {
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+$_dialCode$national';
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
                      style: TextStyle(
                        color: AppThemeConfig.consequence(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
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
          // Phone entry, built as one explicit bordered row rather than a
          // TextField whose prefixIcon happens to be a country picker.
          //
          // The old shape put CountryCodePicker into prefixIcon and relied on
          // InputDecoration to draw the box around both. That box silently
          // stopped painting: a deliberately loud 4px red enabledBorder did
          // not render a single pixel, while the label still did. Rather than
          // keep fighting the decorator, the container owns the border and
          // the field inside is borderless — which is also the conventional
          // way to build a composite phone input, and gives the picker and
          // the number a real divider between them.
          //
          // Forced LTR: a phone number is a fixed left-to-right digit group
          // ("0750 858 2031"); under the ambient RTL Directionality of an
          // Arabic/Kurdish locale the bidi algorithm mirrors that grouping
          // ("2031 858 0750"), which reads as a different number.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              decoration: BoxDecoration(
                color: authFieldFill(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: authFieldBorder(context), width: 1.2),
              ),
              child: Row(
                children: [
                  CountryCodePicker(
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
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 2,
                    ),
                    flagWidth: 24,
                    showDropDownButton: true,
                    textStyle: TextStyle(
                      color: AppThemeConfig.text(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    flagDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                    ),
                    dialogSize: const Size(360, 520),
                    boxDecoration: BoxDecoration(
                      color: AppThemeConfig.elevatedSurface(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: authFieldBorder(context)),
                    ),
                    barrierColor: Colors.black.withValues(alpha: 0.45),
                    closeIcon: Icon(
                      Icons.close_rounded,
                      color: AppThemeConfig.mutedText(context),
                    ),
                    headerText: 'Select your country · 200+ available'.tr,
                    headerTextStyle: TextStyle(
                      color: AppThemeConfig.text(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    dialogTextStyle: TextStyle(
                      color: AppThemeConfig.text(context),
                      fontWeight: FontWeight.w500,
                    ),
                    searchStyle: TextStyle(color: AppThemeConfig.text(context)),
                    dialogItemPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  // Divider between the dial code and the number, so the two
                  // read as separate inputs inside one control.
                  Container(
                    width: 1,
                    height: 26,
                    color: authFieldBorder(context),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      cursorColor: AppThemeConfig.primary,
                      decoration: InputDecoration(
                        hintText: '750 858 2031',
                        hintStyle: TextStyle(
                          color: AppThemeConfig.mutedText(
                            context,
                          ).withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        // The container is the visual field, so the error
                        // text is rendered below it by the Form instead.
                        errorStyle: const TextStyle(height: 0, fontSize: 0),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 18,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        PhoneSpaceInputFormatter(),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_phoneError != null) {
                          setState(() => _phoneError = null);
                        }
                      },
                      validator: _validatePhone,
                      onFieldSubmitted: (_) => _handleSendOtp(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Inline validation message, owned by this screen so it sits under
          // the whole control rather than under just the number half.
          if (_phoneError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppThemeConfig.consequence(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _phoneError!,
                    style: TextStyle(
                      color: AppThemeConfig.consequence(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loginController.isLoading.value
                    ? null
                    : _handleSendOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeConfig.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppThemeConfig.primary.withValues(
                    alpha: 0.5,
                  ),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _loginController.isLoading.value
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        'Continue'.tr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: AppThemeConfig.border(context),
                  thickness: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or'.tr,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: AppThemeConfig.border(context),
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
                  foregroundColor: AppThemeConfig.text(context),
                  side: BorderSide(color: authFieldBorder(context), width: 1.2),
                  backgroundColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loginController.isLoading.value
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppThemeConfig.text(context),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppThemeConfig.text(context),
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              'G',
                              style: TextStyle(
                                color: Colors.white,
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
          const SizedBox(height: 10),
          // Section 27 — Guest Mode: browse without an account.
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _loginController.isLoading.value
                  ? null
                  : _continueAsGuest,
              icon: Icon(
                Icons.person_outline_rounded,
                color: AppThemeConfig.mutedText(context),
                size: 20,
              ),
              label: Text(
                'Continue as guest'.tr,
                style: TextStyle(
                  color: AppThemeConfig.mutedText(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // This screen IS the sign-up: the phone/OTP flow creates the account
          // if the number is new. The old footer sent people to /register,
          // whose submit handler waits 650ms and routes to /verify without
          // ever calling the backend — a dead end that looks like it worked.
          Center(
            child: Text(
              'New here? Entering your number creates your account.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'By continuing you agree to our Terms and Privacy Policy.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context).withValues(alpha: 0.8),
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
          // Delivery mode. Demoted from a pair of full-size cards sitting
          // directly above the primary button — a developer control competing
          // with the main action — to one quiet row at the very bottom.
          const SizedBox(height: 20),
          _OtpModeRow(
            value: _otpMode,
            onChanged: (next) => setState(() => _otpMode = next),
          ),
        ],
      ),
    );
  }
}

/// _OtpModeRow — how the next code is delivered.
///
///   Real — OTPIQ sends it over WhatsApp, falling back to SMS.
///   Demo — the backend skips OTPIQ and returns the fixed code 123456
///          (honoured only while OTP_DEMO_ENABLED=1 on the server).
///
/// This used to be two full-size cards stacked directly above the primary
/// button, which gave a development affordance the same weight as "Continue"
/// and put "Code: 123456" in the middle of the sign-in screen. It is one
/// muted row at the foot of the page now: still reachable while demo mode is
/// the only working delivery path, but no longer part of the main flow.
class _OtpModeRow extends StatelessWidget {
  const _OtpModeRow({required this.value, required this.onChanged});

  final String value; // 'real' | 'demo'
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = AppThemeConfig.mutedText(context);
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Delivery'.tr, style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(width: 8),
          _ModeLink(
            label: 'WhatsApp / SMS'.tr,
            selected: value == 'real',
            onTap: () => onChanged('real'),
          ),
          Text('  ·  ', style: TextStyle(color: muted, fontSize: 12)),
          _ModeLink(
            label: 'Demo code'.tr,
            selected: value == 'demo',
            onTap: () => onChanged('demo'),
          ),
        ],
      ),
    );
  }
}

class _ModeLink extends StatelessWidget {
  const _ModeLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? AppThemeConfig.primary
                : AppThemeConfig.mutedText(context),
            decoration: selected ? TextDecoration.underline : null,
            decorationColor: AppThemeConfig.primary,
          ),
        ),
      ),
    );
  }
}

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
          decoration: BoxDecoration(color: AppThemeConfig.accent(context)),
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
                      color: AppThemeConfig.border(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Continue as guest'.tr,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Just a username and password to quickly browse.'.tr,
                  style: TextStyle(color: AppThemeConfig.mutedText(context)),
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
                TextFormField(
                  controller: _usernameController,
                  style: TextStyle(color: AppThemeConfig.text(context)),
                  cursorColor: AppThemeConfig.primary,
                  decoration: authInputDecoration(
                    context,
                    label: 'Username'.tr,
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
                  style: TextStyle(color: AppThemeConfig.text(context)),
                  cursorColor: AppThemeConfig.primary,
                  obscureText: _obscure,
                  decoration:
                      authInputDecoration(
                        context,
                        label: 'Password'.tr,
                        hintText: '••••••',
                        icon: Icons.lock_outline_rounded,
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppThemeConfig.mutedText(context),
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                  validator: (v) =>
                      (v ?? '').length < 6 ? 'At least 6 characters'.tr : null,
                  onFieldSubmitted: (_) => _submit(asLogin: false),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _submit(asLogin: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeConfig.onAccent(context),
                      foregroundColor: AppThemeConfig.accent(context),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppThemeConfig.accent(context),
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
                        foregroundColor: AppThemeConfig.primary,
                        side: BorderSide(color: AppThemeConfig.border(context)),
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
