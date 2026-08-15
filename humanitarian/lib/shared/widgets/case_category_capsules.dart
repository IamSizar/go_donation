// Quick Filter Capsules — admin-managed beneficiary-case category chips
// (Orphan Sponsorship, Widow Support, Food Baskets, etc). Used both as a
// Home-screen shortcut row and as the persistent filter on the case list
// screen it jumps into. Visual pattern mirrors news_activities_screen.dart's
// _FilterChip/_CategoryChips.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/case_categories_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class CaseCategoryCapsules extends StatefulWidget {
  const CaseCategoryCapsules({
    super.key,
    required this.selected,
    required this.onSelected,
    this.header,
  });

  /// The currently selected category slug, or null for "All".
  final String? selected;
  final ValueChanged<String?> onSelected;

  /// A heading drawn above the row, and drawn ONLY when there is a row or an
  /// error to explain (C2).
  ///
  /// Home used to print its own "Browse by category" label unconditionally
  /// while this widget rendered `SizedBox.shrink()` on an empty list, so a
  /// failed load left a heading standing over nothing — asserting both that
  /// there are categories and that there are none. Passing the heading in
  /// means the two can no longer disagree, and passing it as a WIDGET rather
  /// than a string keeps each caller's own label styling where it lives.
  ///
  /// The case-list screen passes nothing: it has a page heading already.
  final Widget? header;

  @override
  State<CaseCategoryCapsules> createState() => _CaseCategoryCapsulesState();
}

class _CaseCategoryCapsulesState extends State<CaseCategoryCapsules> {
  List<CaseCategory> _categories = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await fetchCaseCategories();
      if (!mounted) return;
      setState(() {
        _categories = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // The message says what is missing and what it costs, not what threw.
      setState(() {
        _categories = const [];
        _loading = false;
        _error = 'Could not load the browse categories.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // A genuinely empty taxonomy is the one state that still renders nothing,
    // heading included: there is no category to browse and nothing went
    // wrong, so an empty state would be an announcement about an admin list
    // the user cannot act on.
    if (!_loading && _error == null && _categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final row = AppAsync<List<CaseCategory>>(
      loading: _loading,
      error: _error,
      onRetry: _load,
      data: _categories,
      isEmpty: (list) => list.isEmpty,
      // Unreachable — the guard above takes the empty case — but AppAsync
      // requires it, and a shrink is the right answer if it ever is reached.
      empty: const SizedBox.shrink(),
      skeleton: const _CapsuleSkeleton(),
      builder: _buildRow,
    );

    final header = widget.header;
    if (header == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, const SizedBox(height: 12), row],
    );
  }

  Widget _buildRow(List<CaseCategory> categories) {
    // Both call sites nest this in a page with 20px side padding — without
    // canceling that here, dragging a capsule toward the edge made it
    // disappear early, well before actually reaching the screen edge.
    //
    // The fixed-height SizedBox must wrap FullBleedHorizontal, not nest
    // inside it: OverflowBox (inside FullBleedHorizontal) sizes itself using
    // its own incoming constraints, which are unbounded height when this
    // widget sits directly in a vertical ListView — nesting it the other way
    // made OverflowBox try to report an infinite height and corrupted the
    // rest of the list's layout (overlapping/missing sections below it).
    return SizedBox(
      height: 40,
      child: FullBleedHorizontal(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: categories.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _CapsuleChip(
                label: 'All'.tr,
                active: widget.selected == null,
                onTap: () => widget.onSelected(null),
              );
            }
            final cat = categories[i - 1];
            return _CapsuleChip(
              label: cat.localizedName,
              active: widget.selected == cat.slug,
              onTap: () => widget.onSelected(cat.slug),
            );
          },
        ),
      ),
    );
  }
}

/// Four pill-shaped bones at the height and spacing of the real capsules, so
/// the row fills in rather than popping in and shifting everything below it.
class _CapsuleSkeleton extends StatelessWidget {
  const _CapsuleSkeleton();

  @override
  Widget build(BuildContext context) {
    // Varied widths, because four identical pills read as a loading bar
    // rather than as chips.
    const widths = <double>[54, 92, 76, 110];
    return SizedBox(
      height: 40,
      child: AppSkeleton(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => Container(
            width: widths[i],
            decoration: BoxDecoration(
              color: AppColors.of(context).line,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleChip extends StatelessWidget {
  const _CapsuleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppThemeConfig.primary : AppThemeConfig.surface(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppThemeConfig.text(context),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
