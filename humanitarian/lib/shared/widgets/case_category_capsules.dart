// Quick Filter Capsules — admin-managed beneficiary-case category chips
// (Orphan Sponsorship, Widow Support, Food Baskets, etc). Used both as a
// Home-screen shortcut row and as the persistent filter on the case list
// screen it jumps into. Visual pattern mirrors news_activities_screen.dart's
// _FilterChip/_CategoryChips.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/case_categories_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

class CaseCategoryCapsules extends StatefulWidget {
  const CaseCategoryCapsules({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// The currently selected category slug, or null for "All".
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  State<CaseCategoryCapsules> createState() => _CaseCategoryCapsulesState();
}

class _CaseCategoryCapsulesState extends State<CaseCategoryCapsules> {
  List<CaseCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await fetchCaseCategories();
    if (!mounted) return;
    setState(() => _categories = items);
  }

  @override
  Widget build(BuildContext context) {
    // Best-effort feature: on failure/offline the capsule row just doesn't
    // render rather than showing an empty "All"-only row.
    if (_categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _CapsuleChip(
              label: 'All'.tr,
              active: widget.selected == null,
              onTap: () => widget.onSelected(null),
            );
          }
          final cat = _categories[i - 1];
          return _CapsuleChip(
            label: cat.localizedName,
            active: widget.selected == cat.slug,
            onTap: () => widget.onSelected(cat.slug),
          );
        },
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
