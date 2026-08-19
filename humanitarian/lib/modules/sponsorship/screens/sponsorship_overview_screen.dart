import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/sponsorships_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_schedule_screen.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

class SponsorshipOverviewScreen extends StatelessWidget {
  const SponsorshipOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<SponsorshipsController>()
        ? Get.find<SponsorshipsController>()
        : Get.put(SponsorshipsController());

    return SectionScaffold(
      title: 'Overview',
      subtitle: 'Review current sponsorship activity and milestones.',
      child: RefreshIndicator(
        onRefresh: controller.fetchSponsorships,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const _OverviewHeroCard(),
            SizedBox(height: 12),
            // "Eighth: Sponsorship Schedule and Calendar" — entitlement
            // tracking: every due date, split into upcoming / due / overdue
            // / history.
            GlassPanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  Icons.calendar_month_rounded,
                  color: AppThemeConfig.accent(context),
                ),
                title: Text(
                  'sched_title'.tr,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('sched_subtitle'.tr),
                trailing: Icon(AppIcons.chevronForward(context)),
                onTap: () => Get.to(() => SponsorshipScheduleScreen()),
              ),
            ),
            SizedBox(height: 18),
            SectionLabel(title: 'My monthly sponsorships'),
            SizedBox(height: 12),
            Obx(() {
              // AppAsync renders exactly ONE of loading / content / error /
              // empty. The error branch here used a _OverviewNoticeCard with
              // no retry at all, so a failed load was a dead end - the only
              // way to try again was to leave the screen and come back.
              return AppAsync<List<dynamic>>(
                loading: controller.isLoading.value,
                error: controller.errorMessage.value,
                onRetry: controller.fetchSponsorships,
                data: controller.items,
                isEmpty: (list) => list.isEmpty,
                empty: const AppEmpty(
                  title: 'No sponsorships yet',
                  message: 'Create one from the Support page.',
                ),
                builder: (list) => Column(
                  children: [
                    // A cancel in flight is genuine determinate-ish progress
                    // on EXISTING content, not a load - so it stays inside the
                    // content state rather than replacing it.
                    if (controller.isCancelling.value)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),
                    ...list.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SponsorshipPlanCard(
                          item: item,
                          onCancel: () async {
                            final id = int.tryParse('${item['id']}') ?? 0;
                            final ok = await controller.cancelSponsorship(id);
                            if (ok) {
                              Get.snackbar(
                                'Cancelled'.tr,
                                'Sponsorship cancelled.'.tr,
                              );
                            } else if (controller.errorMessage.value != null) {
                              Get.snackbar(
                                'Error'.tr,
                                controller.errorMessage.value!,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 22),
            const SectionLabel(title: 'Focus areas'),
            const SizedBox(height: 12),
            const _OverviewFocusCard(),
          ],
        ),
      ),
    );
  }
}

class _SponsorshipPlanCard extends StatelessWidget {
  const _SponsorshipPlanCard({required this.item, required this.onCancel});

  final Map<String, dynamic> item;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final title = (item['project_title'] ?? 'General support').toString();
    final status = (item['status'] ?? 'pending').toString();
    final amount = (item['amount'] ?? '0').toString();
    final currency = (item['currency'] ?? 'IQD').toString();
    final dueDate = (item['next_due_date'] ?? '').toString();
    final dueLabel = _sponsorshipDueLabel(dueDate);
    final canCancel = [
      'pending',
      'active',
      'paused',
      'delayed',
    ].contains(status.toLowerCase());

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileIcon(
                icon: Icons.handshake_rounded,
                color: AppThemeConfig.accent(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '@amount @currency monthly'.trParams({
                        'amount': amount,
                        'currency': currency,
                      }),
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              InfoChip(
                icon: Icons.info_rounded,
                label: 'sponsorship_status_$status',
              ),
            ],
          ),
          if (dueLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              dueLabel.tr,
              style: TextStyle(color: AppThemeConfig.mutedText(context)),
            ),
          ],
          if (canCancel) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined),
                label: Text('Cancel sponsorship'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _sponsorshipDueLabel(String rawDate) {
  final due = DateTime.tryParse(rawDate.trim());
  if (due == null) return '';
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final dueOnly = DateTime(due.year, due.month, due.day);
  final days = dueOnly.difference(todayOnly).inDays;
  if (days == 0) return 'sponsorship_due_today'.tr;
  if (days > 0) {
    return (days == 1 ? 'sponsorship_due_in_day' : 'sponsorship_due_in_days')
        .trParams({'n': '$days'});
  }
  final overdue = days.abs();
  return (overdue == 1
          ? 'sponsorship_overdue_by_day'
          : 'sponsorship_overdue_by_days')
      .trParams({'n': '$overdue'});
}

class _OverviewHeroCard extends StatelessWidget {
  const _OverviewHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.accent(context).withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoChip(icon: Icons.favorite_rounded, label: 'Kafala impact'),
          const SizedBox(height: 18),
          Text(
            'Your sponsorships are active and creating steady support for families who rely on consistent monthly care.'
                .tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppThemeConfig.onAccent(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Track progress, payment continuity, and story updates in one place so you always know how support is being delivered.'
                .tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewFocusCard extends StatelessWidget {
  const _OverviewFocusCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              InfoChip(icon: Icons.school_rounded, label: 'Education needs'),
              InfoChip(
                icon: Icons.local_hospital_rounded,
                label: 'Health support',
              ),
              InfoChip(
                icon: Icons.home_work_rounded,
                label: 'Family stability',
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'The overview highlights where sponsorship attention is needed most, helping donors balance continuity, urgent needs, and long-term family support.'
                .tr,
          ),
        ],
      ),
    );
  }
}
