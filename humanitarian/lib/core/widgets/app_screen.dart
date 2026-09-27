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
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/modules/bot/widgets/assistant_hint_button.dart';

class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.child,
    this.title = '',
    this.subtitle = '',
    this.eyebrow = '',
    this.trailing,
    this.assistantRoute,
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

  /// K28 — a `BotNavigation` route key naming this section, e.g. `'donate'`.
  ///
  /// When set, the header shows the AI icon the client asked for beside each
  /// menu, and tapping it opens the assistant already asking about this
  /// section. It lives on the shared frame rather than on each screen's own
  /// header so the next section added inherits it instead of quietly shipping
  /// without one.
  final String? assistantRoute;

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
        trailing != null ||
        assistantRoute != null;

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
                assistantRoute: assistantRoute,
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
    required this.assistantRoute,
    required this.canPop,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final Widget? trailing;
  final String? assistantRoute;
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
      // THE BUG THIS FIXES: this Row cross-aligned the back chevron and the
      // title block to `start` (their shared TOP edge) unconditionally. That
      // is right when the title block has multiple lines (eyebrow above
      // title, or a subtitle below it) — the chevron should sit level with
      // the FIRST line, not float in the middle of the stack. But
      // `AppPressable` (wrapping the chevron) enforces a 44pt minimum touch
      // target, so the icon itself is centered inside a box roughly twice
      // as tall as one line of title text. Top-aligning a 44pt box against
      // a ~24pt text line leaves the chevron's actual glyph sitting
      // noticeably below the title's own vertical center — reported live,
      // correctly, as "the title doesn't look aligned with the back
      // button." Only the single-line case (the overwhelming majority of
      // this app's 46 screens using this header — just a title, no eyebrow
      // or subtitle) can safely center instead: with nothing else in the
      // stack, there is no "first line" for the chevron to lose alignment
      // with by centering against the whole block.
      child: Row(
        crossAxisAlignment: (eyebrow.isEmpty && subtitle.isEmpty)
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (canPop) ...[
            AppPressable(
              onTap: () => Navigator.of(context).maybePop(),
              semanticLabel: MaterialLocalizations.of(
                context,
              ).backButtonTooltip,
              child: Icon(
                // arrow_back_ios_new_rounded carries matchTextDirection, so
                // Flutter mirrors it under RTL on its own. This used to swap
                // it by hand as well, which double-mirrored it and pointed it
                // the wrong way for the majority of this app's users.
                AppIcons.back(context),
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
          // K28 — the section's AI icon. Placed BEFORE `trailing` so a screen
          // that already owns the far end of its header (a filter, an avatar)
          // keeps that position and the assistant tucks in beside it, rather
          // than the two fighting over the same slot.
          if (assistantRoute != null) ...[
            const SizedBox(width: AppSpace.xs),
            AssistantHintButton(route: assistantRoute!),
          ],
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

/// The Tawazzn mark shown beside the bottom-navigation title (client note,
/// 2026-09-27: "add the app logo inside the app right next to the title of
/// the tab" — corrected the same day: only the 4 bottom-nav tab titles in
/// `DashboardTopBar` — لوحة التحكم / Marketplace / Events / City Guide — not
/// every screen's header. An earlier version of this change had wired it into
/// [AppScreen] and `PageTopBar` (glass_ui.dart) as well; that was reverted.
///
/// Lives here rather than beside `_TopBarTitle` in dashboard_screen.dart so it
/// stays with the app's other shared chrome pieces.
class HeaderLogo extends StatelessWidget {
  const HeaderLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/tawazzn_icon_foreground.png',
      width: size,
      height: size,
      // The title text beside it already carries the semantic label;
      // marking this decorative avoids a screen reader reading an
      // unlocalized "tawazzn icon foreground" filename.
      excludeFromSemantics: true,
    );
  }
}
