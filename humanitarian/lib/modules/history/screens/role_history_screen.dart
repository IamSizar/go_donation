import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/history/controllers/role_history_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

final NumberFormat _historyNumberFormat = NumberFormat.decimalPattern();

class RoleHistoryScreen extends StatefulWidget {
  const RoleHistoryScreen({super.key});

  @override
  State<RoleHistoryScreen> createState() => _RoleHistoryScreenState();
}

class _RoleHistoryScreenState extends State<RoleHistoryScreen> {
  late final RoleHistoryController _controller;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<RoleHistoryController>()) {
      Get.delete<RoleHistoryController>();
    }
    _controller = Get.put(RoleHistoryController());
  }

  @override
  void dispose() {
    if (Get.isRegistered<RoleHistoryController>()) {
      Get.delete<RoleHistoryController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'My history',
      subtitle:
          'Follow your role-specific records with quick filters and clear details.',
      trailing: IconButton.filledTonal(
        onPressed: _controller.fetchHistory,
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh'.tr,
      ),
      child: Obx(() {
        final filtered = _controller.filteredItems;
        return RefreshIndicator(
          onRefresh: _controller.fetchHistory,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 44),
            children: [
              _HistoryHero(controller: _controller),
              const SizedBox(height: 18),
              if (_controller.errorMessage.value != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SectionTile(
                    icon: Icons.error_outline_rounded,
                    title: _controller.title,
                    subtitle: _controller.errorMessage.value!,
                    color: Colors.orange,
                    onTap: _controller.fetchHistory,
                  ),
                ),
              _FilterSection(controller: _controller),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    _controller.title.tr,
                    style: TextStyle(
                      color: AppThemeConfig.text(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} ${'records'.tr}',
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_controller.isLoading.value && _controller.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                const GlassPanel(
                  child: Text('No history records match the selected filters.'),
                )
              else
                ...filtered.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _HistoryCard(
                      item: item,
                      onTap: () => _showDetails(context, item),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final details = Map<String, dynamic>.from(item['details'] as Map? ?? {});
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GlassPanel(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (item['title'] ?? 'Record').toString(),
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _StatusBadge(status: (item['status'] ?? '').toString()),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (item['subtitle'] ?? '').toString(),
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...details.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 122,
                              child: Text(
                                entry.key.tr,
                                style: TextStyle(
                                  color: AppThemeConfig.mutedText(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                (entry.value ?? '—').toString(),
                                style: TextStyle(
                                  color: AppThemeConfig.text(context),
                                  fontWeight: FontWeight.w700,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryHero extends StatelessWidget {
  const _HistoryHero({required this.controller});

  final RoleHistoryController controller;

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(controller.summary);
    final stats = switch (controller.role.value) {
      'donor' => [
        _HeroMetric(
          label: 'Total given',
          value:
              '${_historyNumberFormat.format(_historyNum(summary['donation_total']).round())} IQD',
        ),
        _HeroMetric(
          label: 'Successful donations',
          value: '${_historyInt(summary['successful_donations'])}',
        ),
        _HeroMetric(
          label: 'Pending payments',
          value: '${_historyInt(summary['pending_payments'])}',
        ),
        _HeroMetric(
          label: 'Active sponsorships',
          value: '${_historyInt(summary['active_sponsorships'])}',
        ),
      ],
      'volunteer' => [
        _HeroMetric(
          label: 'Mission records',
          value: '${_historyNestedCount(summary, 'kind_counts', 'mission')}',
        ),
        _HeroMetric(
          label: 'Completed',
          value: '${_historyInt(summary['completed_missions'])}',
        ),
        _HeroMetric(
          label: 'Hours served',
          value:
              '${_historyNumberFormat.format(_historyNum(summary['hours_served']).round())}h',
        ),
        _HeroMetric(
          label: 'Application',
          value: _prettyLabel(
            (summary['application_status'] ?? '—').toString(),
          ),
        ),
      ],
      _ => [
        _HeroMetric(
          label: 'Cases',
          value: '${_historyNestedCount(summary, 'kind_counts', 'case')}',
        ),
        _HeroMetric(
          label: 'Requests',
          value: '${_historyNestedCount(summary, 'kind_counts', 'request')}',
        ),
        _HeroMetric(
          label: 'Approved',
          value: '${_historyInt(summary['approved_items'])}',
        ),
        _HeroMetric(
          label: 'Pending',
          value: '${_historyInt(summary['pending_items'])}',
        ),
      ],
    };

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB), Color(0xFF0EA5A4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              controller.title.tr,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            controller.subtitle.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: stats),
        ],
      ),
    );
  }
}

num _historyNum(dynamic value) {
  if (value is num) {
    return value;
  }
  return num.tryParse((value ?? '').toString()) ?? 0;
}

int _historyInt(dynamic value) => _historyNum(value).round();

int _historyNestedCount(
  Map<String, dynamic> summary,
  String parentKey,
  String childKey,
) {
  final parent = summary[parentKey];
  if (parent is Map) {
    return _historyInt(parent[childKey]);
  }
  return 0;
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.controller});

  final RoleHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filters'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _ChoiceChips(
            title: 'Type',
            currentValue: controller.selectedKind.value,
            values: controller.kindOptions,
            onSelected: controller.setKind,
          ),
          const SizedBox(height: 12),
          _ChoiceChips(
            title: 'Status',
            currentValue: controller.selectedStatus.value,
            values: controller.statusOptions,
            onSelected: controller.setStatus,
          ),
          const SizedBox(height: 12),
          _ChoiceChips(
            title: 'Date',
            currentValue: controller.selectedDateRange.value,
            values: const ['all', '30d', '90d'],
            onSelected: controller.setDateRange,
          ),
        ],
      ),
    );
  }
}

