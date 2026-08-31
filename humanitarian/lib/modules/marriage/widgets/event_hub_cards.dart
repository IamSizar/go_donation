// Card primitives for the Events hub grid redesign (chunk 5).
//
// WHY THIS FILE EXISTS
// The Events tab used to be three flat, full-width tile lists (14 tiles plus
// an "About & contact" pair). The owner asked for the two service groups to
// collapse into a top-level grid of two cards, each opening its own grid of
// cards. Two screens need visually-identical cards at two different sizes —
// [EventHubCard] is that one implementation, parameterised by [dense] rather
// than duplicated per screen.
//
// DESIGN NOTES
//   * Press feedback is [AppPressable] — the app's existing tap primitive —
//     rather than a bespoke InkWell, so the 0.97 spring scale, the reduced-
//     motion opacity fallback, and the 44×44 minimum touch target are all
//     inherited for free instead of re-implemented here.
//   * Colour comes only from [AppThemeConfig]; text sits on `text`/
//     `mutedText` over `surface`, the same pairing `test/design/
//     contrast_test.dart` already measures at 16.7:1 / 7.9:1 (light) and
//     14.4:1 / 8.4:1 (dark) — both comfortably above the 4.5:1 floor.
//   * [StaggeredEntrance] fades + rises each card in ~40ms apart on open,
//     and collapses to an instant, non-positional appearance when the
//     platform requests reduced motion (`MediaQuery.disableAnimations`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// A tappable card: icon, title, one-line-or-wrapping subtitle.
///
/// Used at two sizes from the same definition — [dense] shrinks the icon and
/// padding for the second-level item grids, where six cards share the
/// screen instead of two.
class EventHubCard extends StatelessWidget {
  const EventHubCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.heroTag,
    this.dense = false,
  });

  final IconData icon;
  final Color color;

  /// Translation key — resolved with `.tr` inside, so callers pass the
  /// literal English key exactly as it appears in the translation maps.
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// When set, wraps the icon badge in a [Hero] with this tag so the group
  /// screen's matching header can share it, giving the "opens out of the
  /// card" continuity the redesign asked for. Left null for second-level
  /// item cards, which have no further screen to hand off to.
  final String? heroTag;

  /// Shrinks the card for the 6-item group grids (top-level cards stay
  /// full-size — they are the only two things on that screen).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final badgeSize = dense ? 44.0 : 56.0;
    final iconSize = dense ? 22.0 : 28.0;
    final padding = dense ? 16.0 : 20.0;

    final badge = Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(dense ? 12 : 16),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );

    return AppPressable(
      expand: true,
      haptic: AppPressHaptic.selection,
      onTap: onTap,
      semanticLabel: '${title.tr}. ${subtitle.tr}',
      child: Material(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppThemeConfig.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              heroTag == null ? badge : Hero(tag: heroTag!, child: badge),
              SizedBox(height: dense ? 12 : 16),
              Text(
                title.tr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: dense ? 14 : 17,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle.tr,
                maxLines: dense ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 11.5 : 12.5,
                  height: 1.3,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and rises [child] in, delayed by `40ms * index` — the "stagger the
/// grid items in" requirement from the redesign brief.
///
/// Reads [AppMotion.reduced] itself (rather than asking the caller to check)
/// so every grid on this screen honours Reduce Motion identically: no delay,
/// no slide, the card is simply present on the first frame.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _visible = false;
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);

    if (!_scheduled) {
      _scheduled = true;
      if (reduced) {
        // No positional motion, no stagger delay — the card is just there.
        _visible = true;
      } else {
        Future.delayed(Duration(milliseconds: 40 * widget.index), () {
          if (mounted) setState(() => _visible = true);
        });
      }
    }

    if (reduced) return widget.child;

    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.06),
      duration: AppMotion.settleDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: AppMotion.settleDuration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
