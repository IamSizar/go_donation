import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/sponsorships_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

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
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: '12',
                    subtitle: 'Sponsored families',
                    icon: Icons.family_restroom_rounded,
                    color: Colors.teal,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: '96%',
                    subtitle: 'On-time payments',
                    icon: Icons.verified_rounded,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: '4',
                    subtitle: 'Stories this month',
                    icon: Icons.auto_stories_rounded,
                    color: Colors.amber,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: '3',
                    subtitle: 'Renewals due soon',
                    icon: Icons.event_repeat_rounded,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionLabel(title: 'My monthly sponsorships'),
            const SizedBox(height: 12),
            Obx(() {
              if (controller.isLoading.value && controller.items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.errorMessage.value != null &&
                  controller.items.isEmpty) {
                return _OverviewNoticeCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load sponsorships',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.redAccent,
                );
              }
              if (controller.items.isEmpty) {
                return const _OverviewNoticeCard(
                  icon: Icons.handshake_rounded,
                  title: 'No sponsorships yet',
                  subtitle: 'Create one from the Sponsorship page.',
                  color: Colors.pinkAccent,
                );
              }
              return Column(
                children: [
                  if (controller.isCancelling.value)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  ...controller.items.map(
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
              );
            }),
            const SizedBox(height: 22),
            const SectionLabel(title: 'This month'),
            const SizedBox(height: 12),
            const _OverviewTimelineCard(),
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

class _OverviewNoticeCard extends StatelessWidget {
  const _OverviewNoticeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: _OverviewLine(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
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
              const TileIcon(
                icon: Icons.handshake_rounded,
                color: Colors.pinkAccent,
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
                      '$amount $currency monthly'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              InfoChip(icon: Icons.info_rounded, label: status),
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
              alignment: Alignment.centerRight,
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
  if (days == 0) return 'Next due today';
  if (days > 0) {
    return 'Next due in $days ${days == 1 ? 'day' : 'days'}';
  }
  final overdue = days.abs();
  return 'Overdue by $overdue ${overdue == 1 ? 'day' : 'days'}';
}

class _OverviewHeroCard extends StatelessWidget {
  const _OverviewHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF14B8A6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.22),
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
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
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

class _OverviewTimelineCard extends StatelessWidget {
  const _OverviewTimelineCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _OverviewLine(
            icon: Icons.payments_rounded,
            color: Colors.teal,
            title: 'Payment batch completed',
            subtitle:
                '9 recurring sponsorships were processed successfully this week.',
          ),
          SizedBox(height: 16),
          _OverviewLine(
            icon: Icons.mark_chat_read_rounded,
            color: Colors.amber,
            title: 'New family stories available',
            subtitle:
                'Three sponsored families shared recent progress and gratitude notes.',
          ),
          SizedBox(height: 16),
          _OverviewLine(
            icon: Icons.notifications_active_rounded,
            color: Colors.blueAccent,
            title: 'Renewals approaching',
            subtitle:
                'Two sponsorship plans need confirmation before the next billing cycle.',
          ),
        ],
      ),
    );
  }
}

class _OverviewLine extends StatelessWidget {
  const _OverviewLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TileIcon(icon: icon, color: color),
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
                ),
              ),
              const SizedBox(height: 6),
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
      ],
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
