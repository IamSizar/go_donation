import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

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
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppThemeConfig.backgroundTop(context),
                  AppThemeConfig.backgroundBottom(context),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: BlurOrb(
              color: Colors.tealAccent.withValues(alpha: 0.22),
              size: 220,
            ),
          ),
          if (showBottomOrb)
            Positioned(
              bottom: -100,
              left: -50,
              child: BlurOrb(
                color: Colors.blueAccent.withValues(alpha: 0.18),
                size: 260,
              ),
            ),
          child,
        ],
      ),
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
  const PageTopBar({super.key, required this.title, this.hideBack = false});

  final String title;
  final bool hideBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!hideBack)
          Container(
            decoration: BoxDecoration(
              color: AppThemeConfig.surface(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: IconButton(
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
        if (!hideBack) const SizedBox(width: 14),
        Expanded(
          child: Text(
            title.tr,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
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
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return GradientScreen(
      showBottomOrb: false,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canPop) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeConfig.surface(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppThemeConfig.border(context),
                        ),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.arrow_forward_ios_rounded
                              : Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.tr,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppThemeConfig.text(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle.tr,
                          style: TextStyle(
                            color: AppThemeConfig.mutedText(context),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
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
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle.tr,
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
          Icons.arrow_forward_ios_rounded,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: List.generate(destinations.length, (index) {
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
        }),
      ),
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
        gradient: isSelected
            ? LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.20),
                  accent.withValues(alpha: 0.08),
                ],
              )
            : null,
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
                            color: const Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppThemeConfig.navBarSurface(context),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFF59E0B,
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
                    padding: const EdgeInsets.only(left: 10, right: 2),
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
