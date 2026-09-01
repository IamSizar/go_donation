import 'package:flutter/material.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/widgets/menu_grid.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/auth/screens/control_settings_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/registration_form.dart';
import 'package:flutter_application_1/modules/auth/screens/task_verification_screen.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/dashboard/screens/games_screen.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/our_work_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/saved_posts_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/modules/receipts/screens/aid_receipts_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';
import 'package:flutter_application_1/localization/failure_message.dart';

/// Client spec, "Ninth: Improve the Home Interface Design" — the account hub
/// opened by the circular profile photo in the top-right of every tab.
///
/// Originally split with the client: this screen owned the account and
/// public-facing items (profile, Our Work, Services, Community Services,
/// language, dark mode, support, legal/contact) while a separate Settings
/// bottom-nav tab (widgets/settings_section.dart) kept the operational
/// content (Control Settings and Preferences, Volunteer With Us, Task
/// Verification, Our Partners, receipts, share, Our Humanitarian Work, clear
/// cache), reachable from here via a "Settings" row.
///
/// The owner later asked to remove the Settings tab and move everything it
/// held into Profile, so that operational content now lives directly in this
/// screen's list too (see the "Operational" section below) — there is no
/// longer a second screen to hand off to, and no destination was dropped.
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
  final confirmed = await showAdaptiveConfirm(
    context,
    title: 'Switch account type?'.tr,
    message:
        'You can switch to @type yourself, but only staff can switch you back.'
            .trParams({'type': _roleLabelFor(picked).tr}),
    confirmLabel: 'Confirm'.tr,
    cancelLabel: 'Cancel'.tr,
  );
  if (!confirmed) return;

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
    // The server's sentence is English and unlocalizable — chooseRole goes
    // through postJson, which carries no machine code — so it goes to the log
    // and the user gets copy in their own language.
    debugPrint('chooseRole($picked) failed: $e');
    Get.snackbar('Error'.tr, failureMessage(e, 'error_role_change_failed'));
  }
}

class ProfileMenuScreen extends StatelessWidget {
  const ProfileMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();
    return SectionScaffold(
      title: 'Profile'.tr,
      subtitle: '',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          AccountHeader(guest: guest),

          // ─── DESTINATIONS AS A GRID, NOT TWELVE ROWS ─────────────────────
          // Each of these is an icon and a word. A full-width row each made
          // the screen about six screens long; three across makes it four
          // rows. Nothing is hidden — collapsing them would have been shorter
          // to LOOK at and longer to USE.
          const MenuSectionLabel('My account'),
          MenuGrid(
            items: [
              if (!guest)
                MenuGridItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: () =>
                      Get.to(() => const RegistrationFormPage(editMode: true)),
                ),
              if (!guest)
                MenuGridItem(
                  icon: Icons.badge_outlined,
                  label: 'Account type',
                  color: Colors.brown,
                  onTap: () => _chooseAccountType(context),
                ),
              if (!guest)
                MenuGridItem(
                  icon: Icons.bookmark_rounded,
                  label: 'Saved',
                  color: AppThemeConfig.pending(context),
                  onTap: () => Get.to(() => const SavedPostsScreen()),
                ),
              MenuGridItem(
                icon: Icons.receipt_long_rounded,
                label: 'receipts_title',
                onTap: () => Get.to(() => const AidReceiptsScreen()),
              ),
            ],
          ),

          const MenuSectionLabel('Services'),
          MenuGrid(
            items: [
              MenuGridItem(
                icon: Icons.apps_rounded,
                label: 'Services',
                onTap: () => Get.to(() => const ProposalServicesSection()),
              ),
              MenuGridItem(
                icon: Icons.diversity_3_rounded,
                label: 'Community Services',
                onTap: () => Get.to(() => const CommunityServicesSection()),
              ),
              // Role-segmented, exactly as before.
              if (sharedPreferences.getString('role_id') == '3')
                MenuGridItem(
                  icon: Icons.volunteer_activism_rounded,
                  label: 'Volunteer With Us',
                  color: AppThemeConfig.pending(context),
                  onTap: () => Get.to(() => const SupportSection()),
                ),
              MenuGridItem(
                icon: Icons.checklist_rounded,
                label: 'Task Verification',
                color: AppThemeConfig.pending(context),
                onTap: () => Get.to(() => const TaskVerificationScreen()),
              ),
              MenuGridItem(
                icon: Icons.casino_rounded,
                label: 'Game',
                color: AppThemeConfig.pending(context),
                onTap: () => Get.to(() => const GamesScreen()),
              ),
            ],
          ),

