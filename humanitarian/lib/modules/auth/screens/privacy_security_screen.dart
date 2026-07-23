import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/field_privacy_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Client note — "Privacy and Security" (piece 2 of the Settings/Profile
/// drawer note).
///
/// Kept to what's actually real: field-level profile privacy is the only
/// backing capability that exists. Regular accounts sign in with phone + OTP
/// (no password to change), and there's no self-service account deletion or
/// session management yet — a short note explains that instead of shipping
/// dead buttons for features that don't exist server-side.
class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Privacy and Security',
      subtitle: 'Control who can see your account details.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Get.to(() => const FieldPrivacyScreen()),
              child: GlassPanel(
                child: Row(
                  children: [
                    TileIcon(
                      icon: Icons.visibility_off_rounded,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Field privacy'.tr,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              color: AppThemeConfig.text(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'privacy_desc'.tr,
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              height: 1.35,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppThemeConfig.mutedText(context),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppThemeConfig.mutedText(context),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your account signs in with your phone number and a one-time code — there is no password to manage.'
                        .tr,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
