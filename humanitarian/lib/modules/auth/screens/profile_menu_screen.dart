import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/our_work_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:get/get.dart';

/// Client spec, "Ninth: Improve the Home Interface Design" — the account hub
/// opened by the circular profile photo in the top-right of every tab.
///
/// Scope split (agreed with the client): this screen owns the account and
/// public-facing items — profile, Our Work, Services, Community Services,
/// language, dark mode, support, and the legal/contact pages.
///
/// The Settings tab keeps the remaining operational content (Our Partners,
/// Supporting Organizations, Volunteer tools, Task Verification, receipts,
/// share, clear cache) and is reachable from here via the Settings row, so
/// nothing becomes a dead end.
///
/// The notification *list* is deliberately NOT here: the client asked for a
/// single entry point and the top-bar bell (with its unread badge) is the one
/// that stays. The enable/disable *setting* does live here, as its own
/// switch — a different thing from the list.
/// Account types a user may move themselves into. Anything else is granted by
/// staff — see selfSelectableRole in the backend's choose_role handler.
const Map<String, int> _selfSelectableRoles = {'Marriage': 5, 'Guest': 0};

Future<void> _chooseAccountType(BuildContext context) async {
  final picked = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('Account type'.tr),
      children: [
        for (final entry in _selfSelectableRoles.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(entry.value),
            child: Text(entry.key.tr),
          ),
      ],
    ),
  );
  if (picked == null) return;
  try {
    final applied = await ModuleApi().chooseRole(picked);
    if (applied != picked) {
      Get.snackbar('Account type'.tr, 'Account type unchanged.'.tr);
      return;
    }
    // The dashboard reads role_key from the summary, so refetch rather than
    // patching local state — the backend is the source of truth for the role.
    if (Get.isRegistered<RoleDashboardController>()) {
      await Get.find<RoleDashboardController>().fetchSummary();
    }
    Get.snackbar('Account type'.tr, 'Account type updated.'.tr);
  } catch (e) {
    Get.snackbar('Error'.tr, e.toString().replaceFirst('Exception: ', ''));
  }
}

class ProfileMenuScreen extends StatelessWidget {
  const ProfileMenuScreen({super.key});

  /// Bottom-nav index of the Settings tab, so the Settings row can hand off
  /// to it rather than duplicating its contents here.
  static const int _settingsTabIndex = 4;

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();
    return SectionScaffold(
      title: 'Profile'.tr,
      subtitle: '',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          AccountHeader(guest: guest),
          const SizedBox(height: 12),
          if (!guest)
            DrawerTile(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
              onTap: () => Get.to(() => const EditProfilePage()),
            ),
          DrawerTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            color: Colors.blueGrey,
            onTap: () {
              // Hand off to the Settings tab instead of repeating it here.
              dashboardTabNotifier.value = _settingsTabIndex;
              Get.back();
            },
          ),
          // Client spec item 4 — "Our Work" gets its own entry inside the
          // Profile area, showing every activity and programme the
          // organization has run.
          DrawerTile(
            icon: Icons.emoji_events_outlined,
            label: 'Our Work',
            color: Colors.teal,
            onTap: () => Get.to(() => const OurWorkScreen()),
          ),
          DrawerTile(
            icon: Icons.apps_rounded,
            label: 'Services',
            color: Colors.deepPurple,
            onTap: () => Get.to(() => const ProposalServicesSection()),
          ),
          // Client backlog #4 — a user may switch their own account type, but
          // only to the two that carry no granted privilege: the marriage
          // service, or back to guest. Recipient/Volunteer stay staff-granted,
          // and the backend enforces that regardless of what the app sends.
          if (!guest)
            DrawerTile(
              icon: Icons.badge_outlined,
              label: 'Account type',
              color: Colors.brown,
              onTap: () => _chooseAccountType(context),
            ),
          DrawerTile(
            icon: Icons.diversity_3_rounded,
            label: 'Community Services',
            color: Colors.indigo,
            onTap: () => Get.to(() => const CommunityServicesSection()),
          ),
          const DrawerDivider(),
          // Language uses the existing picker row (a trailing arrow that
          // opens the language list), and Dark mode its existing switch.
          const LanguageRow(),
          const DarkModeRow(),
          // "Twelfth: General Settings" — enable/disable notifications. This
          // is the notification *setting*; the notification *list* stays
          // behind the top-bar bell, so the two aren't duplicates.
          const NotificationsRow(),
          const DrawerDivider(),
          DrawerTile(
            icon: Icons.support_agent_rounded,
            label: 'Technical Support',
            color: Colors.deepOrange,
            onTap: () => Get.to(() => const SupportSection()),
          ),
          DrawerTile(
            icon: Icons.info_outline_rounded,
            label: 'About Us',
            color: Colors.teal,
            onTap: () => Get.to(
              () =>
                  const ContentPageScreen(slug: 'about', titleKey: 'About Us'),
            ),
          ),
          DrawerTile(
            icon: Icons.mail_outline_rounded,
            label: 'Contact Us',
            color: Colors.orange,
            onTap: () => Get.to(
              () => const ContentPageScreen(
                slug: 'contact',
                titleKey: 'Contact Us',
              ),
            ),
          ),
          DrawerTile(
            icon: Icons.description_rounded,
            label: 'Terms & Conditions',
            color: Colors.blueGrey,
            onTap: () => Get.to(() => const TermsScreen()),
          ),
          const DrawerDivider(),
          guest
              ? DrawerTile(
                  icon: Icons.login_rounded,
                  label: 'Sign in',
                  color: drawerPrimary,
                  onTap: () => Get.offAllNamed('/login'),
                )
              : DrawerTile(
                  icon: Icons.logout_rounded,
                  label: 'Log out',
                  color: drawerDanger,
                  onTap: () => confirmLogout(context),
                ),
        ],
      ),
    );
  }
}
