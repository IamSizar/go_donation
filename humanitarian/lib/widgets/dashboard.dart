import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/history/screens/role_history_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_my_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_pending_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_submit_project_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_overview_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/bot/screens/bot_chat_screen.dart';
import 'package:flutter_application_1/widgets/firebase_screen_add.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/routes/app_routes.dart';

import '../data/featured_campaigns.dart';

class DashboardHomeSection extends StatelessWidget {
  const DashboardHomeSection({super.key});

  static const Color _primary = Color(0xFF0F766E);
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _ink = Color(0xFF0F172A);

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
    return raw.replaceAll('_', ' ').tr;
  }

  String _dateLabel(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  String _roleSubtitle(String roleKey) {
    return switch (roleKey) {
      'beneficiary' =>
        'Follow your requests, approvals, and support progress from one place.',
      'volunteer' =>
        'Keep your missions, application status, and field updates in view.',
      _ => 'Track your donations, campaigns, and trust signals from one place.',
    };
  }

  String _heroBadge(String roleKey) {
    return switch (roleKey) {
      'beneficiary' => 'Support follow-up',
      'volunteer' => 'Mission tracker',
      _ => 'Giving analytics',
    };
  }

  String _heroBody(String roleKey) {
    return switch (roleKey) {
      'beneficiary' =>
        'See what is under review, what needs action, and which requests have already moved forward.',
      'volunteer' =>
        'Stay ready for the next mission, keep an eye on approvals, and track the work you have already completed.',
      _ =>
        'Your giving is supporting families, community requests, and trusted campaigns with live updates.',
    };
  }

  Widget _buildRefreshButton(RoleDashboardController controller) {
    return Obx(
      () => _HeaderIconButton(
        tooltip: 'Refresh'.tr,
        icon: controller.isLoading.value
            ? Icons.hourglass_top_rounded
            : Icons.refresh_rounded,
        onPressed: controller.isLoading.value ? () {} : controller.fetchSummary,
      ),
    );
  }

  Widget _buildHero({
    required String firstName,
    required String badge,
    required String body,
    required Widget primaryAction,
    required Widget secondaryAction,
    required List<Widget> stats,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_ink, _primary, _accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: 8,
            child: Icon(
              Icons.volunteer_activism_rounded,
              color: Colors.white.withValues(alpha: 0.08),
              size: 156,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      badge.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Welcome back,\n@name'.trParams({'name': firstName}),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: primaryAction),
                  const SizedBox(width: 12),
                  secondaryAction,
                ],
              ),
              const SizedBox(height: 22),
              Row(children: stats),
            ],
          ),
        ],
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
    final recentNotifications = _listValue(summary, 'recent_notifications');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        _buildHero(
          firstName:
              ((sharedPreferences.getString('name_user') ?? 'No name'.tr)
                      .trim())
                  .split(RegExp(r'\s+'))
                  .first,
          badge: _heroBadge('donor'),
          body: _heroBody('donor'),
          primaryAction: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => dashboardTabNotifier.value = 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Make donation'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          secondaryAction: _WatchNowButton(
            label: 'My history',
            onTap: () => Get.to(() => const RoleHistoryScreen()),
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
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'successful_count')}',
                subtitle: 'Confirmed donations',
                icon: Icons.volunteer_activism_rounded,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'pending_count')}',
                subtitle: 'Pending payments',
                icon: Icons.hourglass_top_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'active_campaigns')}',
                subtitle: 'Open campaigns',
                icon: Icons.track_changes_rounded,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'pending_sponsorships')}',
                subtitle: 'Pending sponsorships',
                icon: Icons.schedule_rounded,
                color: Colors.pink,
              ),
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
                  icon: Icons.send_rounded,
                  label: 'Contribute',
                  color: Colors.orange,
                  onTap: () => dashboardTabNotifier.value = 4,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.receipt_long_rounded,
                  label: 'History',
                  color: Colors.blueAccent,
                  onTap: () => Get.to(() => const RoleHistoryScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.favorite_rounded,
                  label: 'Support',
                  color: Colors.teal,
                  onTap: () => Get.to(() => const SponsorshipOverviewScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _ExploreRow(),
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
            Text(
              'See all'.tr,
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recentDonations.isEmpty)
          const _GlassPanel(child: Text('No donations yet.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentDonations.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.receipt_long_rounded,
                    color: Colors.teal,
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
        const SizedBox(height: 20),
        const _SectionLabel(title: 'Latest alerts'),
        const SizedBox(height: 12),
        if (recentNotifications.isEmpty)
          const _GlassPanel(child: Text('No recent alerts.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentNotifications.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.notifications_active_rounded,
                    color: Colors.amber,
                    title: (recentNotifications[i]['title'] ?? 'Notification')
                        .toString(),
                    subtitle: (recentNotifications[i]['body'] ?? '').toString(),
                    time: _dateLabel(recentNotifications[i]['created_at']),
                    onTap: () => Get.toNamed(AppRoutes.notifications),
                  ),
                  if (i != recentNotifications.length - 1)
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
    final recentNotifications = _listValue(summary, 'recent_notifications');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        _buildHero(
          firstName:
              ((sharedPreferences.getString('name_user') ?? 'No name'.tr)
                      .trim())
                  .split(RegExp(r'\s+'))
                  .first,
          badge: _heroBadge('beneficiary'),
          body: _heroBody('beneficiary'),
          primaryAction: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onLongPress: () {
                Get.to(() => const FirebaseScreenAdd());
              },
              borderRadius: BorderRadius.circular(8),
              onTap: () => Get.to(() => const BeneficiarySubmitProjectScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Submit request'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          secondaryAction: _WatchNowButton(
            label: 'My history',
            onTap: () => Get.to(() => const RoleHistoryScreen()),
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
                onTap: () =>
                    Get.to(() => const BeneficiaryPendingProjectsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _FeaturedCampaignsSection(),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'approved_cases')}',
                subtitle: 'Approved cases',
                icon: Icons.verified_rounded,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'needs_changes_cases')}',
                subtitle: 'Needs changes',
                icon: Icons.edit_note_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'approved_requests')}',
                subtitle: 'Approved requests',
                icon: Icons.volunteer_activism_rounded,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'open_support_tickets')}',
                subtitle: 'Open support tickets',
                icon: Icons.support_agent_rounded,
                color: Colors.indigo,
              ),
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
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Submit',
                  color: Colors.orange,
                  onTap: () =>
                      Get.to(() => const BeneficiarySubmitProjectScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.folder_open_rounded,
                  label: 'My requests',
                  color: Colors.blueAccent,
                  onTap: () =>
                      Get.to(() => const BeneficiaryMyProjectsScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'Pending',
                  color: Colors.teal,
                  onTap: () =>
                      Get.to(() => const BeneficiaryPendingProjectsScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _ExploreRow(),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Recent case updates'),
        const SizedBox(height: 12),
        if (recentCases.isEmpty)
          const _GlassPanel(child: Text('No beneficiary cases yet.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentCases.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.assignment_rounded,
                    color: Colors.indigo,
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
          const _GlassPanel(child: Text('No submitted requests yet.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentRequests.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.flag_rounded,
                    color: Colors.teal,
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
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Latest alerts'),
        const SizedBox(height: 12),
        if (recentNotifications.isEmpty)
          const _GlassPanel(child: Text('No recent alerts.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentNotifications.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.notifications_active_rounded,
                    color: Colors.amber,
                    title: (recentNotifications[i]['title'] ?? 'Notification')
                        .toString(),
                    subtitle: (recentNotifications[i]['body'] ?? '').toString(),
                    time: _dateLabel(recentNotifications[i]['created_at']),
                    onTap: () => Get.toNamed(AppRoutes.notifications),
                  ),
                  if (i != recentNotifications.length - 1)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
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
    final recentNotifications = _listValue(summary, 'recent_notifications');
    final applicationStatus = (stats['application_status'] ?? '').toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        _buildHero(
          firstName:
              ((sharedPreferences.getString('name_user') ?? 'No name'.tr)
                      .trim())
                  .split(RegExp(r'\s+'))
                  .first,
          badge: _heroBadge('volunteer'),
          body: _heroBody('volunteer'),
          primaryAction: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => dashboardTabNotifier.value = 7,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Open missions'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          secondaryAction: _WatchNowButton(
            label: 'My history',
            onTap: () => Get.to(() => const RoleHistoryScreen()),
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
                onTap: () => dashboardTabNotifier.value = 7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _FeaturedCampaignsSection(),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'available_missions')}',
                subtitle: 'Available missions',
                icon: Icons.assignment_turned_in_rounded,
                color: Colors.cyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: '${_intValue(stats, 'completed_missions')}',
                subtitle: 'Completed missions',
                icon: Icons.workspace_premium_rounded,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: applicationStatus.isEmpty
                    ? 'None'
                    : applicationStatus.replaceAll('_', ' '),
                subtitle: 'Application status',
                icon: Icons.person_add_alt_1_rounded,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: (application['city'] ?? '—').toString(),
                subtitle: 'Application city',
                icon: Icons.location_city_rounded,
                color: Colors.indigo,
              ),
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
                  color: Colors.orange,
                  onTap: () => dashboardTabNotifier.value = 7,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.badge_rounded,
                  label: 'Apply',
                  color: Colors.blueAccent,
                  onTap: () =>
                      Get.to(() => const VolunteerApplicationFormScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.notifications_active_rounded,
                  label: 'History',
                  color: Colors.teal,
                  onTap: () => Get.to(() => const RoleHistoryScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _ExploreRow(),
        const SizedBox(height: 22),
        const _SectionLabel(title: 'My mission schedule'),
        const SizedBox(height: 12),
        if (upcomingMissions.isEmpty)
          const _GlassPanel(child: Text('No missions joined yet.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < upcomingMissions.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.task_alt_rounded,
                    color: Colors.cyan,
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
        const SizedBox(height: 22),
        const _SectionLabel(title: 'Latest alerts'),
        const SizedBox(height: 12),
        if (recentNotifications.isEmpty)
          const _GlassPanel(child: Text('No recent alerts.'))
        else
          _GlassPanel(
            child: Column(
              children: [
                for (var i = 0; i < recentNotifications.length; i++) ...[
                  _DashboardActivityTile(
                    icon: Icons.notifications_active_rounded,
                    color: Colors.amber,
                    title: (recentNotifications[i]['title'] ?? 'Notification')
                        .toString(),
                    subtitle: (recentNotifications[i]['body'] ?? '').toString(),
                    time: _dateLabel(recentNotifications[i]['created_at']),
                    onTap: () => Get.toNamed(AppRoutes.notifications),
                  ),
                  if (i != recentNotifications.length - 1)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
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
      return _SectionScaffold(
        title: roleKey == 'donor'
            ? 'Contributor dashboard'
            : roleKey == 'beneficiary'
            ? 'Recipient dashboard'
            : roleKey == 'volunteer'
            ? 'Volunteer dashboard'
            : 'Dashboard',
        subtitle: _roleSubtitle(roleKey),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderIconButton(
              tooltip: 'Notifications'.tr,
              icon: Icons.notifications_none_rounded,
              onPressed: () => Get.toNamed(AppRoutes.notifications),
            ),
            const SizedBox(width: 8),
            _buildRefreshButton(controller),
          ],
        ),
        child: Builder(
          builder: (context) {
            if (controller.isLoading.value && controller.summary.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (controller.errorMessage.value != null &&
                controller.summary.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.errorMessage.value!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: controller.fetchSummary,
                        child: Text('Retry'.tr),
                      ),
                    ],
                  ),
                ),
              );
            }
            final summary = Map<String, dynamic>.from(controller.summary);
            return switch (roleKey) {
              'beneficiary' => _buildBeneficiaryDashboard(context, summary),
              'volunteer' => _buildVolunteerDashboard(context, summary),
              _ => _buildDonorDashboard(context, summary, campaignsController),
            };
          },
        ),
      );
    });
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
            Text(
              'See all'.tr,
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Obx(() {
          if (campaignsController.isLoading.value) {
            return const SizedBox(
              height: 340,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (campaignsController.errorMessage.value != null) {
            return SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  campaignsController.errorMessage.value!,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (campaignsController.campaigns.isEmpty) {
            return const _GlassPanel(child: Text('No campaigns available.'));
          }
          return SizedBox(
            height: 340,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: campaignsController.campaigns
                  .map((campaign) => _CampaignCard(campaign: campaign))
                  .toList(),
            ),
          );
        }),
      ],
    );
  }
}

class _SectionScaffold extends StatelessWidget {
  const _SectionScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppThemeConfig.backgroundTop(context),
              AppThemeConfig.backgroundBottom(context),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.tr,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppThemeConfig.text(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle.tr,
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeConfig.surface(context),
            AppThemeConfig.elevatedSurface(context),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.shadow(context),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: AppThemeConfig.text(context), size: 22),
          ),
        ),
      ),
    );
  }
}

