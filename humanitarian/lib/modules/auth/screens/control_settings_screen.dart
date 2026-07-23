import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/auth/screens/payment_methods_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/privacy_security_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Client note — "Control Settings and Preferences" (piece 2 of the
/// Settings/Profile drawer note): the drawer's own arrow-triggered sub-page
/// grouping Account Information and Editing, Payment Methods and Payment
/// Gateways, and Privacy and Security.
class ControlSettingsScreen extends StatelessWidget {
  const ControlSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Control Settings and Preferences',
      subtitle: 'Manage your account, payments, and privacy.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _ControlOptionTile(
            icon: Icons.badge_rounded,
            title: 'Account Information and Editing',
            subtitle: 'Update your name, photo, and other account details.',
            color: Colors.teal,
            onTap: () => Get.to<bool>(() => const EditProfilePage()),
          ),
          const SizedBox(height: 12),
          _ControlOptionTile(
            icon: Icons.payment_rounded,
            title: 'Payment Methods and Payment Gateways',
            subtitle: 'Your wallet balance and the ways you can pay.',
            color: Colors.green,
            onTap: () => Get.to(() => const PaymentMethodsScreen()),
          ),
          const SizedBox(height: 12),
          _ControlOptionTile(
            icon: Icons.security_rounded,
            title: 'Privacy and Security',
            subtitle: 'Control who can see your account details.',
            color: Colors.deepPurple,
            onTap: () => Get.to(() => const PrivacySecurityScreen()),
          ),
        ],
      ),
    );
  }
}

class _ControlOptionTile extends StatelessWidget {
  const _ControlOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: GlassPanel(
          child: Row(
            children: [
              TileIcon(icon: icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle.tr,
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
    );
  }
}
