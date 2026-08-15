import 'dart:async';

import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter/services.dart'; // LengthLimitingTextInputFormatter
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/modules/auth/widgets/auth_inline_error.dart';
import 'package:flutter_application_1/routes/app_routes.dart';

import '../../../widgets/auth_ui.dart';
import '../../../controllers/login.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The headline lives in _LoginForm: A16 gave this screen two modes, and the
    // title has to say which one is showing.
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
          const _LoginForm(),
        ],
      ),
    );
  }
}

/// Which of the two things this screen is doing right now.
///
/// A16 — the owner's design gives the screen two jobs that used to be one. A
/// returning user signs in with a password; a new one proves a number with a
/// code and then chooses a password. Mixing them into a single "Continue"
/// button was what made a phone number look like a credential, so they are
/// separate modes with separate buttons and separate copy.
enum _LoginMode { signIn, signUp }

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
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  /// Sign in (phone + password) or sign up (phone → code → password). Starts on
  /// sign-in because that is what almost every visit is.
  _LoginMode _mode = _LoginMode.signIn;

  bool _obscurePassword = true;

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
  // the first tap for everyone.
  //
  // A16 — this default no longer needs changing, and a shipped build can no
  // longer be stuck on demo codes. The server decides delivery now: once
  // OTPIQ_API_KEY is configured it serves a 'demo' request as a real
  // out-of-band code, so the switchover is an environment change and never a
  // store release. Asking for 'demo' means "demo if that is all there is".
  String _otpMode = 'demo';

  /// A16 — one shared finish for every way of arriving signed in (password,
  /// Google, or a completed sign-up), so no path lands the user in the app with
  /// a half-populated profile. See core/auth_navigation.dart.
  Future<void> _completeLogin(Map<String, dynamic> user) =>
      completeSignInAndRoute(user);

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

  /// Sign-in: phone + password. The ordinary way in for anyone who has finished
  /// signing up.
  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) {
      AppHaptics.error();
      return;
    }
    // Never leave the keyboard over the button or ghosting onto the next screen.
    FocusScope.of(context).unfocus();

    final localDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final user = await _loginController.signInWithPassword(
      _normalizeLocalPhone(localDigits),
      _passwordController.text,
    );
    if (!mounted) return;
    if (user == null) {
      AppHaptics.error();
      return; // the message (or the setup offer) is already on screen
    }
    AppHaptics.success();
    await _completeLogin(user);
  }

  /// Sign-up, and the rescue path for an account that holds no password: send a
  /// code, then the verify screen, then "choose a password".
  Future<void> _handleSendOtp() async {
    // Only the phone matters here, so a half-typed password must not block it.
    if (_phoneMessage(_phoneController.text) != null) {
      _formKey.currentState!.validate();
      AppHaptics.error();
      return;
    }
    FocusScope.of(context).unfocus();

    // Phase 19c — auto-prepend the selected country's dial code so the
    // user only ever types their local number. The leading "+" tells
    // backend's NormalizePhone this is already country-coded (its
    // bare-input branch otherwise assumes Iraq), and normalizing here also
    // keeps the pendingPhone display + verify-screen header consistent.
    final localDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final normalizedPhone = _normalizeLocalPhone(localDigits);

    debugPrint('Requesting a code for: $normalizedPhone (mode=$_otpMode)');

    final sent = await _loginController.sendOtp(
      normalizedPhone,
      mode: _otpMode,
    );
    if (!mounted) return;
    if (sent) {
      Get.toNamed(AppRoutes.authVerify);
    } else {
      AppHaptics.error();
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
      // Awaited now that the finish is shared and asynchronous: it writes the
      // prefs the destination screen reads, so routing before it completes
      // would land the user on a screen with no identity yet.
      await _completeLogin(result);
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
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Switch between signing in and signing up, clearing anything that belonged
  /// to the other mode — a stale "wrong password" under a sign-up form reads as
  /// a bug.
  void _setMode(_LoginMode next) {
    if (_mode == next) return;
    setState(() {
      _mode = next;
      _passwordController.clear();
    });
    _loginController.errorMessage.value = '';
    _loginController.needsPasswordSetup.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == _LoginMode.signUp;
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: AppThemeConfig.text(context),
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: AppThemeConfig.mutedText(context),
      height: 1.5,
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The headline says which of the two jobs is on screen, and the line
          // under it says exactly what the button will do.
          Text(
            isSignUp ? 'Create your account'.tr : 'Welcome back'.tr,
            style: titleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            isSignUp
                ? 'Enter your phone number and we will send you a verification code.'
                      .tr
                : 'Sign in with your phone number and password.'.tr,
            style: subtitleStyle,
          ),
          const SizedBox(height: 26),
          // A16 — "this number has no password yet" is not an error the user
          // can retype their way out of, so it gets an action instead of a
          // scolding: verify the number, then choose a password (5.7).
          Obx(
            () => _loginController.needsPasswordSetup.value
                ? _NeedsPasswordSetupCard(
                    busy: _loginController.isLoading.value,
                    onVerify: _handleSendOtp,
                  )
                : const SizedBox.shrink(),
          ),
          // E4 — this line was the correct one; the OTP screen and the
          // registration form each had their own, drawn in a hardcoded red.
          // All three now share AuthInlineError, so there is one place where
          // the colour is chosen and one place a test can read it back.
          Obx(
            () => AuthInlineError(
              // The gap sits below, unchanged from before the extraction: this
              // line is above the field it refers to.
              padding: const EdgeInsets.only(bottom: 12),
              message: _loginController.needsPasswordSetup.value
                  ? '' // the card above already says this, with an action
                  : _loginController.errorMessage.value,
            ),
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
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        PhoneSpaceInputFormatter(),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      // Sign-in has a password field after this one, so the
                      // return key moves on rather than submitting a half-
                      // filled form (5.6).
                      textInputAction: isSignUp
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onChanged: (_) {
                        if (_phoneError != null) {
                          setState(() => _phoneError = null);
                        }
                        if (_loginController.needsPasswordSetup.value) {
                          _loginController.needsPasswordSetup.value = false;
                          _loginController.errorMessage.value = '';
                        }
                      },
                      validator: _validatePhone,
                      onFieldSubmitted: (_) => isSignUp
                          ? _handleSendOtp()
                          : _passwordFocus.requestFocus(),
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
          // Password — sign-in only. A16: a code is for creating an account,
          // and this is the credential everyone uses afterwards.
          if (!isSignUp) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _obscurePassword,
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              style: TextStyle(color: AppThemeConfig.text(context)),
              cursorColor: AppThemeConfig.primary,
              decoration:
                  authInputDecoration(
                    context,
                    label: 'Password',
                    hintText: '••••••••',
                    icon: Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      tooltip:
                          (_obscurePassword ? 'Show password' : 'Hide password')
                              .tr,
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppThemeConfig.mutedText(context),
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
              // Only "is there one at all" here: the server decides whether it
              // is right, and telling the user their length is wrong on the
              // sign-in screen would leak the rule for an existing password.
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Enter your password'.tr : null,
              onFieldSubmitted: (_) => _handleSignIn(),
            ),
          ],
          const SizedBox(height: 20),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loginController.isLoading.value
                    ? null
                    : (isSignUp ? _handleSendOtp : _handleSignIn),
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
                        isSignUp ? 'Send code'.tr : 'Sign in'.tr,
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
          // The switch between the screen's two jobs. This screen IS the
          // sign-up — there is no /register — but under A16 signing up is a
          // different set of steps from signing in, so it says so.
          Center(
            child: TextButton(
              onPressed: _loginController.isLoading.value
                  ? null
                  : () => _setMode(
                      isSignUp ? _LoginMode.signIn : _LoginMode.signUp,
                    ),
              child: Text(
                isSignUp
                    ? 'Already have an account? Sign in'.tr
                    : 'New here? Create an account'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppThemeConfig.primary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
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
          //
          // A16 — shown only where it applies. Signing in no longer involves a
          // code at all, so on that side of the screen this row would offer a
          // choice about something that is not going to happen.
          if (isSignUp || _loginController.needsPasswordSetup.value) ...[
            const SizedBox(height: 20),
            _OtpModeRow(
              value: _otpMode,
              onChanged: (next) => setState(() => _otpMode = next),
            ),
          ],
        ],
      ),
    );
  }
}

/// _NeedsPasswordSetupCard — the answer to `401 otp_required`.
///
/// A16 — 36 of the 46 live accounts hold no password, so "wrong password" would
/// be both untrue and useless for them: there is nothing to get right. The
/// server says so with a code the app can act on, and this is the action —
/// verify the number, then choose a password.
///
/// It does NOT say whether the number is registered. The server answers an
/// unknown number and a passwordless account identically, on purpose, so this
/// card has to fit both readings — and it does: either way, the next step is to
/// verify the number and pick a password.
class _NeedsPasswordSetupCard extends StatelessWidget {
  const _NeedsPasswordSetupCard({required this.busy, required this.onVerify});

  final bool busy;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: authFieldFill(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: authFieldBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_reset_rounded,
                size: 20,
                color: AppThemeConfig.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This number has no password yet. Verify it to choose one.'
                      .tr,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: busy ? null : onVerify,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppThemeConfig.primary,
                side: BorderSide(color: AppThemeConfig.primary, width: 1.2),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppThemeConfig.primary,
                      ),
                    )
                  : Text(
                      'Verify my number'.tr,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
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