class _ChoiceChips extends StatelessWidget {
  const _ChoiceChips({
    required this.title,
    required this.currentValue,
    required this.values,
    required this.onSelected,
  });

  final String title;
  final String currentValue;
  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => ChoiceChip(
                  label: Text(_filterLabel(value).tr),
                  selected: currentValue == value,
                  onSelected: (_) => onSelected(value),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = item['amount'];
    final currency = (item['currency'] ?? 'IQD').toString();
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TileIcon(
                  icon: _iconForKind((item['kind'] ?? '').toString()),
                  color: _colorForStatus((item['status'] ?? '').toString()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['title'] ?? 'Record').toString(),
                        style: TextStyle(
                          color: AppThemeConfig.text(context),
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        (item['subtitle'] ?? '').toString(),
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: (item['status'] ?? '').toString()),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(
                  icon: Icons.category_rounded,
                  label: _prettyLabel((item['kind'] ?? 'record').toString()),
                ),
                if (amount != null)
                  InfoChip(
                    icon: Icons.payments_rounded,
                    label:
                        '${_historyNumberFormat.format((amount as num).round())} $currency',
                  ),
                InfoChip(
                  icon: Icons.schedule_rounded,
                  label: _dateLabel((item['date_label'] ?? '').toString()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _colorForStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        _prettyLabel(status).tr,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _filterLabel(String value) {
  return switch (value) {
    'all' => 'All',
    '30d' => 'Last 30 days',
    '90d' => 'Last 90 days',
    _ => _prettyLabel(value),
  };
}

String _prettyLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Unknown';
  return trimmed
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _dateLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '—';
  final parsed =
      DateTime.tryParse(trimmed.replaceFirst(' ', 'T')) ??
      DateTime.tryParse(trimmed);
  if (parsed == null) return trimmed;
  return DateFormat('dd MMM yyyy').format(parsed);
}

IconData _iconForKind(String kind) {
  return switch (kind) {
    'donation' => Icons.volunteer_activism_rounded,
    'sponsorship' => Icons.favorite_rounded,
    'application' => Icons.badge_rounded,
    'mission' => Icons.task_alt_rounded,
    'case' => Icons.assignment_rounded,
    'request' => Icons.flag_rounded,
    'support' => Icons.support_agent_rounded,
    _ => Icons.history_rounded,
  };
}

Color _colorForStatus(String status) {
  if ([
    'approved',
    'success',
    'resolved',
    'completed',
    'active',
    'joined',
  ].contains(status)) {
    return Colors.green;
  }
  if ([
    'pending',
    'submitted',
    'under_review',
    'in_progress',
    'open',
  ].contains(status)) {
    return Colors.orange;
  }
  if ([
    'rejected',
    'failed',
    'closed',
    'cancelled',
    'inactive',
  ].contains(status)) {
    return Colors.redAccent;
  }
  return Colors.blueGrey;
}
