// menu_grid.dart — the profile menu's compact pieces.
//
// WHY THIS EXISTS
// The profile menu was twenty-four full-width rows in one ListView, separated
// by four anonymous dividers. Roughly six screens of scrolling to reach "Terms
// & Conditions", and nothing on the way told you which part of the list you
// were in. The owner: "extremely crowded … I don't want it to be this long."
//
// The fix is not an accordion. Collapsing would have hidden every destination
// behind a tap and made the screen a menu of menus — shorter to look at,
// longer to use. Most of these entries are a word and an icon; they do not
// need a full-width row each.
//
//   MenuGrid      three across, so twelve destinations take four rows instead
//                 of twelve. Nothing is hidden and the screen roughly halves.
//   MenuCard      a grouped card for rows that must stay rows — the ones
//                 carrying switches and trailing values (language, dark mode,
//                 notifications), which cannot be squeezed into a tile.
//   MenuSectionLabel  names each group, which the dividers never did.
//
// Sizing follows the skill's Quick Reference: tiles are ≥44pt on both axes,
// gaps are on the 4/8 rhythm, and the label/tile/section spacing uses the
// 8/16/24 tiers rather than arbitrary values.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';

/// A small heading above a group. Muted and light, so it organises the list
/// without competing with the entries under it.
class MenuSectionLabel extends StatelessWidget {
  const MenuSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 24 above, 8 below: the gap that separates groups is bigger than the
      // one that binds a label to its group, so the grouping reads without a
      // rule or a box.
      padding: const EdgeInsetsDirectional.only(start: 4, top: 24, bottom: 8),
      child: Text(
        label.tr,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppThemeConfig.mutedText(context),
        ),
      ),
    );
  }
}

/// One destination in the grid: a tinted icon over its name.
class MenuGridItem {
  const MenuGridItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

/// Three-across grid of destinations.
class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key, required this.items});

  final List<MenuGridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        const perRow = 3;
        // Computed rather than fixed, so the tiles fill the row exactly at any
        // width instead of leaving a ragged margin on one side.
        final tileWidth = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _MenuTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});

  final MenuGridItem item;

  @override
  Widget build(BuildContext context) {
    final tint = item.color ?? AppThemeConfig.accent(context);
    return Material(
      color: AppThemeConfig.softSurface(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          // 96 tall — comfortably past the 44pt floor, and enough for an icon
          // over two lines of Arabic without the label being clipped.
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 20, color: tint),
              ),
              const SizedBox(height: 8),
              Text(
                item.label.tr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grouped card for rows that have to stay rows — anything with a switch or
/// a trailing value. Rounded and filled so the group reads as one object,
/// which is what the four anonymous dividers were failing to do.
class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
