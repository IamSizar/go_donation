import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';

/// Section 27 — guest-facing versions of the Home and Account tabs. They make
/// no authenticated calls, so a signed-out guest gets a clean browse landing
/// and a clear path to sign in (instead of an auth-error placeholder).

void _goSignIn() {
  exitGuestMode();
  Get.offAllNamed(AppRoutes.authLogin);
}

/// Guest Home — a welcome hero, quick links to the enabled browse tabs, and a
/// sign-in call-to-action.
class GuestHomeSection extends StatelessWidget {
  const GuestHomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final canMarket = guestCanSee('marketplace');
    final canCommunity = guestCanSee('city_directory');

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome'.tr,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You are browsing as a guest.'.tr,
              style: TextStyle(
                fontSize: 14,
                color: AppThemeConfig.mutedText(context),
              ),
            ),
            const SizedBox(height: 20),

            // Hero card.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppThemeConfig.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.explore_rounded, color: Colors.white, size: 30),
                  const SizedBox(height: 12),
                  Text(
                    'Explore freely'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Browse campaigns, the marketplace, and community services. Sign in to donate, volunteer, and more.'
                        .tr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _goSignIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppThemeConfig.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Sign in'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            Text(
              'Browse'.tr,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 12),
            if (canMarket)
              _BrowseTile(
                icon: Icons.storefront_rounded,
                color: Colors.deepOrangeAccent,
                title: 'Marketplace'.tr,
                subtitle: 'Products from productive families'.tr,
                onTap: () => dashboardTabNotifier.value = 2,
              ),
            if (canCommunity)
              _BrowseTile(
                icon: Icons.groups_rounded,
                color: Colors.indigo,
                title: 'Community'.tr,
                subtitle: 'Local services and directory'.tr,
                onTap: () => dashboardTabNotifier.value = 3,
              ),
            if (!canMarket && !canCommunity)
              Text(
                'Sign in to access more of the app.'.tr,
                style: TextStyle(color: AppThemeConfig.mutedText(context)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrowseTile extends StatelessWidget {
  const _BrowseTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 15, color: AppThemeConfig.mutedText(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Guest Account tab — a friendly sign-in prompt shown where a signed-in user
/// would see their profile.
class GuestAccountSection extends StatelessWidget {
  const GuestAccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 120),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppThemeConfig.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_outline_rounded,
                    size: 44, color: AppThemeConfig.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'You are a guest'.tr,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your profile, donations, volunteering, and messages.'
                    .tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _goSignIn,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    'Sign in'.tr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppThemeConfig.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    exitGuestMode();
                    Get.offAllNamed(AppRoutes.authRegister);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppThemeConfig.primary,
                    side: BorderSide(color: AppThemeConfig.border(context)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Create an account'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
