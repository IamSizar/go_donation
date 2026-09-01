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
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

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
    // AppPressable, not InkWell.
    //
    // The house pressable already does the three things a tile like this
    // needs and an InkWell does not: it presses on the RAW POINTER DOWN
    // (Listener.onPointerDown) rather than GestureDetector.onTapDown, which
    // TapGestureRecognizer can hold for up to kPressTimeout — 100ms of
    // latency is exactly what makes a grid stop feeling direct; it scales on
    // a SPRING started from the current value and velocity, so a press
    // arriving mid-release continues instead of jumping; and it already
    // honours Reduce Motion by dropping the scale and keeping an opacity
    // change, so the feedback survives without the movement.
    //
    // Using it here also means these tiles feel identical to every other
    // pressable surface in the app rather than being the one place with a
    // Material ripple and no scale.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: AppPressable(
        onTap: item.onTap,
        semanticLabel: item.label.tr,
        child: SizedBox(
          // 96 tall — comfortably past the 44pt floor, and enough for an icon
          // over two lines of Arabic without the label being clipped.
          height: 96,
          child: Padding(
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
                  // 12, not 11.5: twelve is the floor for body-ish text, and
                  // these labels are the only thing naming each destination.
                  fontSize: 12,
                  height: 1.25,
                  // Small text wants a touch MORE tracking, not less — the
                  // opposite of a heading. Large type is what gets tightened.
                  letterSpacing: 0.1,
                  fontWeight: FontWeight.w600,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ],
          ),
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
