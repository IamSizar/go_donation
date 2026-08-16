import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/dashboard/screens/games_screen.dart';
import 'package:flutter_application_1/modules/notifications/screens/notification_categories_screen.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/our_work_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/saved_posts_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:flutter_application_1/widgets/sound_vibration_row.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';

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

/// The label for a self-selectable role id, for the confirmation sentence.
/// Falls back to the generic word rather than printing a bare number, which is
/// what a reader would otherwise see if the map above ever gains an entry.
String _roleLabelFor(int roleId) {
  for (final entry in _selfSelectableRoles.entries) {
    if (entry.value == roleId) return entry.key;
  }
  return 'Account type';
}

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

  // Confirm first — this is a ONE-WAY door and the list row gave no sign of it.
  //
  // choose_role.go refuses a self-promotion into Recipient or Volunteer
  // (`current > 0 && !selfSelectableRole`), but Guest and Marriage ARE
  // self-selectable, so the guard does not fire for either option offered here:
  // the write goes through. A recipient who taps ضيف becomes a guest, and
  // because Recipient is NOT self-selectable they cannot undo it — only staff
  // can put the role back, after vetting.
  //
  // So a single tap on an unlabelled row could cost someone the account type
  // their aid is attached to, with no warning and nothing to cancel. Found by
  // opening this sheet as a recipient — the role nobody had signed in as before.
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Switch account type?'.tr),
      content: Text(
        'You can switch to @type yourself, but only staff can switch you back.'
            .trParams({'type': _roleLabelFor(picked).tr}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Confirm'.tr),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

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
            color: AppThemeConfig.subtleText(context),
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
            color: AppThemeConfig.accent(context),
            onTap: () => Get.to(() => const OurWorkScreen()),
          ),
          // Client backlog #23 — posts the user bookmarked for later.
          if (!guest)
            DrawerTile(
              icon: Icons.bookmark_rounded,
              label: 'Saved',
              color: AppThemeConfig.pending(context),
              onTap: () => Get.to(() => const SavedPostsScreen()),
            ),
          DrawerTile(
            icon: Icons.apps_rounded,
            label: 'Services',
            color: AppThemeConfig.accent(context),
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
            color: AppThemeConfig.accent(context),
            onTap: () => Get.to(() => const CommunityServicesSection()),
          ),
          // J6 — "اللعبة". The wheel and the coupon were both finished, but
          // their only door in the app was the donor Home quick-actions panel,
          // which is not rendered for any other role. This entry is the
          // role-neutral one the client's menu asks for; GamesScreen offers
          // both games because the client asked for a single menu entry.
          DrawerTile(
            icon: Icons.casino_rounded,
            label: 'Game',
            color: AppThemeConfig.pending(context),
            onTap: () => Get.to(() => const GamesScreen()),
          ),
          const DrawerDivider(),
          // Language uses the existing picker row (a trailing arrow that
          // opens the language list), and Dark mode its existing switch.
          const LanguageRow(),
          const DarkModeRow(),
          // "Twelfth: General Settings" + J6 — one row doing both jobs.
          //
          // It used to be the on/off switch alone, on the reasoning that the
          // list belonged behind the top-bar bell and repeating it here would
          // be duplication. The client read it the other way: الاشعارات is one
          // of the eleven ENTRIES this menu is supposed to hold, so tapping it
          // should show your notifications. It flipped a preference instead.
          //
          // Tapping the label now opens the list; the switch beside it still
          // changes the setting. The bell keeps its badge and stays the fast
          // route — this is a second door to one screen, not a second screen.
          NotificationsRow(
            onOpenList: () => Get.to(() => const NotificationsScreen()),
          ),
          // K7 — the switch above is still all-or-nothing; this is the row
          // that refines it. It is a separate entry rather than more controls
          // stacked into NotificationsRow because six switches inside a menu
          // row would bury the master switch they depend on, and because the
          // categories screen has its own four states to render.
          DrawerTile(
            icon: Icons.tune_rounded,
            label: 'Alert categories',
            color: AppThemeConfig.pending(context),
            onTap: () => Get.to(() => const NotificationCategoriesScreen()),
          ),
          // K26 — "full user control over sounds and vibration from an
          // app-settings menu". AppMute has always worked; its only UI was a
          // card on ProfileSection, and the sole route to that screen is the
          // AI assistant's 'profile' deep link — so in practice the setting
          // could only be found by asking the chatbot for it. It belongs with
          // the other preference switches, and next to Notifications in
          // particular, because the chime it silences is a notification cue.
          const SoundVibrationRow(),
          const DrawerDivider(),
          DrawerTile(
            icon: Icons.support_agent_rounded,
            label: 'Technical Support',
            color: AppThemeConfig.pending(context),
            // Was opening SupportSection — the volunteer-missions screen — so
            // "Technical Support" led to a list of volunteering opportunities.
            onTap: () => Get.to(() => const TechnicalSupportScreen()),
          ),
          DrawerTile(
            icon: Icons.info_outline_rounded,
            label: 'About Us',
            color: AppThemeConfig.accent(context),
            onTap: () => Get.to(
              () =>
                  const ContentPageScreen(slug: 'about', titleKey: 'About Us'),
            ),
          ),
          DrawerTile(
            icon: Icons.mail_outline_rounded,
            label: 'Contact Us',
            color: AppThemeConfig.pending(context),
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
            color: AppThemeConfig.subtleText(context),
            onTap: () => Get.to(() => const TermsScreen()),
          ),
          const DrawerDivider(),
          guest
              ? DrawerTile(
                  icon: Icons.login_rounded,
                  label: 'Sign in',
                  color: AppThemeConfig.accent(context),
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
