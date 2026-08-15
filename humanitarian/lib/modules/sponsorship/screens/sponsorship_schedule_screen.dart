import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// "Eighth: Sponsorship Schedule and Calendar" — requirement 3, entitlement
/// tracking. One row per due date, filtered into the four views the spec
/// asks for: upcoming contributions/grants, assistance currently due,
/// overdue assistance, and previous history.
///
/// Complements BeneficiaryEntitlementsScreen (#21), which lists the
/// sponsorships themselves; this lists their individual dates.
class SponsorshipScheduleScreen extends StatefulWidget {
  const SponsorshipScheduleScreen({super.key});

  @override
  State<SponsorshipScheduleScreen> createState() =>
      _SponsorshipScheduleScreenState();
}

class _SponsorshipScheduleScreenState extends State<SponsorshipScheduleScreen> {
  /// Filter key -> the API `status` value it requests. History asks for
  /// 'paid' — the settled record the spec calls "previous assistance".
  static const _filters = <({String key, String labelKey, String status})>[
    (key: 'upcoming', labelKey: 'sched_upcoming', status: 'upcoming'),
    (key: 'due', labelKey: 'sched_due', status: 'due'),
    (key: 'overdue', labelKey: 'sched_overdue', status: 'overdue'),
    (key: 'history', labelKey: 'sched_history', status: 'paid'),
  ];

  String _selected = 'upcoming';

  /// True only while there is nothing to show yet: the first load and each
  /// filter switch, which discards the previous filter's rows. A
  /// pull-to-refresh passes `silent: true` and keeps the current rows on
  /// screen rather than flashing a skeleton over them.
  bool _loading = true;

  /// User-facing failure message, or null when the last load succeeded.
  String? _error;

  /// Null while a fresh set of rows is still in flight — AppAsync shows its
  /// skeleton only when the data is null, which is what distinguishes
  /// "not loaded yet" from "loaded and genuinely empty".
  List<ScheduleOccurrence>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      // Cleared here so a successful retry does not leave the previous
      // failure's banner on screen.
      _error = null;
      if (!silent) {
        _loading = true;
        _items = null;
      }
    });
    final status = _filters.firstWhere((f) => f.key == _selected).status;
    try {
      final items = await const ModuleApi().getSponsorshipSchedule(
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      // There was no catch here and no error field, so a failed fetch left
      // `_items` empty and rendered the filter's empty copy — telling a
      // beneficiary they had no assistance due, or no history, when the
      // request had merely failed. No retry was offered either.
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your sponsorship schedule.';
        _loading = false;
      });
      debugPrint('getSponsorshipSchedule($status) failed: $e');
    }
  }

  void _select(String key) {
    if (key == _selected) return;
    setState(() => _selected = key);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'sched_title'.tr,
      subtitle: 'sched_subtitle'.tr,
      child: Column(
        children: [
          // Filter row. Horizontally scrollable so the four chips never
          // overflow on a narrow screen or with longer translations.
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _filters[i];
                final active = f.key == _selected;
                return Material(
                  color: active
                      ? AppThemeConfig.primary
                      : AppThemeConfig.surface(context),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _select(f.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        f.labelKey.tr,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: active
                              ? Colors.white
                              : AppThemeConfig.text(context),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppAsync<List<ScheduleOccurrence>>(
              loading: _loading,
              error: _error,
              onRetry: _load,
              data: _items,
              isEmpty: (items) => items.isEmpty,
              // Padded to the list's own gutters so the bones land where the
              // occurrence cards will.
              skeleton: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: AppSkeleton.rows(count: 4, withProgress: false),
              ),
              // The existing per-filter empty copy is kept as-is: "no
              // upcoming contributions" and "no overdue assistance" are
              // different messages and both are correct empty states.
              empty: _EmptyState(filterKey: _selected),
              builder: (items) => RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _OccurrenceCard(item: items[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filterKey});

  final String filterKey;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: [
        Icon(
          Icons.event_available_outlined,
          size: 48,
          color: AppThemeConfig.mutedText(context),
        ),
        const SizedBox(height: 12),
        Text(
          'sched_empty_$filterKey'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppThemeConfig.mutedText(context),
          ),
        ),
      ],
    );
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({required this.item});

  final ScheduleOccurrence item;

  /// Status colour: overdue reads as a problem, due as action-needed, paid as
  /// settled, upcoming as neutral.
  Color _statusColor() {
    switch (item.status) {
      case 'overdue':
        return const Color(0xFFEF4444);
      case 'due':
        return const Color(0xFFF59E0B);
      case 'paid':
        return const Color(0xFF16A34A);
      default:
        return AppThemeConfig.primary;
    }
  }

  String _money() =>
      '${NumberFormat.decimalPattern().format(item.amount.round())} ${item.currency}';

  /// Renders the ISO date as "dd MMM yyyy", falling back to the raw string if
  /// it ever arrives in an unexpected shape.
  String _date() {
    final parsed = DateTime.tryParse(item.dueDate);
    if (parsed == null) return item.dueDate;
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.calendar_month_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _money(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // sponsorship_type is free text set by staff; show it as-is
                  // and fall back to a generic label when it's blank.
                  item.sponsorshipType.trim().isEmpty
                      ? 'sched_assistance'.tr
                      : item.sponsorshipType.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                if (item.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _date(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'sched_status_${item.status}'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
