// AppScreen — the app's one page frame.
//
// WHY THIS WIDGET EXISTS
// The audit found FOUR chrome systems running in parallel: SectionScaffold
// (46 screens), PageTopBar (10), stock Material AppBar (9) and bare Scaffold
// (6). Header height, back-button placement and title styling therefore
// changed depending on which screen you happened to be on — `bot_chat_screen`
// and `edit_profile` used a stock AppBar while their sibling screens used
// SectionScaffold, so the seam was visible during ordinary navigation.
//
// Things that look the same must behave the same and live in the same place,
// or people cannot predict what happens next. This is that one place.
//
// MIGRATION
// The constructor deliberately mirrors `SectionScaffold(title:, subtitle:,
// child:, trailing:)` so converting a screen is a rename in most cases. Both
// `title` and `subtitle` are still passed through `.tr`, matching the old
// behaviour, so no call site needs its strings changed.
//
// The one addition is [eyebrow]: a short uppercase label ABOVE the title,
// which is where context belongs ("34 open", "Step 2 of 6", "Winter fuel ·
// Duhok"). Prefer it over [subtitle] for new screens — a count or a parent
// name reads better above the title than as a sentence below it.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.child,
    this.title = '',
    this.subtitle = '',
    this.eyebrow = '',
    this.trailing,
    this.scrollable = false,
    this.bottomBar,
    this.padded = true,
  });

  /// The screen's body.
  final Widget child;

  /// The screen title. Translated via `.tr`, matching SectionScaffold.
  final String title;

  /// A supporting sentence below the title. Translated via `.tr`.
  ///
  /// Kept for migration compatibility. For new screens prefer [eyebrow].
  final String subtitle;

  /// A short label above the title — a count, a parent name, a step.
  /// Translated via `.tr`. Rendered uppercase with positive tracking.
  final String eyebrow;

  /// An action at the far end of the header row (avatar, filter, overflow).
  final Widget? trailing;

  /// Wraps [child] in a scroll view with the standard gutter. Leave false
  /// when the child is already a ListView — nesting scrollables is the
  /// commonest way to break a list.
  final bool scrollable;

  /// A pinned bar at the bottom of the screen, above the safe area. Used for
  /// a single primary action ("Give 50,000 IQD").
  final Widget? bottomBar;

  /// Applies the standard horizontal gutter to [child]. Turn off for
  /// edge-to-edge content such as a hero image or a full-bleed list.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final canPop = Navigator.of(context).canPop();
    final hasHeader =
        title.isNotEmpty ||
        subtitle.isNotEmpty ||
        eyebrow.isNotEmpty ||
        canPop ||
        trailing != null;

    Widget body = child;
    if (padded) {
      body = Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.lg),
        child: body,
      );
    }
    if (scrollable) {
      body = SingleChildScrollView(
        // Dismisses the keyboard when the user starts scrolling a form. The
        // audit found this wired nowhere in the app, only tap-to-dismiss.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasHeader)
              _Header(
                title: title,
                subtitle: subtitle,
                eyebrow: eyebrow,
                trailing: trailing,
                canPop: canPop,
              ),
            Expanded(child: body),
            if (bottomBar != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.sm,
                ),
                child: SafeArea(top: false, child: bottomBar!),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    required this.trailing,
    required this.canPop,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final Widget? trailing;
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop) ...[
            AppPressable(
              onTap: () => Navigator.of(context).maybePop(),
              semanticLabel: MaterialLocalizations.of(
                context,
              ).backButtonTooltip,
              child: Icon(
                // Mirrors under RTL. Three of the app's four languages are
                // right-to-left, so a hardcoded left-pointing chevron would
                // point the wrong way for most users.
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_forward_ios_rounded
                    : Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: c.ink,
              ),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow.isNotEmpty)
                  Text(
                    eyebrow.tr.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: AppType.wLabel,
                      letterSpacing: AppType.trackLabel,
                      color: c.inkTertiary,
                    ),
                  ),
                if (title.isNotEmpty) ...[
                  if (eyebrow.isNotEmpty) const SizedBox(height: AppSpace.xxs),
                  Text(
                    title.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.title,
                      fontWeight: FontWeight.w600,
                      letterSpacing: AppType.trackTitle,
                      height: AppType.leadTitle,
                      color: c.ink,
                    ),
                  ),
                ],
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(
                    subtitle.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.meta,
                      height: AppType.leadDense,
                      color: c.inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A section divider: a hairline, a small uppercase label, and an optional
/// trailing action.
///
/// This is the structural device the whole design rests on — sections are
/// separated by one rule weight rather than by cards, shadows or coloured
/// blocks. Using it consistently is most of what makes the app read as one
/// system.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.label,
    this.action,
    this.onActionTap,
    this.emphasized = false,
  });

  /// Translated via `.tr` and rendered uppercase.
  final String label;

  /// Optional trailing text action ("See all"). Translated via `.tr`.
  final String? action;

  final VoidCallback? onActionTap;

  /// Draws the rule in ink rather than the hairline colour. Reserve this for
  /// the first section on a screen, where it anchors the page.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: emphasized ? 1.5 : 1,
            color: emphasized ? c.ink : c.line,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              top: AppSpace.sm,
              bottom: AppSpace.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    label.tr.toUpperCase(),
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: AppType.wLabel,
                      letterSpacing: AppType.trackLabel,
                      color: c.inkSecondary,
                    ),
                  ),
                ),
                if (action != null)
                  AppPressable(
                    onTap: onActionTap,
                    child: Text(
                      action!.tr,
                      style: TextStyle(
                        fontSize: AppType.meta,
                        fontWeight: AppType.wLabel,
                        color: c.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