          // ─── SETTINGS STAYS ROWS ─────────────────────────────────────────
          // These carry switches and trailing values — a language row shows
          // WHICH language, a dark-mode row shows a three-way choice. None of
          // that survives being squeezed into a 96px tile, so the group keeps
          // full-width rows and gets a card to hold them together.
          //
          // The settings entry the owner asked to be able to see leads the
          // section it names; it used to sit mid-list between "Volunteer With
          // Us" and "Task Verification".
          // ─── ONE ENTRY, NOT A SECOND SETTINGS SURFACE ────────────────────
          // Language, appearance, notifications and sound used to sit loose
          // here, directly under the tile that opens Control Settings — so the
          // app had a settings SECTION and a settings SCREEN, and which
          // preference lived where was arbitrary. They all live in the screen
          // now; this is the door to it.
          const MenuSectionLabel('Settings'),
          MenuCard(
            children: [
              // Guests have no phone/wallet/field-privacy to manage — the same
              // gating this row has always had.
              if (!guest)
                DrawerTile(
                  icon: Icons.tune_rounded,
                  label: 'Control Settings and Preferences',
                  color: AppThemeConfig.accent(context),
                  onTap: () => Get.to(() => const ControlSettingsScreen()),
                ),
              // A guest still needs the language switch, and Control Settings
              // is closed to them — so for a guest ONLY, it stays here rather
              // than becoming unreachable.
              if (guest) const LanguageRow(),
              if (guest) const DarkModeRow(),
            ],
          ),

          const MenuSectionLabel('About & support'),
          MenuGrid(
            items: [
              MenuGridItem(
                icon: Icons.support_agent_rounded,
                label: 'Technical Support',
                color: AppThemeConfig.pending(context),
                onTap: () => Get.to(() => const TechnicalSupportScreen()),
              ),
              MenuGridItem(
                icon: Icons.emoji_events_outlined,
                label: 'Our Work',
                onTap: () => Get.to(() => const OurWorkScreen()),
              ),
              MenuGridItem(
                icon: Icons.volunteer_activism_outlined,
                label: 'Our Humanitarian Work',
                onTap: () => Get.to(
                  () => const ContentPageScreen(
                    slug: 'humanitarian-work',
                    titleKey: 'Our Humanitarian Work',
                  ),
                ),
              ),
              MenuGridItem(
                icon: Icons.handshake_rounded,
                label: 'Our Partners',
                color: AppThemeConfig.pending(context),
                onTap: () => Get.to(() => const PartnersScreen()),
              ),
              MenuGridItem(
                icon: Icons.info_outline_rounded,
                label: 'About Us',
                onTap: () => Get.to(
                  () => const ContentPageScreen(
                      slug: 'about', titleKey: 'About Us'),
                ),
              ),
              MenuGridItem(
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
              MenuGridItem(
                icon: Icons.ios_share_rounded,
                label: 'share_app',
                // The context anchors the iOS share popover — a bare
                // `shareApp` sends no origin rect and the sheet refuses.
                onTap: () => shareApp(context),
              ),
              MenuGridItem(
                icon: Icons.description_rounded,
                label: 'Terms & Conditions',
                color: AppThemeConfig.subtleText(context),
                onTap: () => Get.to(() => const TermsScreen()),
              ),
              MenuGridItem(
                icon: Icons.cleaning_services_rounded,
                label: 'clear_cache',
                color: Colors.brown,
                onTap: () => clearCache(context),
              ),
            ],
          ),

          const SizedBox(height: 24),
          // Sign out is the one destructive action here, so it is separated
          // from everything else and never folded into a group.
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
