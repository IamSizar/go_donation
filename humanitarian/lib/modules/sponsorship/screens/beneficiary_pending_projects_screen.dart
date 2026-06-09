import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_projects_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class BeneficiaryPendingProjectsScreen extends StatelessWidget {
  const BeneficiaryPendingProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<BeneficiaryProjectsController>()
        ? Get.find<BeneficiaryProjectsController>()
        : Get.put(BeneficiaryProjectsController());

    return SectionScaffold(
      title: 'Pending projects for help',
      subtitle: 'Requests awaiting review, changes, or sponsor matching.',
      child: Obx(() {
        final pendingItems = controller.projects.where(_isPending).toList();
        return RefreshIndicator(
          onRefresh: controller.fetchProjects,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              _PendingIntroCard(total: pendingItems.length),
              const SizedBox(height: 22),
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.refresh_rounded,
                  title: 'Pending projects for help',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.orange,
                  onTap: controller.fetchProjects,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  pendingItems.isEmpty)
                const SectionTile(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'No pending projects',
                  subtitle:
                      'Submitted project requests that need review or matching will appear here.',
                  color: Colors.indigo,
                ),
              for (final item in pendingItems) ...[
                _PendingProjectCard(item: item),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _PendingIntroCard extends StatelessWidget {
  const _PendingIntroCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              InfoChip(
                icon: Icons.hourglass_top_rounded,
                label: '$total pending',
              ),
              const InfoChip(
                icon: Icons.volunteer_activism_rounded,
                label: 'Needs sponsor',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Beneficiary pending projects'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Track requests that are still waiting for admin review, requested changes, approval, or sponsor matching.'
                .tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingProjectCard extends StatelessWidget {
  const _PendingProjectCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      item,
      'project_title',
      fallback: 'Project request',
    );
    final community = localizedContentFromMap(
      item,
      'beneficiary_community_name',
    );
    final summary = localizedContentFromMap(item, 'summary');
    final category = localizedContentFromMap(item, 'category');
    final amount = _money(item['amount_needed'], item['currency']);
    final status = (item['status'] ?? 'submitted').toString();
    final submitted = _dateLabel(item['created_at']);
    final color = _statusColor(status);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileIcon(icon: _categoryIcon(category), color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (community.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        community,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summary.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(
                icon: Icons.pending_actions_rounded,
                label: status.replaceAll('_', ' '),
              ),
              if (category.trim().isNotEmpty)
                _MetricPill(icon: Icons.category_rounded, label: category),
              _MetricPill(icon: Icons.flag_rounded, label: amount),
              if (submitted.isNotEmpty)
                _MetricPill(icon: Icons.event_rounded, label: submitted),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppThemeConfig.primary),
          const SizedBox(width: 7),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isPending(Map<String, dynamic> item) {
  final status = (item['status'] ?? '').toString();
  return status == 'pending' ||
      status == 'submitted' ||
      status == 'under_review';
}

String _money(dynamic value, dynamic currency) {
  final amount = num.tryParse((value ?? '0').toString()) ?? 0;
  final formatted = NumberFormat.decimalPattern().format(amount);
  final code = (currency ?? 'IQD').toString();
  return '$formatted $code';
}

String _dateLabel(dynamic raw) {
  final parsed = DateTime.tryParse((raw ?? '').toString());
  if (parsed == null) return '';
  return DateFormat.yMMMd().format(parsed);
}

Color _statusColor(String status) {
  return switch (status) {
    'approved' => Colors.green,
    'rejected' => Colors.redAccent,
    'under_review' => Colors.orange,
    'pending' || 'submitted' => Colors.amber,
    _ => Colors.indigo,
  };
}

IconData _categoryIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('water')) return Icons.water_drop_rounded;
  if (value.contains('health') || value.contains('medical')) {
    return Icons.local_hospital_rounded;
  }
  if (value.contains('education') || value.contains('school')) {
    return Icons.school_rounded;
  }
  if (value.contains('shelter') || value.contains('housing')) {
    return Icons.home_work_rounded;
  }
  return Icons.assignment_rounded;
}
