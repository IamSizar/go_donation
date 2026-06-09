import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_projects_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class BeneficiaryMyProjectsScreen extends StatelessWidget {
  const BeneficiaryMyProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<BeneficiaryProjectsController>()
        ? Get.find<BeneficiaryProjectsController>()
        : Get.put(BeneficiaryProjectsController());

    return SectionScaffold(
      title: 'My help requests',
      subtitle: 'Track project requests you submitted for admin review.',
      child: Obx(() {
        final items = controller.projects;
        return RefreshIndicator(
          onRefresh: controller.fetchProjects,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              _SummaryBand(items: items),
              const SizedBox(height: 14),
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.refresh_rounded,
                  title: 'My help requests',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.orange,
                  onTap: controller.fetchProjects,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                const SectionTile(
                  icon: Icons.assignment_outlined,
                  title: 'No requests yet',
                  subtitle: 'Submitted project requests will appear here.',
                  color: Colors.indigo,
                ),
              for (final item in items) ...[
                _ProjectRequestCard(item: item),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((item) {
      final status = (item['status'] ?? '').toString();
      return status == 'pending' ||
          status == 'submitted' ||
          status == 'under_review';
    }).length;
    final approved = items
        .where((item) => (item['status'] ?? '').toString() == 'approved')
        .length;

    return GlassPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          InfoChip(
            icon: Icons.assignment_rounded,
            label: '${items.length} total',
          ),
          InfoChip(icon: Icons.schedule_rounded, label: '$pending pending'),
          InfoChip(icon: Icons.verified_rounded, label: '$approved approved'),
        ],
      ),
    );
  }
}

class _ProjectRequestCard extends StatelessWidget {
  const _ProjectRequestCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      item,
      'project_title',
      fallback: 'Request',
    );
    final summary = localizedContentFromMap(item, 'summary');
    final category = localizedContentFromMap(item, 'category');
    final community = localizedContentFromMap(
      item,
      'beneficiary_community_name',
    );
    final status = (item['status'] ?? 'submitted').toString();
    final amount = _money(item['amount_needed'], item['currency']);
    final raised = _money(item['raised_amount'], item['currency']);
    final updatedAt = _dateLabel(item['updated_at'] ?? item['created_at']);
    final color = _statusColor(status);

    return GlassPanel(
      padding: const EdgeInsets.all(16),
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
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    if (community.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
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
              _StatusPill(status: status, color: color),
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
              if (category.trim().isNotEmpty)
                _MetricPill(icon: Icons.category_rounded, label: category),
              _MetricPill(icon: Icons.flag_rounded, label: amount),
              _MetricPill(icon: Icons.savings_rounded, label: '$raised raised'),
              _MetricPill(
                icon: Icons.favorite_rounded,
                label: '${item['like_count'] ?? 0} likes',
              ),
              _MetricPill(
                icon: Icons.mode_comment_rounded,
                label: '${item['comment_count'] ?? 0} comments',
              ),
              if (updatedAt.isNotEmpty)
                _MetricPill(icon: Icons.update_rounded, label: updatedAt),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        status.replaceAll('_', ' ').tr,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
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
