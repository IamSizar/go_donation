import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:get/get.dart';

import '../../../api/profile_api.dart';
import '../../../api/registration_api.dart';
import '../../../core/app_state.dart';
import '../../../core/auth_navigation.dart';
import '../../../core/theme/app_theme_config.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/widgets/brand_logo.dart';

/// Routing splash: looks identical to the native launch screen (see BrandLogo).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // R2 (owner): launch showed the logo three times in three styles. This
  // route only decides where to go; it now draws exactly what the native
  // launch screen drew (same background, same BrandLogo, same centre), so
  // the user sees one launch screen, then the next page. No animation, no
  // wordmark, no loading bar, and no artificial 2.4 s wait.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleNavigation());
  }

  Future<void> _handleNavigation() async {
    final userId = sharedPreferences.getString('id_user');
    final accessToken = currentApiAccessToken();
    if ((userId != null && userId.isNotEmpty) &&
        (accessToken == null || accessToken.isEmpty)) {
      // A16 — a stored identity with no token used to be silently re-armed by
      // POSTing the remembered phone number to /api/auth/login, which minted a
      // fresh session for anyone who knew the number. That trade no longer
      // exists: a token is only issued to a sign-in that verified a password or
      // an out-of-band code. So a missing token means the session really is
      // over — drop the stale identity and let the routing below land on
      // welcome/sign-in instead of on a signed-in screen with no session.
      await sharedPreferences.remove('id_user');
      await sharedPreferences.remove('role_id');
      await sharedPreferences.remove('registration_status');
    }
    final effectiveUserId = sharedPreferences.getString('id_user');
    String regStatus = '';
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      final id = int.tryParse(effectiveUserId);
      if (id != null && id > 0) {
        // Authoritative approval status (ungated endpoint; also refreshes
        // role_id). Drives where a returning user lands.
        final st = await fetchRegistrationStatus();
        if (st != null) {
          regStatus = (st['registration_status'] ?? '').toString();
        }
        // Best-effort profile prefs for approved users (403s while pending).
        final account = await fetchUserAccount(id);
        if (account != null) {
          await applyUserAccountToSharedPreferences(account);
        }
      }
    }

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Section 27 — a returning guest (skip sign-in) lands on Home, not the
      // welcome/login flow.
      if (isGuestMode()) {
        Get.offAllNamed(AppRoutes.home);
        return;
      }
      if (effectiveUserId == null || effectiveUserId.isEmpty) {
        Get.offAllNamed(AppRoutes.welcome);
      } else {
        routeByRegistrationStatus(regStatus);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeConfig.backgroundTop(context),
      body: const Center(child: BrandLogo()),
    );
  }
}
