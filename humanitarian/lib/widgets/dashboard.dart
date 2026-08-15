import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/wallet_api.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/dashboard/screens/lucky_coupon_screen.dart';
import 'package:flutter_application_1/modules/dashboard/screens/wheel_of_fortune_screen.dart';
import 'package:flutter_application_1/modules/history/screens/role_history_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_my_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_submit_project_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/orphan_family_profiles_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_overview_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/shared/widgets/case_category_capsules.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart'
    show FullBleedHorizontal;
import 'package:flutter_application_1/shared/widgets/operation_status_badge.dart';
import 'package:flutter_application_1/widgets/firebase_screen_add.dart';
import 'package:flutter_application_1/widgets/impact_stats_slider.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';

import '../data/featured_campaigns.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

class DashboardHomeSection extends StatelessWidget {
  const DashboardHomeSection({super.key});

  String _roleKey(RoleDashboardController controller) {
    final backendRole = controller.roleKey.value.trim();
    if (backendRole.isNotEmpty && backendRole != 'guest') {
      return backendRole;
    }
    return switch (sharedPreferences.getString('role_id')) {
      '1' => 'donor',
      '2' => 'beneficiary',
      '3' => 'volunteer',
      _ => 'guest',
    };
  }

  int _intValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _doubleValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _listValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  String _moneyLabel(num amount) {
    return '${NumberFormat.decimalPattern().format(amount.round())} IQD';
  }

  String _paymentStatusLabel(dynamic value) {
    switch (value?.toString()) {
      case '1':
        return 'Successful'.tr;
      case '2':
        return 'Pending'.tr;
      default:
        return 'Failed'.tr;
    }
  }

