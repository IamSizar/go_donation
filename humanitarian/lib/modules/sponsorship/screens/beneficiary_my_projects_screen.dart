// Beneficiary help requests — ONE screen, filtered by request status.
//
// WHY THIS FILE LOOKS LIKE THIS
// There used to be two screens here: "My help requests" (every row from
// BeneficiaryProjectsController) and "Pending projects for help" (the same
// controller, the same fetch, the same rows, with `status in
// {pending, submitted, under_review}` applied client-side). Two menu items,
// two files, two card widgets and two copies of _money/_dateLabel/
// _statusColor/_categoryIcon for what was a filter predicate. Neither screen
// carried an action, a field or a permission the other lacked — no cancel, no
// edit, no approve — so there was nothing behavioural to preserve by keeping
// them apart.
//
// The filter row follows the pattern already established by
// SponsorshipScheduleScreen: a horizontally scrollable strip of chips, the
// active one filled with the primary colour, driving a single AppAsync below
// it. The app must not gain a second convention for the same idea.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_projects_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

/// The status buckets the filter strip offers.
///
/// `all` deliberately has no predicate — it is the unfiltered list, and the
/// switch below returns the rows untouched for it.
enum ProjectRequestFilter { all, pending, approved, rejected }

/// Beneficiary's own project/help requests, filtered by status.
///
/// [initialFilter] lets a caller deep-link straight into a bucket — the
/// dashboard's "Pending" tile and the bot's `pending_projects` intent both
/// want the pending view, which is exactly what the second screen used to be.
class BeneficiaryMyProjectsScreen extends StatefulWidget {
  const BeneficiaryMyProjectsScreen({
    super.key,
    this.initialFilter = ProjectRequestFilter.all,
  });

  final ProjectRequestFilter initialFilter;

  @override
  State<BeneficiaryMyProjectsScreen> createState() =>
      _BeneficiaryMyProjectsScreenState();
}

