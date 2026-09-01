import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';
import 'package:flutter_application_1/modules/auth/screens/payment_methods_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/privacy_security_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:flutter_application_1/widgets/sound_vibration_row.dart';
import 'package:flutter_application_1/widgets/menu_grid.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/modules/notifications/screens/notification_categories_screen.dart';
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
            onTap: () => Get.to<bool>(() => const RegistrationFormPage(editMode: true)),
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

          // ─── THE PREFERENCES THEMSELVES ──────────────────────────────────
          // Language, appearance, notifications and sound used to sit loose on
          // the profile menu, under a "Settings" heading, immediately below
          // the tile that opens THIS screen. So the menu had a settings
          // section AND a settings screen, and which preference lived where
          // was arbitrary — the owner's point: put them all in Settings and
          // Preferences.
          //
          // The menu now carries one entry, and everything it names is here.
          const SizedBox(height: 24),
          Text(
            'Preferences'.tr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
          const SizedBox(height: 8),
          MenuCard(
            children: [
              const LanguageRow(),
              const DarkModeRow(),
              // Notifications and its categories are ONE unit now, not two
              // entries a row apart: the master switch, and the per-category
              // refinement it governs, which is meaningless without it.
              NotificationsRow(
                onOpenList: () => Get.to(() => const NotificationsScreen()),
                onOpenCategories: () =>
                    Get.to(() => const NotificationCategoriesScreen()),
              ),
              const SoundVibrationRow(),
            ],
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
                AppIcons.forward(context),
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