  String _statusLabel(dynamic value, {String fallback = 'Pending'}) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return fallback.tr;
    // Was `raw.replaceAll('_', ' ').tr`, which humanised BEFORE looking the
    // value up — so a translated token like `needs_changes` could never match
    // its entry and always rendered the English "needs changes", even in
    // Arabic. localizedTag tries the raw token first and only humanises when
    // nothing is translated, and is the single shared mechanism for this.
    return localizedTag(raw);
  }

  String _dateLabel(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  Widget _buildHero({
    required BuildContext context,
    required String firstName,
    required Widget primaryAction,
    required List<Widget> stats,
    // Optional, and currently passed by nobody. Every role's hero used to put
    // a "My history" button here, going to the same screen as "My Engagement"
    // in the shortcuts row 18px below it — the same destination twice, within
    // one glance, in all three roles. The shortcuts row won because it is a
    // client-specified grouping; this slot stays available for a secondary
    // that is genuinely distinct from it.
    Widget? secondaryAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        // Flat, not a three-stop ramp. Contrast on a gradient is positional:
        // the previous ink→teal→mint version put white text over a stop that
        // measured 2.49:1, below even the 3.0 large-text floor, on the most
        // prominent element in the product.
        //
        // The foreground here is `onAccent`, NOT Colors.white. White is only
        // right in light mode: the dark accent is a light mint (#6FBF9C) and
        // white on it measures 2.19:1 — worse than the gradient this replaced.
        // onAccent measures 7.54:1 light / 7.72:1 dark, because it flips with
        // the palette.
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppThemeConfig.onAccent(context).withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.accent(context).withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Large faint watermark — kept subtle so it never competes with
            // the text sitting on top of it.
            Positioned(
              right: -18,
              top: -10,
              child: Icon(
                Icons.volunteer_activism_rounded,
                color: AppThemeConfig.onAccent(context).withValues(alpha: 0.07),
                size: 170,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    'Welcome back, @name'.trParams({'name': firstName}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppThemeConfig.onAccent(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: primaryAction),
                    if (secondaryAction != null) ...[
                      const SizedBox(width: 10),
                      secondaryAction,
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                Row(children: stats),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Shared white pill CTA for the hero card's primary action (task: reduce
  /// per-role duplication of the same button chrome).
  Widget _heroPrimaryButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    void Function()? onLongPress,
  }) {
    return Material(
      color: AppThemeConfig.onAccent(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppThemeConfig.accent(context), size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label.tr,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppThemeConfig.accent(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDonorDashboard(
    BuildContext context,
    Map<String, dynamic> summary,
    FeaturedCampaignsController campaignsController,
  ) {
    final stats = Map<String, dynamic>.from(summary['stats'] as Map? ?? {});
    final recentDonations = _listValue(summary, 'recent_donations');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _buildHero(
          context: context,
          firstName:
              ((sharedPreferences.getString('name_user') ?? 'No name'.tr)
                      .trim())
                  .split(RegExp(r'\s+'))
                  .first,
          primaryAction: _heroPrimaryButton(
            context: context,
            icon: Icons.favorite_rounded,
            label: 'Make donation'.tr,
            onTap: () => Get.to(() => const DonationsSection()),
          ),
          stats: [
            Expanded(
              child: _DashboardHeroStat(
                value: _moneyLabel(_doubleValue(stats, 'successful_amount')),
                label: 'Given so far',
                icon: Icons.payments_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DashboardHeroStat(
                value: '${_intValue(stats, 'active_sponsorships')}',
                label: 'Active sponsorships',
                icon: Icons.favorite_rounded,
                onTap: () => Get.to(() => const SponsorshipOverviewScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _TopShortcutsRow(),
        const SizedBox(height: 18),
        // Note #42, Section One — Financial Wallet (test phase).
        const _WalletCard(),
        const SizedBox(height: 18),
        const ImpactStatsSlider(),
        const SizedBox(height: 20),
        _StatPanel(
          items: [
            _StatItem(
              value: '${_intValue(stats, 'successful_count')}',
              label: 'Confirmed donations'.tr,
              icon: Icons.volunteer_activism_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'pending_count')}',
              label: 'Pending payments'.tr,
              icon: Icons.hourglass_top_rounded,
              color: AppThemeConfig.pending(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'active_campaigns')}',
              label: 'Open campaigns'.tr,
              icon: Icons.track_changes_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'pending_sponsorships')}',
              label: 'Pending sponsorships'.tr,
              icon: Icons.schedule_rounded,
              color: AppThemeConfig.pending(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Quick actions'),
        const SizedBox(height: 12),
        // Removed: a three-up quick-action row (Contribute / History /
        // Support). Every one of its three destinations was already reachable
        // from the hero card a few hundred pixels above, on this same screen,
        // with no scrolling in between — Contribute repeated the hero's
        // "Make donation" primary button, History repeated the hero's
        // "My history" secondary button, and Support repeated the tappable
        // "Active sponsorships" hero stat. It was the hero rendered a second
        // time as small chips, not a set of additional shortcuts, so it cost
        // vertical space and split attention without adding a single new way
        // in. The panel below survives because Wheel of Fortune and Lucky
        // Coupon have no other entry point on Home.
        _GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.casino_rounded,
                  label: 'Wheel of Fortune',
                  color: AppThemeConfig.accent(context),
                  compact: true,
                  badgeLabel: 'New',
                  onTap: () => Get.to(() => const WheelOfFortuneScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Lucky Coupon',
                  color: AppThemeConfig.accent(context),
                  compact: true,
                  badgeLabel: 'New',
                  onTap: () => Get.to(() => const LuckyCouponScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // Quick Filter Capsules (client spec, Home "Section Three") — tap a
        // category to jump straight into Orphan & Family Profiles filtered
        // to it.
        const _SectionLabel(title: 'Browse by category'),
        const SizedBox(height: 12),
        CaseCategoryCapsules(
          selected: null,
          onSelected: (slug) =>
              Get.to(() => OrphanFamilyProfilesScreen(initialCategory: slug)),
        ),
        const SizedBox(height: 22),
        const _FeaturedCampaignsSection(),
        const SizedBox(height: 22),
        // Phase 27.11 — "Latest news" media strip (public news/activities).
        const _NewsStrip(),
        const SizedBox(height: 22),
        // Phase 27.7 — "Our partners" showcase. A horizontal strip of
        // partner logos that links to the full partners screen.
        const _PartnersStrip(),
        const SizedBox(height: 22),
        // Personal activity grouped at the bottom: your recent donations,
        // then your latest alerts.
        Row(
          children: [
            const _SectionLabel(title: 'Recent donations'),
            const Spacer(),
            InkWell(
              onTap: () => Get.to(() => const MyDonationsPage()),
              child: Text(
                'See all'.tr,
                style: TextStyle(
                  color: AppThemeConfig.accent(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recentDonations.isEmpty)
          // A designed empty state, not a bare sentence in a panel.
          //
          // This is a first-time donor's most likely view of the section, so
          // it is the app's chance to say what will appear here and offer the
          // action that makes it appear — rule 5.8. It was a single line of
          // muted text with no icon, no explanation and no way forward, which
          // reads as a dead section rather than an invitation.
          _GlassPanel(
            child: AppEmpty(
              icon: Icons.volunteer_activism_rounded,
              title: 'No donations yet.',
              message: 'Your contributions will appear here once you give.',
              actionLabel: 'Make donation',
              onAction: () => Get.to(() => const DonationsSection()),
            ),
          )
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentDonations.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.receipt_long_rounded,
                    color: AppThemeConfig.accent(context),
                    title: _moneyLabel(
                      _doubleValue(recentDonations[i], 'amount'),
                    ),
                    subtitle:
                        '${((recentDonations[i]['campaign_title'] ?? 'General support').toString()).tr} · ${_paymentStatusLabel(recentDonations[i]['payment_status'])}',
                    time: _dateLabel(recentDonations[i]['transaction_date']),
                    onTap: () => Get.to(() => const RoleHistoryScreen()),
                  ),
                  if (i != recentDonations.length - 1)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBeneficiaryDashboard(
    BuildContext context,
    Map<String, dynamic> summary,
  ) {
    final stats = Map<String, dynamic>.from(summary['stats'] as Map? ?? {});
    final recentCases = _listValue(summary, 'recent_cases');
    final recentRequests = _listValue(summary, 'recent_requests');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _buildHero(
          context: context,
          firstName:
              ((sharedPreferences.getString('name_user') ?? 'No name'.tr)
                      .trim())
                  .split(RegExp(r'\s+'))
                  .first,
          primaryAction: _heroPrimaryButton(
            context: context,
            icon: Icons.add_circle_rounded,
            label: 'Submit request'.tr,
            onTap: () => Get.to(() => const BeneficiarySubmitProjectScreen()),
            onLongPress: () => Get.to(() => const FirebaseScreenAdd()),
          ),
          stats: [
            Expanded(
              child: _DashboardHeroStat(
                value: '${_intValue(stats, 'active_cases')}',
                label: 'Active cases',
                icon: Icons.assignment_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DashboardHeroStat(
                value: '${_intValue(stats, 'pending_requests')}',
                label: 'Pending requests',
                icon: Icons.schedule_rounded,
                onTap: () => Get.to(
                  () => const BeneficiaryMyProjectsScreen(
                    initialFilter: ProjectRequestFilter.pending,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _TopShortcutsRow(),
        const SizedBox(height: 18),
        const ImpactStatsSlider(),
        const SizedBox(height: 20),
        const _FeaturedCampaignsSection(),
        const SizedBox(height: 20),
        _StatPanel(
          items: [
            _StatItem(
              value: '${_intValue(stats, 'approved_cases')}',
              label: 'Approved cases'.tr,
              icon: Icons.verified_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'needs_changes_cases')}',
              label: 'Needs changes'.tr,
              icon: Icons.edit_note_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'approved_requests')}',
              label: 'Approved requests'.tr,
              icon: Icons.volunteer_activism_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'open_support_tickets')}',
              label: 'Open support tickets'.tr,
              icon: Icons.support_agent_rounded,
              color: AppThemeConfig.accent(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Quick actions'),
        const SizedBox(height: 12),
        _GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          // "Submit" and "Pending" were removed: Submit repeated the hero's
          // primary button and Pending repeated the hero stat directly above,
          // both within one glance. Pending was doubly redundant — pending is
          // now a filter chip INSIDE the requests screen, so the shortcut
          // pointed at a view the destination already offers.
          //
          // "My requests" stays and is the whole panel: it is the only route
          // in the app to the UNFILTERED request list, so unlike the donor
          // panel this one could not simply be deleted.
          child: Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.folder_open_rounded,
                  label: 'My requests',
                  color: AppThemeConfig.accent(context),
                  onTap: () =>
                      Get.to(() => const BeneficiaryMyProjectsScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Recent case updates'),
        const SizedBox(height: 12),
        if (recentCases.isEmpty)
          _GlassPanel(child: Text('No beneficiary cases yet.'.tr))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentCases.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.assignment_rounded,
                    color: AppThemeConfig.accent(context),
                    title: (recentCases[i]['public_title'] ?? 'Case')
                        .toString(),
                    subtitle:
                        '${_statusLabel(recentCases[i]['verification_status'], fallback: 'submitted')} · ${_statusLabel(recentCases[i]['priority_level'], fallback: 'medium')}',
                    time: _dateLabel(recentCases[i]['updated_at']),
                    onTap: () => Get.to(() => const RoleHistoryScreen()),
                  ),
                  if (i != recentCases.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Project request progress'),
        const SizedBox(height: 12),
        if (recentRequests.isEmpty)
          _GlassPanel(child: Text('No submitted requests yet.'.tr))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentRequests.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.flag_rounded,
                    color: AppThemeConfig.accent(context),
                    title: (recentRequests[i]['project_title'] ?? 'Request')
                        .toString(),
                    subtitle:
                        '${_moneyLabel(_doubleValue(recentRequests[i], 'amount_needed'))} · ${_statusLabel(recentRequests[i]['status'], fallback: 'submitted')}',
                    time: _dateLabel(recentRequests[i]['updated_at']),
                    onTap: () => Get.to(() => const RoleHistoryScreen()),
                  ),
                  if (i != recentRequests.length - 1)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        const SizedBox(height: 22),
        // Phase 27.11 — public "Latest news" strip on the beneficiary home.
        const _NewsStrip(),
      ],
    );
  }

  Widget _buildVolunteerDashboard(
    BuildContext context,
    Map<String, dynamic> summary,
  ) {
    final stats = Map<String, dynamic>.from(summary['stats'] as Map? ?? {});
    final application = Map<String, dynamic>.from(
      summary['application'] as Map? ?? {},
    );
    final upcomingMissions = _listValue(summary, 'upcoming_missions');
    final applicationStatus = (stats['application_status'] ?? '').toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _buildHero(
          context: context,
          firstName:
              ((sharedPreferences.getString('name_user') ?? 'No name'.tr)
                      .trim())
                  .split(RegExp(r'\s+'))
                  .first,
          primaryAction: _heroPrimaryButton(
            context: context,
            icon: Icons.front_hand_rounded,
            label: 'Open missions'.tr,
            onTap: () => Get.to(() => const SupportSection()),
          ),
          stats: [
            Expanded(
              child: _DashboardHeroStat(
                value: '${_intValue(stats, 'active_missions')}',
                label: 'Active missions',
                icon: Icons.task_alt_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DashboardHeroStat(
                value:
                    '${_doubleValue(stats, 'hours_served').toStringAsFixed(0)}h',
                label: 'Hours served',
                icon: Icons.timer_rounded,
                onTap: () => Get.to(() => const SupportSection()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _TopShortcutsRow(),
        const SizedBox(height: 18),
        const ImpactStatsSlider(),
        const SizedBox(height: 20),
        const _FeaturedCampaignsSection(),
        const SizedBox(height: 20),
        _StatPanel(
          items: [
            _StatItem(
              value: '${_intValue(stats, 'available_missions')}',
              label: 'Available missions'.tr,
              icon: Icons.assignment_turned_in_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: '${_intValue(stats, 'completed_missions')}',
              label: 'Completed missions'.tr,
              icon: Icons.workspace_premium_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: applicationStatus.isEmpty
                  ? 'None'
                  : applicationStatus.replaceAll('_', ' '),
              label: 'Application status'.tr,
              icon: Icons.person_add_alt_1_rounded,
              color: AppThemeConfig.accent(context),
            ),
            _StatItem(
              value: (application['city'] ?? '—').toString(),
              label: 'Application city'.tr,
              icon: Icons.location_city_rounded,
              color: AppThemeConfig.accent(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Quick actions'),
        const SizedBox(height: 12),
        _GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.front_hand_rounded,
                  label: 'Missions',
                  color: AppThemeConfig.accent(context),
                  onTap: () => Get.to(() => const SupportSection()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.badge_rounded,
                  label: 'Apply',
                  color: AppThemeConfig.accent(context),
                  onTap: () =>
                      Get.to(() => const VolunteerApplicationFormScreen()),
                ),
              ),
              // Removed: a third "History" chip pointing at RoleHistoryScreen.
              // The volunteer already reaches that exact screen twice higher
              // up the same page — the hero's "My history" button and the
              // "My Engagement" shortcut directly beneath it — and this chip
              // was additionally mislabelled with a notifications bell, so it
              // advertised a destination it did not go to. "Missions" and
              // "Apply" stay: Apply is the only route to the application form,
              // and Missions is the row's anchor action.
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'My mission schedule'),
        const SizedBox(height: 12),
        if (upcomingMissions.isEmpty)
          _GlassPanel(child: Text('No missions joined yet.'.tr))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < upcomingMissions.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.task_alt_rounded,
                    color: AppThemeConfig.accent(context),
                    title: (upcomingMissions[i]['title'] ?? 'Mission')
                        .toString(),
                    subtitle:
                        '${_statusLabel(upcomingMissions[i]['signup_status'])} · ${(upcomingMissions[i]['city'] ?? '').toString()}',
                    time: _dateLabel(upcomingMissions[i]['mission_date']),
                    onTap: () => Get.to(() => const RoleHistoryScreen()),
                  ),
                  if (i != upcomingMissions.length - 1)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        const SizedBox(height: 22),
        // Phase 27.11 — public "Latest news" strip on the volunteer home.
        const _NewsStrip(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final campaignsController = Get.isRegistered<FeaturedCampaignsController>()
        ? Get.find<FeaturedCampaignsController>()
        : Get.put(FeaturedCampaignsController());
    final controller = Get.isRegistered<RoleDashboardController>()
        ? Get.find<RoleDashboardController>()
        : Get.put(RoleDashboardController());

    return Obx(() {
      final roleKey = _roleKey(controller);
      // READ INSIDE THE Obx BUILDER, deliberately.
      //
      // Obx only subscribes to observables read during its OWN synchronous
      // build. These three used to be read inside the nested Builder below,
      // which Flutter invokes later — so Obx never subscribed to them and the
      // only tracked value was roleKey.
      //
      // The consequence was severe and invisible in tests: roleKey stays
      // 'guest' whenever the summary request fails, so nothing ever triggered
      // a rebuild, so the FIRST paint — isLoading true — was frozen on screen
      // permanently. The Home dashboard's error branch and its retry button
      // could never render at all. Caught by running the app against a backend
      // returning 500: a skeleton that never resolved, with no way out.
      final isLoading = controller.isLoading.value;
      final error = controller.errorMessage.value;
      final summary = Map<String, dynamic>.from(controller.summary);
      return _SectionScaffold(
        // Note #41 — the title and profile avatar moved to the persistent
        // top bar (shown above every tab now, not just Home), so neither is
        // repeated here. The Technical support and Refresh header buttons
        // were removed — support is reachable from Settings, and refreshing
        // is now a plain pull-to-refresh on the list below.
        child: Builder(
          builder: (context) {
            if (isLoading && summary.isEmpty) {
              // A skeleton, not a spinner, so the first paint has roughly the
              // shape of the dashboard that replaces it. Deliberately NOT
              // AppAsync: the summary is a Map, and it has no empty state
              // distinct from "not loaded", so AppAsync's required `empty`
              // would be a state that can never occur.
              return Padding(
                padding: const EdgeInsets.all(20),
                child: AppSkeleton.rows(),
              );
            }
            if (error != null && summary.isEmpty) {
              // AppErrorState, not a bespoke Center/Column. This was the
              // app's fourth hand-rolled error presentation, and being
              // hand-rolled it rendered `Text(error)` WITHOUT `.tr` — so the
              // message stayed English for every Arabic and Kurdish user,
              // beside a "Retry" button that WAS translated. Using the shared
              // widget gets translation, the design-system styling and the
              // retry affordance from one place.
              return Padding(
                padding: const EdgeInsets.all(20),
                child: AppErrorState(
                  message: error,
                  onRetry: controller.fetchSummary,
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: controller.fetchSummary,
              // 'marriage' (and 'employee') have no bespoke summary yet —
              // the backend returns an empty Stats for them — so they fall
              // through to the donor layout, which degrades to zeros rather
              // than rendering nothing.
              child: switch (roleKey) {
                'beneficiary' => _buildBeneficiaryDashboard(context, summary),
                'volunteer' => _buildVolunteerDashboard(context, summary),
                _ => _buildDonorDashboard(
                  context,
                  summary,
                  campaignsController,
                ),
              },
            );
          },
        ),
      );
    });
  }
}

/// Note #42 — "Financial Wallet" card (test phase). Shows the donor's
/// current IQD balance. There's no in-app top-up button: for now, funds are
/// only added by an admin from the dashboard (see AdminTopUp) — a real
/// payment-gateway top-up flow is a later piece of this note, not this one.
/// The balance is spendable today as an "App Wallet" payment option on the
/// donation and marketplace checkout screens.
class _WalletCard extends StatefulWidget {
  const _WalletCard();

  @override
  State<_WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<_WalletCard> {
  int? _balanceIQD;
  // True once a load attempt failed. Kept separate from `_balanceIQD == null`
  // so the card can tell "still loading" apart from "we couldn't find out".
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the balance, swallowing the error into an explicit unknown state.
  ///
  /// [fetchWalletBalance] throws on failure. Home genuinely cannot show a
  /// full-screen error for one card, so the failure is contained here — but it
  /// is contained as "unknown", not as 0. The card keeps its shape and renders
  /// a dash where the number goes, so the layout never jumps and the user is
  /// never told they have no money when we simply could not ask.
  Future<void> _load() async {
    try {
      final balance = await fetchWalletBalance();
      if (!mounted) return;
      setState(() {
        _balanceIQD = balance.balanceIQD;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _balanceIQD = null;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balanceIQD;
    // Compact single-row layout: icon · label+balance · info button. No
    // top-up/add-funds action — top-ups are staff-only for now (see the
    // info dialog below), so the card must not imply otherwise.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: AppThemeConfig.onAccent(context),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Tapping the balance retries a failed load — the card has no other
          // way out, and Home can't surface a retry button without changing
          // its height.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loadFailed ? _load : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _loadFailed
                        ? 'Balance unavailable — tap to retry'.tr
                        : 'My wallet'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppThemeConfig.onAccent(
                        context,
                      ).withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Three states in one slot, all the same height so the card
                  // never resizes: '···' while loading, an em dash when the
                  // balance is unknown, the real figure otherwise. A dash is
                  // used rather than 0 because 0 is a claim we can't make.
                  Text(
                    _loadFailed
                        ? '—'
                        : balance == null
                        ? '···'
                        : '${NumberFormat('#,##0').format(balance)} IQD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppThemeConfig.onAccent(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'How do I add funds?'.tr,
            child: IconButton(
              tooltip: 'How do I add funds?'.tr,
              icon: Icon(
                Icons.info_outline_rounded,
                color: AppThemeConfig.onAccent(context),
              ),
              onPressed: () => Get.dialog(
                AlertDialog(
                  title: Text('My wallet'.tr),
                  // Kept the original, already-fully-translated (en/ar/ckb/
                  // kmr) copy rather than the spec's suggested new sentence,
                  // which has no non-English translation yet — swapping
                  // would silently show English to Arabic/Kurdish users.
                  content: Text(
                    'Wallet top-ups are added by our team for now. Contact support to add funds, then use "App Wallet" as a payment option when donating or buying.'
                        .tr,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: Text('OK'.tr),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Featured campaigns strip — shown on every role's home tab. All roles can
/// browse; only donors get the donate action on the campaign detail screen.
class _FeaturedCampaignsSection extends StatelessWidget {
  const _FeaturedCampaignsSection();

  @override
  Widget build(BuildContext context) {
    final campaignsController = Get.isRegistered<FeaturedCampaignsController>()
        ? Get.find<FeaturedCampaignsController>()
        : Get.put(FeaturedCampaignsController());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel(title: 'Featured campaigns'),
            const Spacer(),
            InkWell(
              onTap: () => Get.to(() => const DonationsSection()),
              child: Text(
                'See all'.tr,
                style: TextStyle(
                  color: AppThemeConfig.accent(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Obx(() {
          // One fixed height around all four states. Each branch used to size
          // itself - 340 for loading, 200 for the error, an intrinsic panel
          // for empty - so the page visibly jumped as the fetch settled. The
          // error state also had NO retry: a failed carousel was a dead end
          // until the user left the screen and came back.
          //
          // The SizedBox must stay OUTSIDE FullBleedHorizontal: OverflowBox
          // sizes from its own incoming constraints, which are unbounded in
          // height here (a Column under a ListView), so nesting it inside
          // would make OverflowBox report an infinite height and corrupt the
          // rest of the list's layout.
          return SizedBox(
            height: 340,
            child: AppAsync<List<dynamic>>(
              loading: campaignsController.isLoading.value,
              error: campaignsController.errorMessage.value,
              onRetry: campaignsController.refreshCampaigns,
              data: campaignsController.campaigns,
              isEmpty: (list) => list.isEmpty,
              empty: AppEmpty(
                title: 'No campaigns available.'.tr,
                message:
                    'Featured campaigns will appear here once published.'.tr,
              ),
              // Client note — this horizontal carousel sits inside the page's
              // 20px side padding, so its own scroll viewport was clipped
              // ~20px short of the real screen edge on both sides: dragging a
              // card toward the edge made it disappear early. FullBleedHorizontal
              // cancels that parent inset just for this row, and the matching
              // positive padding on the ListView restores the resting look.
              builder: (list) => FullBleedHorizontal(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: list
                      .map((campaign) => _CampaignCard(campaign: campaign))
                      .toList(),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// The dashboard title now lives in the persistent top bar (same row as the
/// Search/Notifications/Messages icons, top-left) instead of a separate
/// header line here — see `_DashboardTopBar` in dashboard_screen.dart, which
/// calls [dashboardTitleForRole] below.
class _SectionScaffold extends StatelessWidget {
  const _SectionScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          // Both stops resolved to the same token, so this was already
          // painting flat. Stated plainly instead.
          color: AppThemeConfig.backgroundTop(context),
        ),
        child: SafeArea(child: child),
      ),
    );
  }
}

/// Role-specific dashboard title, shared between the Home tab's own state
/// (which picks the right role variant to build) and the persistent top bar
/// (which now displays this title at the top-left, next to the icons).
String dashboardTitleForRole(String roleKey) => switch (roleKey) {
  'donor' => 'Donor dashboard',
  'beneficiary' => 'Beneficiary dashboard',
  'volunteer' => 'Volunteer dashboard',
  'marriage' => 'Marriage dashboard',
  _ => 'Dashboard',
};

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.shadow(context),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppThemeConfig.accent(context),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.tr,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppThemeConfig.text(context),
          ),
        ),
      ],
    );
  }
}

class _IconShell extends StatelessWidget {
  const _IconShell({
    required this.icon,
    required this.color,
    this.size = 54,
    this.iconSize = 24,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _IconShell(icon: icon, color: color, size: 50, iconSize: 22);
  }
}

/// One stat shown inside a [_StatPanel] cell (task #11).
class _StatItem {
  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

/// Groups several stats into ONE rounded rectangle as segmented cells (two per
/// row, split by hairline dividers) instead of a grid of separate tiles —
/// task #11. Theme-aware and RTL-safe; handles 3 or 4 items cleanly.
class _StatPanel extends StatelessWidget {
  const _StatPanel({required this.items});

  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    final divider = AppThemeConfig.border(context);
    // Chunk into rows of two so any count (3 or 4) lays out as a tidy grid.
    final rows = <List<_StatItem>>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(items.sublist(i, i + 2 > items.length ? items.length : i + 2));
    }
    return _GlassPanel(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) Divider(height: 1, thickness: 1, color: divider),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < rows[r].length; c++) ...[
                    if (c > 0)
                      VerticalDivider(width: 1, thickness: 1, color: divider),
                    Expanded(child: _StatCell(item: rows[r][c])),
                  ],
                  // Keep a lone trailing cell half-width for a tidy grid.
                  if (rows[r].length.isOdd) const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconShell(
            icon: item.icon,
            color: item.color,
            size: 46,
            iconSize: 21,
          ),
          const SizedBox(height: 12),
          Text(
            item.value.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeroStat extends StatelessWidget {
  const _DashboardHeroStat({
    required this.value,
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeConfig.onAccent(context).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppThemeConfig.onAccent(context).withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppThemeConfig.onAccent(context),
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(
                      context,
                    ).withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Client note — "Our Products" / "My Engagement" / "City Guide" grouped
/// together in one equally-divided rectangle near the top of Home, so all
/// three destinations are reachable in a single glance without scrolling.
class _TopShortcutsRow extends StatelessWidget {
  const _TopShortcutsRow();

  /// Bottom-nav index of the City Guide tab, per the `_sections` list in
  /// dashboard_screen.dart. Named rather than inlined, matching the
  /// `_settingsTabIndex` precedent in profile_menu_screen.dart.
  static const int _cityGuideTabIndex = 3;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.storefront_rounded,
              label: 'Our Products',
              color: AppThemeConfig.accent(context),
              compact: true,
              onTap: () => Get.to(() => const MarketplaceSection()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickAction(
              icon: Icons.volunteer_activism_rounded,
              label: 'My Engagement',
              color: AppThemeConfig.accent(context),
              compact: true,
              onTap: () => Get.to(() => const RoleHistoryScreen()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickAction(
              icon: Icons.explore_rounded,
              label: 'City Guide',
              color: AppThemeConfig.accent(context),
              compact: true,
              // Selects the City Guide TAB rather than pushing a second copy
              // of the same screen on top of it. CityGuideScreen is already
              // tab 3 (dashboard_screen.dart), so `Get.to` here stacked a
              // duplicate the user then had to back out of, landing them on
              // the identical screen they had just left.
              //
              // The shortcut itself stays: this row is a client-specified
              // grouping, and the duplication was in HOW it navigated, not in
              // the entry point existing.
              onTap: () => dashboardTabNotifier.value = _cityGuideTabIndex,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.badgeLabel,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  // Smaller icon chip + font so two-word labels (e.g. "My Engagement") wrap
  // cleanly at the word boundary instead of breaking mid-word.
  final bool compact;
  // Small corner pill (e.g. "New") for newly-added quick actions.
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    // Quick actions are navigation shortcuts, not the point of the screen.
    // They were reading as the loudest thing on Home; scaled down so the
    // headline figure and the campaigns keep the emphasis.
    final boxSize = compact ? 38.0 : 44.0;
    final iconSize = compact ? 17.0 : 20.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 9, 6, 9),
            decoration: BoxDecoration(
              color: AppThemeConfig.softSurface(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            child: Column(
              children: [
                Container(
                  width: boxSize,
                  height: boxSize,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: color.withValues(alpha: 0.14)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (badgeLabel == null)
                        Positioned(
                          top: 7,
                          right: 7,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      Icon(icon, color: color, size: iconSize),
                      if (badgeLabel != null)
                        Positioned(
                          top: -8,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppThemeConfig.onAccent(context),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              badgeLabel!.tr,
                              style: TextStyle(
                                color: AppThemeConfig.onAccent(context),
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label.tr,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 11.5 : 12.5,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});

  final FeaturedCampaignData campaign;

  @override
  Widget build(BuildContext context) {
    // Phase 27.7 — redesigned card: whole card is tappable (→ campaign
    // detail), a prominent funded-percent + raised/goal block, and a
    // thicker gradient progress bar. Cleaner hierarchy than the old
    // info-line stack.
    final pct = (campaign.fundedProgress.clamp(0.0, 1.0) * 100).round();
    final accent = AppThemeConfig.accent(context);

    return Container(
      width: 244,
      margin: const EdgeInsetsDirectional.only(end: 14),
      decoration: BoxDecoration(
        // A single tint over the card surface, replacing a three-stop ramp
        // from surface through two accent alphas.
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Get.to(() => CampaignDetailScreen(campaign: campaign))
              ?.then((donate) {
                if (donate == true) {
                  Get.to(
                    () => DonationsSection(initialCampaignId: campaign.id),
                  );
                }
              }),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Header: icon + category chip + status badge ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _IconShell(
                      icon: campaign.icon,
                      color: accent,
                      size: 52,
                      iconSize: 26,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppThemeConfig.surface(context),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          campaign.category.trim().isNotEmpty
                              ? campaign.category
                              : 'Trending'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OperationStatusBadge(
                      progress: campaign.fundedProgress,
                      size: 40,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ---- Title ----
                Text(
                  campaign.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    height: 1.2,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 5),
                // ---- Location (single compact line) ----
                Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 13,
                      color: accent.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        campaign.location.trim().isNotEmpty
                            ? campaign.location
                            : campaign.impact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ),
                  ],
                ),

                // Pushes the funding block to the bottom regardless of
                // how long the title wrapped — keeps every card aligned.
                const Spacer(),

                // ---- Funding block: big % + raised/goal ----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'funded'.tr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
                // The raised/goal figures get their OWN full-width line.
                //
                // They used to sit in the Row above, sharing a 256pt card with
                // a 22pt percentage, so a real campaign rendered as
                // "9,000,000 ..." — the goal clipped off entirely. Truncating
                // a money figure is worse than wrapping one: the reader cannot
                // tell 9,000,000 from 9,000,000,000, and this is the number
                // that tells them whether the campaign still needs them.
                //
                // Abbreviating to "9M" was the other option and was rejected
                // for the same reason — precision is the point here.
                if (campaign.fundingAmountsLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    campaign.fundingAmountsLine,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // ---- Thick gradient progress bar ----
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 10,
                    color: accent.withValues(alpha: 0.14),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: campaign.fundedProgress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // ---- Donate CTA hint ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'View & donate'.tr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    Icon(
                      AppIcons.forwardSolid(context),
                      size: 16,
                      color: accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Phase 27.11 — "Latest news" home-tab section. Horizontal strip of media
// posts (news / activities) with a cover image, title, and date. Pulls
// from the shared MediaPostsController and links to the full news screen.
// Hidden entirely when there are no posts so the home tab stays clean.
class _NewsStrip extends StatelessWidget {
  const _NewsStrip();

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MediaPostsController>()
        ? Get.find<MediaPostsController>()
        : Get.put(MediaPostsController());

    return Obx(() {
      if (controller.isLoading.value && controller.posts.isEmpty) {
        return const SizedBox.shrink();
      }
      if (controller.posts.isEmpty) {
        return const SizedBox.shrink();
      }
      // Cap to the most recent 8 so the strip stays snappy; "See all"
      // opens the full screen.
      final items = controller.posts.take(8).toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel(title: 'Latest news'),
              const Spacer(),
              InkWell(
                onTap: () => Get.to(() => const NewsActivitiesScreen()),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'See all'.tr,
                    style: TextStyle(
                      color: AppThemeConfig.accent(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // See the matching note on _FeaturedCampaignsSection re: why the
          // fixed-height SizedBox must wrap FullBleedHorizontal, not nest
          // inside it — bleeds this carousel to the true screen edges
          // instead of clipping early at the page's side padding.
          SizedBox(
            height: 208,
            child: FullBleedHorizontal(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _NewsCard(post: items[i]),
              ),
            ),
          ),
        ],
      );
    });
  }
}

// One news card: cover image (or gradient fallback) + title + date.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(post, 'title', fallback: 'Post');
    // localizedTag: post_type is a backend enum (activity/event/news/
    // article) and was printed raw, so the Arabic UI showed the English
    // word on every card.
    final type = localizedTag(post['post_type'] ?? 'news');
    final dateRaw = (post['event_date'] ?? post['created_at'] ?? '').toString();
    final imageUrl = _dashboardMediaUrl(post['media_url']);

    return SizedBox(
      width: 256,
      child: Material(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Get.to(() => const NewsActivitiesScreen()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover
              SizedBox(
                height: 120,
                width: double.infinity,
                child: imageUrl == null
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppThemeConfig.accent(context),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.article_rounded,
                            color: AppThemeConfig.onAccent(context),
                            size: 34,
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppThemeConfig.softSurface(context),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            color: AppThemeConfig.accent(context),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.article_rounded,
                              color: AppThemeConfig.onAccent(context),
                              size: 34,
                            ),
                          ),
                        ),
                      ),
              ),
              // Text
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppThemeConfig.accent(
                              context,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            type.tr,
                            style: TextStyle(
                              color: AppThemeConfig.accent(context),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (dateRaw.isNotEmpty)
                          Text(
                            _dashboardMediaDate(dateRaw),
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Date label for news cards (top-level twin of DashboardHomeSection's
// private _dateLabel, which isn't reachable from these standalone widgets).
String _dashboardMediaDate(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('dd MMM yyyy').format(parsed.toLocal());
}

// Resolve a media path to an absolute URL (absolute passes through;
// bare domains get https; relative paths resolve against publicBaseUrl).
String? _dashboardMediaUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  if (RegExp(
    r'^(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-zA-Z]{2,}\b',
  ).hasMatch(path)) {
    return 'https://$path';
  }
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}

// Phase 27.7 — "Our partners" home-tab section. Pulls from
// PartnersController (shared GetX singleton) and shows a horizontal strip
// of logo cards. Hidden entirely when there are no partners so the home
// tab doesn't show an empty header.
class _PartnersStrip extends StatelessWidget {
  const _PartnersStrip();

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<PartnersController>()
        ? Get.find<PartnersController>()
        : Get.put(PartnersController());

    return Obx(() {
      // While loading the very first time, reserve nothing — the section
      // simply appears once data lands. Keeps the home tab from jumping.
      if (controller.isLoading.value && controller.partners.isEmpty) {
        return const SizedBox.shrink();
      }
      if (controller.partners.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel(title: 'Our partners'),
              const Spacer(),
              InkWell(
                onTap: () => Get.to(() => const PartnersScreen()),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'See all'.tr,
                    style: TextStyle(
                      color: AppThemeConfig.accent(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // See the matching note on _FeaturedCampaignsSection re: why the
          // fixed-height SizedBox must wrap FullBleedHorizontal, not nest
          // inside it — bleeds this carousel to the true screen edges
          // instead of clipping early at the page's side padding.
          SizedBox(
            height: 132,
            child: FullBleedHorizontal(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: controller.partners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) =>
                    _PartnerLogoCard(partner: controller.partners[i]),
              ),
            ),
          ),
        ],
      );
    });
  }
}

// One partner logo card: rounded logo tile + name beneath. Tapping opens
// the full partners screen (the card itself doesn't deep-link to a single
// partner since that screen lists them all with details).
class _PartnerLogoCard extends StatelessWidget {
  const _PartnerLogoCard({required this.partner});

  final Map<String, dynamic> partner;

  @override
  Widget build(BuildContext context) {
    final name = _localizedPartnerName(partner);
    final logoUrl = _dashboardPartnerLogoUrl(partner['logo_path']);

    return SizedBox(
      width: 104,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Get.to(() => const PartnersScreen()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppThemeConfig.surface(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppThemeConfig.border(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl == null
                    ? Center(
                        child: Text(
                          name.isNotEmpty ? name.characters.first : '?',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppThemeConfig.accent(context),
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: logoUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(
                            name.isNotEmpty ? name.characters.first : '?',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppThemeConfig.accent(context),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Localized partner name with EN fallback. Mirrors the partners_screen
// logic but kept local so the dashboard doesn't import private helpers.
String _localizedPartnerName(Map<String, dynamic> p) {
  for (final key in ['name', 'name_en', 'title']) {
    final v = (p[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return 'Partner';
}

// Resolve a partner logo path to an absolute URL (same rule as the
// partners screen: absolute URLs pass through, relative paths resolve
// against publicBaseUrl).
String? _dashboardPartnerLogoUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}

class _DashboardActivityTile extends StatelessWidget {
  const _DashboardActivityTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TileIcon(icon: icon, color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle.tr,
                style: TextStyle(
                  color: AppThemeConfig.mutedText(context),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              time.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(height: 2),
              Icon(
                AppIcons.chevronForward(context),
                size: 18,
                color: AppThemeConfig.mutedText(context),
              ),
            ],
          ],
        ),
      ],
    );

    if (onTap == null) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: row,
        ),
      ),
    );
  }
}