class _WatchNowButton extends StatelessWidget {
  const _WatchNowButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14B8A6).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
          elevation: 2,
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
        label: Text(label.tr),
      ),
    );
  }
}

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
        gradient: LinearGradient(
          colors: [
            AppThemeConfig.surface(context),
            AppThemeConfig.elevatedSurface(context),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
            ),
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
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconShell(icon: icon, color: color, size: 56, iconSize: 25),
              const Spacer(),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppThemeConfig.softSurface(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_outward_rounded,
                  size: 18,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title.tr,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle.tr,
            style: TextStyle(color: AppThemeConfig.mutedText(context)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label.tr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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

/// Home "Explore" panel — non-role-specific shortcuts that live on Home rather
/// than inside the Community/Services tabs (e.g. the City Guide map).
class _ExploreRow extends StatelessWidget {
  const _ExploreRow();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(title: 'Explore'),
        const SizedBox(height: 12),
        _GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.map_rounded,
                  label: 'City Guide',
                  color: Colors.teal,
                  onTap: () => Get.to(() => const CityGuideScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.smart_toy_rounded,
                  label: 'Assistant',
                  color: Colors.deepPurple,
                  onTap: () => Get.to(() => const BotChatScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            decoration: BoxDecoration(
              color: AppThemeConfig.softSurface(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.24),
                        color.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.14)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Icon(icon, color: color, size: 28),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
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
    final accent = campaign.color;

    return Container(
      width: 244,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeConfig.elevatedSurface(context),
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
          onTap: () => Get.to(() => CampaignDetailScreen(campaign: campaign)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Header: icon + category chip ----
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
                        fontSize: 26,
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
                    const Spacer(),
                    if (campaign.fundingAmountsLine.isNotEmpty)
                      Flexible(
                        child: Text(
                          campaign.fundingAmountsLine,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppThemeConfig.mutedText(context),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // ---- Thick gradient progress bar ----
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 10,
                    color: accent.withValues(alpha: 0.14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: campaign.fundedProgress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accent.withValues(alpha: 0.7), accent],
                            ),
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
                    Icon(Icons.arrow_forward_rounded, size: 16, color: accent),
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
                    style: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 208,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _NewsCard(post: items[i]),
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
    final type = (post['post_type'] ?? 'news').toString();
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.article_rounded,
                            color: Colors.white,
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
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.article_rounded,
                              color: Colors.white,
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
                            color: const Color(
                              0xFF0F766E,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            type.tr,
                            style: const TextStyle(
                              color: Color(0xFF0F766E),
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
                    style: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: controller.partners.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) =>
                  _PartnerLogoCard(partner: controller.partners[i]),
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
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F766E),
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
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F766E),
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
        Text(
          time.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            fontWeight: FontWeight.w600,
          ),
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
