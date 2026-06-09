import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/controllers/login.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:flutter_application_1/core/push_registration.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/auth_navigation.dart';
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

  Future<void> _completeLogin(Map<String, dynamic> user) async {
    await sharedPreferences.setString('id_user', user['id'].toString());
    await sharedPreferences.setString(
      'phone_user',
      (user['phone'] ?? '').toString(),
    );
    await sharedPreferences.setString('name_user', user['name'].toString());

    final rawAcc = user['account'];
    if (rawAcc is Map) {
      await applyUserAccountToSharedPreferences(
        Map<String, dynamic>.from(rawAcc),
        includeRoleId: false,
      );
    }

    // Always reload profile from GET — login `account` may be missing, nested, or use odd keys.
    final uid = int.tryParse(user['id'].toString());
    if (uid != null && uid > 0) {
      final remote = await fetchUserAccount(uid);
      if (remote != null) {
        await applyUserAccountToSharedPreferences(remote, includeRoleId: false);
      }
    }

    // Phone login API returns has_role / role_id — sync prefs with server.
    if (user.containsKey('has_role')) {
      final hasRole = user['has_role'] == true;
      if (hasRole) {
        final raw = user['role_id'];
        final rid = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
        if (rid != null && rid > 0) {
          await sharedPreferences.setString('role_id', rid.toString());
        }
      } else {
        await sharedPreferences.remove('role_id');
      }
    }

    // New-user approval flow — persist the status so the router can decide
    // between the registration form, the pending screen, or home.
    final regStatus = user['registration_status']?.toString();
    if (regStatus != null && regStatus.isNotEmpty) {
      await sharedPreferences.setString('registration_status', regStatus);
    }

    // Phase 27.3 — register the FCM device row with the user's locale
    // so server-side pushes arrive in the right language.
    unawaited(PushRegistration.registerNow());

    goToPostLoginDestination();
  }

  Future<void> _verifyOtp() async {
    final result = await _loginController.verifyOtp(_otpController.text.trim());
    if (result != null) {
      AppHaptics.success();
      await _completeLogin(result);
    } else if (_loginController.errorMessage.value.isNotEmpty) {
      AppHaptics.error();
    }
  }

  Future<void> _resendOtp() async {
    await _loginController.resendOtp();
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
                                'phone': formatPhoneForDisplay(pendingPhone),
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
                            !_loginController.isLoading.value,
                        maxLength: 6,
                        onSubmitted: (_) => _verifyOtp(),
                        decoration: InputDecoration(
                          labelText: 'Verification code'.tr,
                          hintText: 'Enter the 6-digit code'.tr,
                          counterText: '',
                        ),
                      ),
                      if (_loginController.errorMessage.value.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _loginController.errorMessage.value,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              hasPendingPhone &&
                                  !_loginController.isLoading.value
                              ? _verifyOtp
                              : null,
                          child: _loginController.isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text('Verify OTP'.tr),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed:
                              hasPendingPhone &&
                                  !_loginController.isLoading.value
                              ? _resendOtp
                              : () => Get.offAllNamed(AppRoutes.authLogin),
                          child: Text(
                            hasPendingPhone
                                ? 'Resend OTP'.tr
                                : 'Back to login'.tr,
                          ),
                        ),
                      ),
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
