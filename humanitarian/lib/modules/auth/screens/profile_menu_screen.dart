import 'package:flutter/material.dart';

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
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/our_work_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/saved_posts_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/modules/receipts/screens/aid_receipts_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';

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

          // THE BUG THIS FIXES: the language switch used to live only far
          // down this list, inside the "Settings" card — and even THAT copy
          // only rendered `if (guest)`, so a signed-in user had no language
          // control on this screen at all (their only door to it was
          // "Control Settings and Preferences", a whole extra screen away).
          // For an app whose users are ~90% Arabic speakers, a person who
          // opens it in the wrong language and can't read the English menu
          // labels ("Profile", "Settings", "Control Settings and
          // Preferences") has no way to read their way to the fix. Right
          // after the account card — the very first thing this screen shows,
          // for guest and signed-in alike — is the one placement that
          // doesn't depend on being able to read anything to reach it.
          const SizedBox(height: 12),
          const MenuCard(children: [LanguageRow()]),

          // THE BUG THIS FIXES: this used to be a MenuGrid — three-across
          // icon tiles — for every section except Settings (already rows,
          // for the trailing values a tile can't hold) and About & support
          // (kept as tiles on purpose, still asked for by name). The
          // Language row's move to the top made the inconsistency obvious
          // side by side: one full-width bar next to a grid of squares reads
          // as two different screens stitched together. Every section down
          // to About & support now shares the Language row's own long-bar
          // style — MenuCard + DrawerTile — so this screen reads as one
          // list, not a grid that occasionally breaks into rows.
          const MenuSectionLabel('My account'),
          MenuCard(
            children: [
              if (!guest)
                DrawerTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: () =>
                      Get.to(() => const RegistrationFormPage(editMode: true)),
                ),
              if (!guest)
                DrawerTile(
                  icon: Icons.bookmark_rounded,
                  label: 'Saved',
                  color: AppThemeConfig.pending(context),
                  onTap: () => Get.to(() => const SavedPostsScreen()),
                ),
              DrawerTile(
                icon: Icons.receipt_long_rounded,
                label: 'receipts_title',
                onTap: () => Get.to(() => const AidReceiptsScreen()),
              ),
            ],
          ),

          // OPOS #25869 — the general news/activities feed used to be
          // embedded directly on the Marriage hub screen (removed per OPOS
          // #25858, since it mixed humanitarian posts into a section-specific
          // screen). Here it's a single door instead.
          const MenuSectionLabel('News'),
          MenuCard(
            children: [
              DrawerTile(
                icon: Icons.campaign_outlined,
                label: 'News and activities',
                onTap: () => Get.to(() => const NewsActivitiesScreen()),
              ),
            ],
          ),

          const MenuSectionLabel('Services'),
          MenuCard(
            children: [
              DrawerTile(
                icon: Icons.apps_rounded,
                label: 'Services',
                onTap: () => Get.to(() => const ProposalServicesSection()),
              ),
              DrawerTile(
                icon: Icons.diversity_3_rounded,
                label: 'Community Services',
                onTap: () => Get.to(() => const CommunityServicesSection()),
              ),
              // Role-segmented, exactly as before.
              if (sharedPreferences.getString('role_id') == '3')
                DrawerTile(
                  icon: Icons.volunteer_activism_rounded,
                  label: 'Volunteer With Us',
                  color: AppThemeConfig.pending(context),
                  onTap: () => Get.to(() => const SupportSection()),
                ),
              DrawerTile(
                icon: Icons.checklist_rounded,
                label: 'Task Verification',
                color: AppThemeConfig.pending(context),
                onTap: () => Get.to(() => const TaskVerificationScreen()),
              ),
              DrawerTile(
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
              // Language now has its own prominent card right below the
              // account header (see above) for every user, guest or not —
              // no longer needs a second copy here. Dark mode still does:
              // a guest still needs it, and Control Settings is closed to
              // them, so for a guest ONLY it stays here rather than
              // becoming unreachable.
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
