import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// Lets a horizontal scroller nested inside a horizontally-padded page (the
/// usual "20px side margin" list) extend all the way to the true screen
/// edges instead of clipping at the page's own padding boundary — without
/// negative Padding, which trips RenderPadding's non-negative assertion.
///
/// Always give this a bounded height from an ancestor — e.g.
/// `SizedBox(height: 40, child: FullBleedHorizontal(child: someListView))` —
/// and never the other way around (`FullBleedHorizontal(child: SizedBox(...))`).
/// The inner OverflowBox sizes *itself* from its own incoming constraints, so
/// if this widget sits directly under an unbounded-height parent (a Column or
/// ListView item), it tries to report an infinite height and corrupts the
/// rest of that list's layout — symptoms are overlapping siblings and
/// sections further down silently failing to render.
class FullBleedHorizontal extends StatelessWidget {
  const FullBleedHorizontal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return OverflowBox(
      minWidth: 0,
      maxWidth: screenWidth,
      alignment: Alignment.center,
      child: SizedBox(width: screenWidth, child: child),
    );
  }
}

class GradientScreen extends StatelessWidget {
  const GradientScreen({
    super.key,
    required this.child,
    this.showBottomOrb = true,
  });

  final Widget child;
  final bool showBottomOrb;

  @override
  Widget build(BuildContext context) {
    // Client note — plain white background, no gradient/decorative blur
    // orbs: a solid Scaffold background already does this (backgroundTop
    // and backgroundBottom are the same flat color), so no Stack/Container
    // layering is needed here anymore.
    return Scaffold(
      backgroundColor: AppThemeConfig.backgroundTop(context),
      body: child,
    );
  }
}

class BlurOrb extends StatelessWidget {
  const BlurOrb({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppThemeConfig.border(context)),
            boxShadow: [
              BoxShadow(
                color: AppThemeConfig.shadow(context),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class PageTopBar extends StatelessWidget {
  const PageTopBar({
    super.key,
    required this.title,
    this.hideBack = false,
    this.onBack,
  });

  final String title;
  final bool hideBack;

  /// Overrides the default `Navigator.pop()` — for pages reached via
  /// `Get.offAllNamed` (no route to pop back to), pass a custom action such
  /// as logging out to the sign-in screen instead.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    // Matches AppScreen's header rather than defining a fourth style: same
    // 18pt chevron, same AppPressable affordance, same title size. This is a
    // Row embedded inside screens, so it cannot delegate to AppScreen the way
    // SectionScaffold does — but it can stop looking different.
    return Row(
      children: [
        if (!hideBack) ...[
          AppPressable(
            onTap:
                onBack ??
                () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            child: Icon(
              // Was a hardcoded arrow_back_ios_new_rounded, which does not
              // mirror — so it pointed the wrong way in Arabic, Sorani and
              // Badini, i.e. for the majority of this app's users, on all 11
              // screens that use this bar.
              AppIcons.back(context),
              size: 18,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Text(
            title.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.title,
              fontWeight: AppType.wLabel,
              color: AppThemeConfig.text(context),
            ),
          ),
        ),
      ],
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppThemeConfig.primary),
          const SizedBox(width: 8),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    this.assistantRoute,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  /// K28 — a BotNavigation route key naming this section. Passed straight
  /// through to [AppScreen], which draws the AI icon in the header. Present
  /// here because 46 screens still reach the frame through this shell.
  final String? assistantRoute;

  @override
  Widget build(BuildContext context) {
    // DELEGATES to AppScreen rather than building its own header.
    //
    // The app had four parallel page-chrome systems — this one (46 screens),
    // PageTopBar, a stock AppBar, and a bare Scaffold — so header height,
    // back affordance and title placement changed depending on which screen
    // you were on. AppScreen is the single chrome; this shell stays as a
    // compatibility layer so those 46 screens pick it up without 46 rewrites.
    //
    // Its own build was equivalent to AppScreen's: GradientScreen resolves to
    // Scaffold(backgroundColor: ground), which is exactly what AppScreen
    // paints, and both collapse the header when there is nothing to put in
    // it. AppScreen additionally offers eyebrow, bottomBar and scrollable.
    //
    // padded: false is load-bearing. AppScreen applies a 20pt horizontal
    // gutter by default; SectionScaffold never did, so all 46 callers supply
    // their own. Padding here would double it on every one of them.
    return AppScreen(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      assistantRoute: assistantRoute,
      padded: false,
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.tr,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppThemeConfig.text(context),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileIcon(icon: icon, color: color),
          const SizedBox(height: 18),
          Text(
            title.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppThemeConfig.mutedText(context)),
          ),
        ],
      ),
    );
  }
}

class SectionTile extends StatelessWidget {
  const SectionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: TileIcon(icon: icon, color: color),
        title: Text(
          title.tr,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppThemeConfig.text(context),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle.tr,
            style: TextStyle(color: AppThemeConfig.mutedText(context)),
          ),
        ),
        trailing: Icon(
          AppIcons.forward(context),
          size: 18,
          color: AppThemeConfig.mutedText(context),
        ),
        onTap: onTap,
      ),
    );
  }
}

class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
}

class ModernBottomNavigator extends StatelessWidget {
  const ModernBottomNavigator({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.destinations,
    this.badgeCounts = const <int, int>{},
    this.dotIndicators = const <int>{},
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<NavDestination> destinations;
  final Map<int, int> badgeCounts;
  final Set<int> dotIndicators;

  @override
  Widget build(BuildContext context) {
    const horizontalPadding = 10.0;
    final items = List.generate(destinations.length, (index) {
      final destination = destinations[index];
      final isSelected = index == currentIndex;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ModernNavItem(
          destination: destination,
          isSelected: isSelected,
          badgeCount: badgeCounts[index] ?? 0,
          showIndicatorDot: dotIndicators.contains(index),
          onTap: () => onSelected(index),
        ),
      );
    });
    // A few tabs (e.g. a guest's 3) would otherwise pack to the left inside
    // the full-width bar; forcing the row to at least fill the available
    // width lets `center` actually center them, while still scrolling
    // left-to-right if there are enough tabs to overflow (a full user's ~9).
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 10,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth - horizontalPadding * 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: items,
            ),
          ),
        );
      },
    );
  }
}

class ModernNavItem extends StatelessWidget {
  const ModernNavItem({
    super.key,
    required this.destination,
    required this.isSelected,
    required this.badgeCount,
    required this.showIndicatorDot,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final int badgeCount;
  final bool showIndicatorDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = destination.color;
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? accent.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isSelected
              ? accent.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.16)
                            : AppThemeConfig.softSurface(context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isSelected ? destination.activeIcon : destination.icon,
                        color: isSelected
                            ? accent
                            : AppThemeConfig.mutedText(context),
                        size: 22,
                      ),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: -5,
                        right: -5,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppThemeConfig.navBarSurface(context),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    else if (showIndicatorDot)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppThemeConfig.pending(context),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppThemeConfig.navBarSurface(context),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppThemeConfig.pending(
                                  context,
                                ).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      end: 2,
                    ),
                    child: Text(
                      destination.label.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
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

class TileIcon extends StatelessWidget {
  const TileIcon({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color),
    );
  }
}
