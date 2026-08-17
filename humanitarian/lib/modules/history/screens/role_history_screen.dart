import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/history/controllers/role_history_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
// `intl` exports a TextDirection of its own (an LTR/RTL constant class) which
// shadows the dart:ui enum Flutter's Text widget takes, so an unhidden import
// makes `TextDirection.ltr` fail to resolve. Only DateFormat/NumberFormat are
// wanted from here.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter_application_1/core/widgets/app_list_search_field.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

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
            // K21 put a text field on this list, so scrolling the results must
            // put the keyboard away — the same behaviour every other screen
            // carrying AppListSearchField sets.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _HistoryHero(controller: _controller),
              const SizedBox(height: 18),
              // K21 — look a history up by identity code. Above the filters
              // because it chooses WHOSE timeline is shown, where the filters
              // only narrow whichever one that is.
              _IdentityCodeLookup(controller: _controller),
              const SizedBox(height: 18),
              // The filters and the count row stay OUTSIDE AppAsync. The
              // empty state here is almost always "nothing matches the
              // filters you chose", so hiding the filters with the results
              // would remove the only way out of it.
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
              // The error used to render as a SectionTile ABOVE the filters
              // while the list below carried on showing its own empty state,
              // so a failed load produced two competing messages. It is one
              // state now, and AppAsync keeps already-loaded records visible
              // behind it rather than wiping the screen for an offline user.
              AppAsync<List<Map<String, dynamic>>>(
                loading: _controller.isLoading.value,
                error: _controller.errorMessage.value,
                onRetry: _controller.fetchHistory,
                data: filtered,
                isEmpty: (list) => list.isEmpty,
                empty: AppEmpty(
                  title: _controller.title.tr,
                  message: 'No history records match the selected filters.'.tr,
                ),
                builder: (list) => Column(
                  children: [
                    for (final item in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _HistoryCard(
                          item: item,
                          onTap: () => _showDetails(context, item),
                        ),
                      ),
                  ],
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
          // No unit suffix on the value. The tile's own label already says
          // which unit this is — «ساعات الخدمة» in Arabic — so the "h" that
          // used to be glued to the number added nothing except a Latin
          // letter standing among Arabic labels on سجلي. Every sibling metric
          // here already prints a bare number for the same reason; only the
          // donor's total carries a suffix, and that one is a currency code
          // its label does not name.
          label: 'Hours served',
          value: _historyNumberFormat.format(
            _historyNum(summary['hours_served']).round(),
          ),
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
        color: AppThemeConfig.accent(context),
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
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              controller.title.tr,
              style: TextStyle(
                color: AppThemeConfig.onAccent(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // K21 — WHOSE history this is, whenever it is not simply "mine".
          //
          // The screen's headings say "My history" and "Review YOUR recent
          // activity", which stops being true the moment a code names somebody
          // else — and staff carrying (users, view) can do exactly that. The
          // endpoint deliberately returns no name (it answers "the timeline for
          // this code" and nothing that would identify the holder), so the code
          // itself is the honest label.
          if (controller.identityCode.value.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 15,
                  color: AppThemeConfig.onAccent(context),
                ),
                const SizedBox(width: 6),
                Text(
                  '${'reg_volunteer_code'.tr}:',
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(
                      context,
                    ).withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  controller.identityCode.value,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            controller.subtitle.tr,
            style: TextStyle(
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.92),
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
        color: AppThemeConfig.onAccent(context).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppThemeConfig.onAccent(context),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// K21 — "استعلام بالكود التعريفي لاستعراض سجل (التبرعات وحالة الدعم)".
///
/// WHAT THIS CAN AND CANNOT DO, SAID OUT LOUD
/// The server allows a code lookup for the OWNER of the code and for staff
/// carrying the (users, view) permission, and answers everybody else with a 404
/// that is byte-identical to the one for a code nobody holds — because the codes
/// are sequential, so an answer that told the two apart would be a way to
/// enumerate real people.
///
/// A box that silently refuses most of what is typed into it would read as
/// broken, so the caption says the rule instead of leaving the user to infer it
/// from a refusal. That is the guidance rule (5.9) doing the work a tooltip
/// would: the control is honest about its own scope before it is used.
///
/// The input is the app's existing list-search field, which already carries the
/// debounce, the clear button, the keyboard type and the dismissal behaviour —
/// clearing it is also the way back to your own history.
class _IdentityCodeLookup extends StatelessWidget {
  const _IdentityCodeLookup({required this.controller});

  final RoleHistoryController controller;

  @override
  Widget build(BuildContext context) {
    final ownCode = controller.ownIdentityCode;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'history_code_title'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'history_code_help'.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.45,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          AppListSearchField(
            // 'Identification code' — already in all four locales, and the
            // words this field is asking for. A new key would be a synonym.
            hintKey: 'reg_volunteer_code',
            onChanged: controller.lookUpIdentityCode,
          ),
          if (ownCode.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Shown so the user has their own code to hand while typing in this
            // very box — the one lookup every account is allowed to make.
            // Absent entirely for an account with no code, rather than a label
            // with a blank after it.
            Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 15,
                  color: AppThemeConfig.mutedText(context),
                ),
                const SizedBox(width: 6),
                Text(
                  '${'reg_volunteer_code'.tr}:',
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ownCode,
                  // A machine value: it keeps its own direction on an Arabic
                  // screen so it can be read back character by character.
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
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
                  color: _colorForStatus(
                    context,
                    (item['status'] ?? '').toString(),
                  ),
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
    final color = _colorForStatus(context, status);
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

Color _colorForStatus(BuildContext context, String status) {
  if ([
    'approved',
    'success',
    'resolved',
    'completed',
    'active',
    'joined',
  ].contains(status)) {
    return AppThemeConfig.accent(context);
  }
  if ([
    'pending',
    'submitted',
    'under_review',
    'in_progress',
    'open',
  ].contains(status)) {
    return AppThemeConfig.pending(context);
  }
  if ([
    'rejected',
    'failed',
    'closed',
    'cancelled',
    'inactive',
  ].contains(status)) {
    return AppThemeConfig.consequence(context);
  }
  return AppThemeConfig.subtleText(context);
}
