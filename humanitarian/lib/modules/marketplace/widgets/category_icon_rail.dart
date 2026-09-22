// #41080 — client note: "تقسيم المتجر إلى أيقونات وتصنيفات ... مع بقاء شريط
// البحث والتصنيفات في الاعلى كما هو" (divide the store into icons/categories,
// while keeping the search bar and category filter bar at the top as-is).
// This rail sits ABOVE CatalogueFilterBar as an additional quick-jump layer —
// it does not replace the filter bar's الفئات picker, it is a second, more
// visual way to reach the same [CatalogueQuery.categorySlug] filter, so a
// shopper who keeps scrolling past dozens of products for an old favourite
// can instead jump straight to its category.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/category_icons.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// The label's own text style, shared by [CategoryIconRail]'s outer height
/// budget and [_ReservedLabel]'s measurement so they can never drift apart —
/// two separate `TextStyle` literals with the same numbers looked identical
/// today and would silently stop matching the day only one of them got
/// edited. Weight doesn't affect the measured height once `height: 1.2` is
/// explicit (line-height is font-size-driven, not glyph-shape-driven), so
/// one style serves both the active and inactive tiles.
const _kCategoryLabelStyle = TextStyle(fontSize: 11, height: 1.2);
const _kCategoryLabelMaxLines = 2;

/// Reserved height for [_kCategoryLabelMaxLines] lines of
/// [_kCategoryLabelStyle], at the CURRENT device's Dynamic Type setting.
///
/// THE BUG THIS FIXES: the rail's outer [SizedBox] used to hardcode `height:
/// 92` — a guess for "56 icon + 6 gap + 2 lines of 11px text" at the DEFAULT
/// text scale. The label itself now reserves its space correctly via this
/// same measurement (see [_ReservedLabel]), which GROWS at a larger Dynamic
/// Type setting — but the outer 92 did not grow with it, so a shopper with
/// large system text turned on would hit the exact same overflow this file
/// already fixed once, just at a bigger font size instead of a bigger
/// screen. Both the outer budget and the label now read from this one
/// function, so neither can be sized for a text scale the other isn't.
double _categoryLabelHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: List.filled(_kCategoryLabelMaxLines, 'M').join('\n'),
      style: _kCategoryLabelStyle,
    ),
    maxLines: _kCategoryLabelMaxLines,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: double.infinity);
  return painter.height;
}

class CategoryIconRail extends StatelessWidget {
  const CategoryIconRail({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Loading/error/empty all just hide the rail — it is a shortcut on
      // top of the filter bar, which already carries its own failure and
      // retry state (K15's الفئات chip), so a second error banner here
      // would only repeat it.
      if (controller.isLoadingCategories.value) {
        return const SizedBox.shrink();
      }
      final categories = controller.categories;
      if (categories.isEmpty) return const SizedBox.shrink();

      final activeSlug = controller.catalogueQuery.value.categorySlug;

      // 56 icon + 6 gap + the label's OWN reserved height (see
      // _categoryLabelHeight) — measured, not guessed, so this budget grows
      // together with the label at a larger Dynamic Type setting instead of
      // falling behind it.
      return SizedBox(
        height: 56 + 6 + _categoryLabelHeight(context),
        child: FullBleedHorizontal(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final cat = categories[i];
              final slug = (cat['slug'] ?? '').toString();
              final active = slug.isNotEmpty && slug == activeSlug;
              return _CategoryTile(
                label: controller.localizedCategoryName(cat),
                icon: categoryIconFor((cat['icon_key'] ?? '').toString()),
                active: active,
                onTap: () {
                  AppHaptics.selection();
                  controller.setCatalogueQuery(
                    controller.catalogueQuery.value.copyWith(
                      // Tapping the already-active category clears it —
                      // same "tap again to turn off" rule the filter bar's
                      // sort chips already use (CatalogueFilterBar._toggleSort).
                      categorySlug: active ? '' : slug,
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
    });
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeConfig.accent(context);
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.16)
                    : AppThemeConfig.softSurface(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: active
                      ? accent
                      : AppThemeConfig.border(context),
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Icon(
                icon,
                color: active ? accent : AppThemeConfig.mutedText(context),
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            // THE BUG THIS FIXES: the rail's outer SizedBox(height: 92) was a
            // guessed budget for "56 icon + 6 gap + 2 lines of 11px text",
            // and on-device it ran 2px short — logged live as "A RenderFlex
            // overflowed by 2.0 pixels on the bottom" right here. Same root
            // cause as the EventHubCard/_QuickAction bugs fixed earlier this
            // session: a hand-picked height constant drifting from the real
            // rendered size. Measuring the label with a TextPainter (using
            // the SAME style and maxLines below) and reserving exactly that
            // — rather than reusing another guessed constant — is what
            // actually closes the gap instead of narrowing it.
            _ReservedLabel(
              label: label,
              active: active,
              color: active ? accent : AppThemeConfig.text(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReservedLabel extends StatelessWidget {
  const _ReservedLabel({
    required this.label,
    required this.active,
    required this.color,
  });

  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = _kCategoryLabelStyle.copyWith(
      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
      color: color,
    );
    return ClipRect(
      child: SizedBox(
        height: _categoryLabelHeight(context),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: _kCategoryLabelMaxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}
