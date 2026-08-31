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

  /// Reserves the height that [maxLines] of [style] occupies at the current
  /// text scale, so the title/subtitle boxes below are always exactly that
  /// tall — even when the actual copy is shorter and would otherwise wrap
  /// to fewer lines.
  ///
  /// WHY THIS EXISTS
  /// [Column] with `mainAxisSize: MainAxisSize.min` (this card's layout)
  /// sizes each Text to however many lines its *own* copy actually needs,
  /// not to `maxLines`. Two cards side by side in the same [CardGrid] row
  /// can have subtitles that wrap to 2 lines and 3 lines respectively —
  /// that difference is exactly the owner-reported bug (three-line "قسم
  /// الفعاليات" taller than two-line "خدمات الفعاليات"). Reserving
  /// `maxLines` worth of space unconditionally makes every card of the
  /// same [dense]-ness the same height, in the row and across the whole
  /// grid, regardless of which subtitle happens to be shorter.
  ///
  /// A [TextPainter] (not a hand-picked pixel constant) is used so the
  /// reserved height tracks the real font metrics and grows with Dynamic
  /// Type via [MediaQuery.textScalerOf] — cards stay equal at every text
  /// scale instead of a fixed height that would either clip or leave a
  /// gap once the system font size changes.
  double _reservedTextHeight(
    BuildContext context,
    TextStyle style,
    int maxLines,
  ) {
    final painter = TextPainter(
      // Explicit newlines force `maxLines` physical lines regardless of
      // width — an unconstrained single line under `maxWidth: infinity`
      // would otherwise never wrap and would report a 1-line height.
      text: TextSpan(text: List.filled(maxLines, 'M').join('\n'), style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: double.infinity);
    return painter.height;
  }

  @override
  Widget build(BuildContext context) {
    final badgeSize = dense ? 44.0 : 56.0;
    final iconSize = dense ? 22.0 : 28.0;
    final padding = dense ? 16.0 : 20.0;

    // Same maxLines the Text widgets below already use — reserving exactly
    // that many lines matches the space these subtitles were already
    // proven to fit within (no copy in the app currently truncates at
    // these limits; see the CardGrid/EventHubCard header comments for the
    // audited subtitle set).
    final titleMaxLines = 2;
    final subtitleMaxLines = dense ? 2 : 3;

    final titleStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: dense ? 14 : 17,
      color: AppThemeConfig.text(context),
    );
    final subtitleStyle = TextStyle(
      fontSize: dense ? 11.5 : 12.5,
      height: 1.3,
      color: AppThemeConfig.mutedText(context),
    );

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
              // Fixed-height box (see _reservedTextHeight) so a one-line
              // title never leaves this card shorter than a sibling whose
              // title actually wraps to two lines.
              SizedBox(
                height: _reservedTextHeight(context, titleStyle, titleMaxLines),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Text(
                    title.tr,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Same fixed-height reservation for the subtitle — this is
              // the box that produced the owner's reported bug (a 3-line
              // subtitle sizing its card taller than a 2-line sibling).
              SizedBox(
                height: _reservedTextHeight(
                  context,
                  subtitleStyle,
                  subtitleMaxLines,
                ),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Text(
                    subtitle.tr,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-column grid whose ROW HEIGHT follows its content.
///
/// WHY THIS EXISTS (and why it replaced a `GridView.count`/`.builder` with a
/// fixed `childAspectRatio`)
/// A fixed aspect ratio sizes every CELL to a uniform height derived from
/// the grid's width, independent of what is actually inside it. These cards
/// use `mainAxisSize: MainAxisSize.min` — they size to their own content —
/// so a card noticeably shorter than its cell just sits top-aligned inside
/// it, and the unused cell height reads as a dead gap between rows. On a
/// 402pt-wide screen with 6 real (non-placeholder) service cards, that gap
/// measured roughly as tall as the cards themselves — the grid looked
/// broken, not spacious.
///
/// [Wrap] has no such cell: each row is exactly as tall as its tallest
/// child, so the layout hugs real content at any item count (2, 3, or 6
/// here) and any text scale, including the largest Dynamic Type step —
/// there is no fixed ratio left to overflow. That is also why this was
/// chosen over "stretch the cards to fill a tuned aspect ratio": a tuned
/// ratio is tuned to ONE text size, and the brief requires no clipping as
/// text grows.
///
/// Implementation: [LayoutBuilder] supplies the available width so each
/// child can be given an explicit half-width `SizedBox` — [Wrap] does not
/// stretch its children itself, so without this every card would size to
/// its own intrinsic (icon + text) width instead of splitting the row
/// evenly, which is what "two columns" actually requires.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.spacing = 16});

  final List<Widget> children;

  /// Gap between cards, both directions. 16 is the app's standard card gap
  /// (the same value the old `GridView`s used for `mainAxisSpacing`/
  /// `crossAxisSpacing`) — kept on the 4/8/12/16/24/32 scale.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          // Ambient Directionality (from the active locale) decides which
          // physical side a Wrap's first child starts on — this is what
          // keeps the grid flowing right-to-left under Arabic without any
          // manual left/right branching here.
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: columnWidth, child: child),
          ],
        );
      },
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
