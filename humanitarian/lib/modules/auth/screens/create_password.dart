// create_password.dart — the last step of signing up, and the way back in for
// an account that has never had a password.
//
// A16 — the owner's design is "OTP for account creation only, password will be
// used for sign in to the app later". The code screen before this one proves the
// number; this screen turns that proof into a password, which is what every
// later sign-in uses. The single-use ticket lives in the LoginController, so
// nothing sensitive travels through route arguments.
//
// Reached in two ways, and it deliberately looks the same in both:
//
//   * a brand-new number finishing sign-up, and
//   * an existing account that holds no password (36 of the 46 live accounts).
//
// The server does not say which, because saying so would turn the flow into an
// "is this number registered?" oracle — so neither does this screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:get/get.dart';

import 'package:flutter_application_1/controllers/login.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/routes/app_routes.dart';

import '../../../widgets/auth_ui.dart';

/// bcrypt cannot hash more than 72 BYTES, so the server refuses anything longer
/// and the field stops the user there rather than letting them type a password
/// that will be rejected. Characters, not bytes — an Arabic password reaches the
/// byte ceiling sooner, and the server has the final say either way.
const int _maxPasswordCharacters = 72;

class CreatePasswordPage extends StatelessWidget {
  const CreatePasswordPage({super.key});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Choose a password'.tr, style: titleStyle),
          const SizedBox(height: 8),
          Text(
            'Your number is verified. This password is how you will sign in from now on.'
                .tr,
            style: subtitleStyle,
          ),
          const SizedBox(height: 26),
          const _CreatePasswordForm(),
        ],
      ),
    );
  }
}

class _CreatePasswordForm extends StatefulWidget {
  const _CreatePasswordForm();

  @override
  State<_CreatePasswordForm> createState() => _CreatePasswordFormState();
}

class _CreatePasswordFormState extends State<_CreatePasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final LoginController _loginController = Get.isRegistered<LoginController>()
      ? Get.find<LoginController>()
      : Get.put(LoginController());

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ─── Validation ───────────────────────────────────────────────────────
  //
  // Mirrors the server's rules (auth.ValidateNewPassword) so the user finds out
  // as they type rather than after a round trip. The server still decides — it
  // applies the same minimum and the same 72-byte bcrypt ceiling, and a client
  // that skipped these checks would simply be refused.

  String? _validatePassword(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Choose a password'.tr;
    final min = _loginController.minPasswordLength.value;
    if (v.runes.length < min) {
      return 'Use at least @n characters.'.trParams({'n': min.toString()});
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if ((value ?? '').trim() != _passwordController.text.trim()) {
      return 'The two passwords do not match.'.tr;
    }
    return null;
  }

  // ─── Actions ──────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      AppHaptics.error();
      return;
    }
    // Dismiss the keyboard before the request so it never sits over the button
    // or ghosts onto the next screen.
    FocusScope.of(context).unfocus();

    final user = await _loginController.setPassword(_passwordController.text);
    if (!mounted) return;
    if (user == null) {
      AppHaptics.error();
      // A dead ticket cannot be retried here — send them back for a new code.
      if (!_loginController.hasSetupTicket) {
        Get.offAllNamed(AppRoutes.authLogin);
      }
      return;
    }
    AppHaptics.success();
    await completeSignInAndRoute(user);
  }

  @override
  Widget build(BuildContext context) {
    final phone = _loginController.pendingPhone.value;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone.isNotEmpty) ...[
            Text(
              // #39 — isolate the number as LTR (U+2066 LRI ... U+2069 PDI) so
              // its digit grouping does not mirror inside an RTL locale. Written
              // as escapes, not literal marks, so the source stays readable.
              'Setting the password for @phone'.trParams({
                'phone': '\u2066${formatPhoneForDisplay(phone)}\u2069',
              }),
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Server-side refusals land here: wrong ticket, expired verification,
          // a password the server judged too short. Never a raw status code.
          Obx(
            () => _loginController.errorMessage.value.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: AppThemeConfig.consequence(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _loginController.errorMessage.value,
                            style: TextStyle(
                              color: AppThemeConfig.consequence(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            // A password field, so the keyboard offers no autocorrect and no
            // suggestion strip that could leak what is being typed.
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxPasswordCharacters),
            ],
            style: TextStyle(color: AppThemeConfig.text(context)),
            cursorColor: AppThemeConfig.primary,
            decoration:
                authInputDecoration(
                  context,
                  label: 'New password',
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
            validator: _validatePassword,
            onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
          ),
          const SizedBox(height: 8),
          // 5.9 — say the rule before it is broken, not only after.
          Obx(
            () => Text(
              'At least @n characters.'.trParams({
                'n': _loginController.minPasswordLength.value.toString(),
              }),
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmController,
            focusNode: _confirmFocus,
            obscureText: _obscureConfirm,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxPasswordCharacters),
            ],
            style: TextStyle(color: AppThemeConfig.text(context)),
            cursorColor: AppThemeConfig.primary,
            decoration:
                authInputDecoration(
                  context,
                  label: 'Confirm password',
                  hintText: '••••••••',
                  icon: Icons.lock_outline_rounded,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip:
                        (_obscureConfirm ? 'Show password' : 'Hide password')
                            .tr,
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppThemeConfig.mutedText(context),
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
            validator: _validateConfirm,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 22),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Disabled while in flight — one tap, one account.
                onPressed: _loginController.isLoading.value ? null : _submit,
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
                        'Save and continue'.tr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loginController.isLoading.value
                  ? null
                  : () => Get.offAllNamed(AppRoutes.authLogin),
              child: Text('Back to sign in'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