class _BeneficiaryMyProjectsScreenState
    extends State<BeneficiaryMyProjectsScreen> {
  late ProjectRequestFilter _selected = widget.initialFilter;

  late final BeneficiaryProjectsController _controller =
      Get.isRegistered<BeneficiaryProjectsController>()
      ? Get.find<BeneficiaryProjectsController>()
      : Get.put(BeneficiaryProjectsController());

  /// Filtering is client-side over the single list the controller already
  /// holds — there is one fetch for every bucket, which is precisely why the
  /// two screens were duplicates. Because the rows are derived synchronously
  /// from the current list, switching filters cannot leave the previous
  /// bucket's rows on screen under the new heading: the list rebuilds from
  /// scratch in the same frame as the selection change.
  List<Map<String, dynamic>> _rowsFor(
    ProjectRequestFilter filter,
    List<Map<String, dynamic>> all,
  ) {
    if (filter == ProjectRequestFilter.all) return all;
    return all.where((item) => _bucketOf(item) == filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'My help requests',
      subtitle: 'Track project requests you submitted for admin review.',
      child: Column(
        children: [
          _FilterStrip(
            selected: _selected,
            // Rebuilding with the new selection is all that is needed; no
            // refetch, so there is no loading flash between buckets.
            onSelect: (filter) => setState(() => _selected = filter),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              final all = _controller.projects.toList();
              final rows = _rowsFor(_selected, all);
              // AppAsync renders exactly ONE of loading / content / error /
              // empty, and checks the error branch BEFORE the empty branch —
              // a failed fetch also leaves the list empty, and "no requests
              // yet" would otherwise win over a failure the user could retry.
              //
              // The summary band lives inside the builder because it reports
              // COUNTS: showing "0 pending" while the fetch is still in
              // flight states something that is not yet known.
              return AppAsync<List<Map<String, dynamic>>>(
                loading: _controller.isLoading.value,
                error: _controller.errorMessage.value,
                onRetry: _controller.fetchProjects,
                data: rows,
                isEmpty: (list) => list.isEmpty,
                skeleton: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: AppSkeleton.rows(count: 4, withProgress: false),
                ),
                // The empty copy names the ACTIVE bucket: "no pending
                // requests" is a different sentence from "no requests at all",
                // and telling a beneficiary they have never submitted anything
                // when they merely have nothing approved would be wrong.
                empty: _EmptyState(filter: _selected),
                builder: (list) => RefreshIndicator(
                  onRefresh: _controller.fetchProjects,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      // Counted over ALL requests, not the active bucket — it
                      // is an overview of the whole pipeline, and a "3
                      // pending" chip that only ever read "3 pending" while
                      // the pending filter was active would be useless.
                      _SummaryBand(items: all),
                      const SizedBox(height: 14),
                      for (final item in list) ...[
                        _ProjectRequestCard(item: item),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Filter strip ───────────────────────────────────────────────────────────

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.selected, required this.onSelect});

  final ProjectRequestFilter selected;
  final ValueChanged<ProjectRequestFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable so the chips never overflow on a narrow screen
    // or with longer translations — same construction as the sponsorship
    // schedule's filter row.
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: ProjectRequestFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = ProjectRequestFilter.values[i];
          final active = filter == selected;
          return Material(
            color: active
                ? AppThemeConfig.primary
                : AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelect(filter),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  _filterLabel(filter).tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: active ? Colors.white : AppThemeConfig.text(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _filterLabel(ProjectRequestFilter filter) {
  return switch (filter) {
    ProjectRequestFilter.all => 'All requests',
    ProjectRequestFilter.pending => 'Pending',
    ProjectRequestFilter.approved => 'Approved',
    ProjectRequestFilter.rejected => 'Rejected',
  };
}

/// Which bucket a row belongs to.
///
/// The pending set is the one the old pending-only screen used verbatim:
/// anything still awaiting review, changes, approval or sponsor matching.
/// Anything the backend reports outside these three buckets (`completed`,
/// `on_hold`, …) shows only under "All requests" — inventing a bucket for a
/// status the spec does not name would be guessing.
ProjectRequestFilter? _bucketOf(Map<String, dynamic> item) {
  final status = (item['status'] ?? '').toString();
  return switch (status) {
    'pending' || 'submitted' || 'under_review' => ProjectRequestFilter.pending,
    'approved' => ProjectRequestFilter.approved,
    'rejected' => ProjectRequestFilter.rejected,
    _ => null,
  };
}

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final ProjectRequestFilter filter;

  @override
  Widget build(BuildContext context) {
    return switch (filter) {
      ProjectRequestFilter.all => const AppEmpty(
        title: 'No requests yet',
        message: 'Submitted project requests will appear here.',
        icon: Icons.assignment_rounded,
      ),
      ProjectRequestFilter.pending => const AppEmpty(
        title: 'No pending requests',
        message:
            'Requests waiting for review, changes, or sponsor matching will appear here.',
        icon: Icons.hourglass_top_rounded,
      ),
      ProjectRequestFilter.approved => const AppEmpty(
        title: 'No approved requests',
        message: 'Requests the admins approve will appear here.',
        icon: Icons.verified_rounded,
      ),
      ProjectRequestFilter.rejected => const AppEmpty(
        title: 'No rejected requests',
        message: 'Requests the admins turn down will appear here.',
        icon: Icons.do_not_disturb_on_rounded,
      ),
    };
  }
}

// ─── Content ────────────────────────────────────────────────────────────────

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final pending = items
        .where((item) => _bucketOf(item) == ProjectRequestFilter.pending)
        .length;
    final approved = items
        .where((item) => _bucketOf(item) == ProjectRequestFilter.approved)
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

/// One request row. This is the richer of the two cards the merged screens
/// had: it keeps the status pill, funding progress and engagement counts from
/// "My help requests", plus the submitted date that only the pending card
/// used to show — so no bucket loses information in the merge.
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
    final submittedAt = _dateLabel(item['created_at']);
    final updatedAt = _dateLabel(item['updated_at'] ?? item['created_at']);
    final color = _statusColor(context, status);

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
              if (submittedAt.isNotEmpty)
                _MetricPill(icon: Icons.event_rounded, label: submittedAt),
              // Only worth a pill when it says something the submitted date
              // does not — an untouched request has updated_at == created_at.
              if (updatedAt.isNotEmpty && updatedAt != submittedAt)
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

// ─── Formatting helpers ─────────────────────────────────────────────────────

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

Color _statusColor(BuildContext context, String status) {
  return switch (status) {
    'approved' => AppThemeConfig.accent(context),
    'rejected' => AppThemeConfig.consequence(context),
    'under_review' => AppThemeConfig.pending(context),
    'pending' || 'submitted' => AppThemeConfig.pending(context),
    _ => AppThemeConfig.accent(context),
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
