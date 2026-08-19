// The four UI states — loading, content, empty, error — as widgets, plus an
// AppAsync switcher that makes it hard to ship a screen missing one.
//
// WHY THIS FILE EXISTS
// The audit measured all 116 screens and admin pages against the four-state
// rule. Loading, error and empty were broadly handled (70–86%), but the two
// things the standard is most specific about were effectively absent:
//
//   * SKELETONS appear on 1 of 116 surfaces. Everything else shows a spinner
//     or the literal word "Loading…", so content pops in rather than filling
//     in, and the layout jumps when it arrives.
//   * RETRY appears on 9 of 58 app screens and 0 of 58 console pages. A
//     failed load rendered a message string and stopped there. A dead-end
//     error screen is a bug.
//
// DESIGN NOTES
//   * The skeleton mirrors the geometry of the real row it replaces, so the
//     transition to content is a fill rather than a jump.
//   * The error state keeps the LAST KNOWN data visible at reduced opacity
//     where the caller has any. An offline user can still read what they had,
//     which is far more useful than an empty screen with an apology on it.
//   * Every error names the cause and offers the way out, in that order.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// A shimmering placeholder shaped like the content it stands in for.
///
/// Prefer [AppSkeleton.rows] over a spinner for any list. The shimmer is a
/// slow opacity pulse rather than a travelling gradient — cheaper, and it
/// still reads as "working" without a large moving object on screen.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({super.key, required this.child});

  /// Build the bones with [bone]; this wraps them in the pulse.
  final Widget child;

  /// A single skeleton bar. [widthFactor] is a fraction of the available
  /// width, so a set of bones reads as ragged text rather than a solid block.
  static Widget bone({
    double height = 10,
    double widthFactor = 1,
    EdgeInsetsGeometry margin = const EdgeInsetsDirectional.only(bottom: 8),
  }) {
    return Padding(
      padding: margin,
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: _Bone(height: height),
      ),
    );
  }

  /// [count] placeholder rows shaped like [AppRow]-style content: a title, a
  /// metadata line, and a progress rule.
  static Widget rows({int count = 4, bool withProgress = true}) {
    return AppSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List<Widget>.generate(count, (i) {
          // Vary the widths so the placeholder does not read as a table of
          // identical blocks.
          final titleWidths = <double>[0.62, 0.74, 0.56, 0.68, 0.7];
          final metaWidths = <double>[0.4, 0.36, 0.46, 0.42, 0.34];
          return Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bone(height: 11, widthFactor: titleWidths[i % 5]),
                bone(height: 8, widthFactor: metaWidths[i % 5]),
                if (withProgress)
                  bone(
                    height: 2,
                    margin: const EdgeInsetsDirectional.only(top: AppSpace.xxs),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Placeholder for a CHAT TRANSCRIPT: bubbles alternating side, of varying
  /// width and height.
  ///
  /// [rows] is the wrong shape here — uniform full-width text rows jump into a
  /// conversation rather than filling into one. The layout is hardcoded rather
  /// than randomised so the shape does not change on every rebuild, which
  /// would read as content arriving and then moving.
  static Widget bubbles() {
    const plan = <({bool mine, double width, int lines})>[
      (mine: false, width: 0.62, lines: 2),
      (mine: true, width: 0.44, lines: 1),
      (mine: false, width: 0.50, lines: 1),
      (mine: true, width: 0.70, lines: 2),
      (mine: false, width: 0.38, lines: 1),
    ];
    return AppSkeleton(
      child: Builder(
        builder: (context) => ListView(
          // Matches the real transcript's padding so the first real bubble
          // lands where its placeholder sat.
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final b in plan)
              Align(
                alignment: b.mine
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  alignment: b.mine
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  widthFactor: b.width,
                  child: Container(
                    // 20px per line of body text, plus the bubble's 10px
                    // vertical padding top and bottom; the 22 of margin is the
                    // sender label and timestamp sitting outside the bubble.
                    height: 20.0 * b.lines + 20,
                    margin: const EdgeInsetsDirectional.only(bottom: 22),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).groundSunken,
                      // The asymmetric corner is what makes a rounded rectangle
                      // read as a speech bubble, and which corner is clipped is
                      // what says who sent it.
                      borderRadius: BorderRadiusDirectional.only(
                        topStart: const Radius.circular(16),
                        topEnd: const Radius.circular(16),
                        bottomStart: Radius.circular(b.mine ? 16 : 4),
                        bottomEnd: Radius.circular(b.mine ? 4 : 16),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Placeholder for a PROSE ARTICLE: a heading, then paragraphs of full-width
  /// lines each ending in a short ragged one.
  ///
  /// The ragged last line is the whole point — a block of equal-length bars
  /// reads as a table, not as text.
  static Widget paragraphs() {
    const plan = <({int lines, double lastWidth})>[
      (lines: 4, lastWidth: 0.45),
      (lines: 5, lastWidth: 0.70),
      (lines: 3, lastWidth: 0.34),
      (lines: 4, lastWidth: 0.58),
    ];
    return AppSkeleton(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 40),
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bone(height: 20, widthFactor: 0.55),
            const SizedBox(height: 18),
            for (final p in plan) ...[
              for (var i = 0; i < p.lines; i++)
                // 12 of bone under a 12 gap gives the same 24px rhythm as the
                // real body text (15px at a 1.6 line height).
                bone(
                  height: 12,
                  widthFactor: i == p.lines - 1 ? p.lastWidth : 1,
                  margin: const EdgeInsetsDirectional.only(bottom: 12),
                ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion: hold the bones at a steady opacity instead of pulsing.
    // The placeholder still communicates "not loaded yet" by existing.
    if (AppMotion.reduced(context)) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _pulse,
        child: widget.child,
        builder: (context, child) {
          return Opacity(opacity: 0.45 + (0.35 * _pulse.value), child: child);
        },
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.of(context).groundSunken,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// A designed empty state: mark, headline, explanation, and a way forward.
///
/// An empty state is content, not the absence of it. It is often a user's
/// first impression of a section, so it should explain what will appear here
/// and give them the action that makes it appear.
class AppEmpty extends StatelessWidget {
  const AppEmpty({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  /// Translated via `.tr`.
  final String title;

  /// Translated via `.tr`. Say what will appear here and why it is worth it.
  final String message;

  /// Translated via `.tr`.
  final String? actionLabel;

  final VoidCallback? onAction;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.lineStrong, width: 1.5),
              ),
              child: Icon(
                icon ?? Icons.inbox_rounded,
                size: 20,
                color: c.inkTertiary,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              title.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.heading,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: c.ink,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              message.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.dense,
                height: AppType.leadBody,
                color: c.inkSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.xl),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!.tr)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A failure with a cause and a way out.
///
/// Renders as a banner rather than a full-screen takeover so that any
/// last-known content passed as [staleContent] stays readable beneath it.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'error_title',
    this.retryLabel = 'retry',
    this.staleContent,
    this.gutter,
  });

  /// What went wrong and what to do, in plain language. Translated via `.tr`.
  ///
  /// Never pass a status code or an exception string here — the audit found
  /// raw `describeError(e)` output reaching users.
  final String message;

  /// Required, not optional. An error with no way out is a dead end, so the
  /// type system asks for the recovery path.
  final VoidCallback onRetry;

  final String title;
  final String retryLabel;

  /// Anything already loaded before the failure. Shown dimmed beneath the
  /// banner so an offline user keeps what they had.
  ///
  /// CALLER'S RESPONSIBILITY: this content is dimmed but still INTERACTIVE.
  /// It is only wrapped in [Opacity], which changes how it looks and nothing
  /// about what it does, so every button inside it still fires.
  ///
  /// That is deliberate — making it inert would need an [IgnorePointer], and
  /// that would also kill scrolling, which defeats the purpose of keeping the
  /// data readable in the first place.
  ///
  /// So a screen passing [staleContent] must gate any action that DECIDES
  /// something on the strength of the data that just failed to refresh. The
  /// case that prompted this note: the marriage subscription screen kept its
  /// package cards visible after a refresh failure, and their Subscribe
  /// buttons still opened a payment sheet that offered or refused the wallet
  /// based on a balance we had already admitted was stale. Reading stale data
  /// is fine; spending against it is not.
  final Widget? staleContent;

  /// Horizontal inset for the BANNER only.
  ///
  /// Deliberately not defaulted. Most callers sit inside a parent that already
  /// supplies the screen gutter, and giving this a default would push those to
  /// 40pt — the whole reason the alignment was inconsistent in the first place.
  /// It is set by [AppAsync.gutter], which is where the decision belongs,
  /// because that is the widget that knows whether the gutter lives in the
  /// parent or inside the content's own ListView.
  ///
  /// [staleContent] is NOT inset by this: it is the caller's own list, padding
  /// included, and insetting it here would indent it past where it sits when
  /// the load succeeds.
  final EdgeInsetsGeometry? gutter;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    final banner = Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.consequenceWash,
        border: Border.all(color: c.consequence),
        borderRadius: AppRadius.smAll,
      ),
      child: Column(
        // Without this the Column takes MainAxisSize.max and the banner grows
        // to whatever height it is given — inside an Expanded, which is how
        // most callers place AppAsync, that turned a two-line message into a
        // full-screen slab of error colour. Wrapping the banner in an Align
        // does NOT fix it; the Column has to be told to hug its children.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.tr,
            style: TextStyle(
              fontSize: AppType.dense,
              fontWeight: AppType.wLabel,
              color: c.consequence,
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            message.tr,
            style: TextStyle(
              fontSize: AppType.meta,
              height: AppType.leadDense,
              color: c.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          AppPressable(
            onTap: onRetry,
            semanticLabel: retryLabel.tr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  retryLabel.tr,
                  style: TextStyle(
                    fontSize: AppType.meta,
                    fontWeight: AppType.wLabel,
                    color: c.consequence,
                  ),
                ),
                const SizedBox(width: AppSpace.xxs),
                Icon(Icons.refresh_rounded, size: 14, color: c.consequence),
              ],
            ),
          ),
        ],
      ),
    );

    // Pinned to the TOP rather than returned bare. The banner is a Container
    // with no height of its own, so inside an Expanded — which is how most
    // callers place AppAsync — it stretched to fill the whole region, turning
    // a two-line message into a full-screen slab of error colour. Seen on the
    // City Guide, where it filled the entire map area.
    //
    // Align gives it its natural height and leaves the space below empty,
    // which also reads correctly: the region genuinely has no content.
    final insetBanner = gutter == null
        ? banner
        : Padding(padding: gutter!, child: banner);

    if (staleContent == null) {
      return Align(
        alignment: AlignmentDirectional.topCenter,
        child: insetBanner,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        insetBanner,
        const SizedBox(height: AppSpace.md),
        // Dimmed, not hidden: the data is real, just possibly out of date.
        Expanded(child: Opacity(opacity: 0.55, child: staleContent!)),
      ],
    );
  }
}

/// Renders exactly one of the four states, and will not compile without all
/// of them.
///
/// This is the point of the file. A screen using AppAsync cannot forget its
/// empty state, because [empty] is a required parameter — and cannot ship a
/// dead-end error, because [onRetry] is too.
///
/// ```dart
/// AppAsync<List<Campaign>>(
///   loading: controller.isLoading.value,
///   error: controller.error.value,
///   onRetry: controller.load,
///   data: controller.items,
///   isEmpty: (items) => items.isEmpty,
///   skeleton: AppSkeleton.rows(),
///   empty: const AppEmpty(title: 'no_campaigns', message: 'no_campaigns_body'),
///   builder: (items) => CampaignList(items),
/// )
/// ```
class AppAsync<T> extends StatelessWidget {
  const AppAsync({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.data,
    required this.isEmpty,
    required this.empty,
    required this.builder,
    this.skeleton,
    this.gutter,
  });

  /// True only for the FIRST load. A background refresh should leave this
  /// false so the list updates in place without flashing a skeleton — the
  /// console's `pollSilent` pattern, which is worth preserving.
  final bool loading;

  /// A user-facing message, or null when there is no error.
  final String? error;

  final VoidCallback onRetry;

  final T? data;

  final bool Function(T data) isEmpty;

  final Widget empty;

  final Widget Function(T data) builder;

  /// Defaults to [AppSkeleton.rows]. Pass a shape that matches this screen's
  /// real content where the default does not.
  final Widget? skeleton;

  /// The screen gutter, for screens that keep theirs INSIDE the content.
  ///
  /// WHY THIS IS NEEDED AT ALL
  /// A screen whose list carries `padding: fromLTRB(20, 0, 20, 28)` on its own
  /// ListView gives that gutter to the content and to nothing else, so the
  /// skeleton and the error banner render edge-to-edge while the rows that
  /// replace them sit in a 20pt margin. Screens that instead wrap the whole
  /// AppAsync in a Padding never had the problem. Both spellings are otherwise
  /// reasonable, which is why the app ended up with a mix of them.
  ///
  /// Pass this ONLY in the first case. Setting it on a screen that already
  /// wraps AppAsync in a Padding double-pads to 40.
  ///
  /// WHAT IT DOES AND DOES NOT TOUCH — measured, not assumed:
  ///   * the DEFAULT skeleton — inset. Renders at x=0 without this.
  ///   * a skeleton passed by the caller — NOT inset. [AppSkeleton.bubbles]
  ///     and [AppSkeleton.paragraphs] carry their own padding, matched to the
  ///     content they stand in for, so insetting them would double it. If you
  ///     pass a skeleton, you own its padding.
  ///   * error banner — inset. Renders at x=0 without this.
  ///   * empty — NOT inset. [AppEmpty] already carries [AppSpace.lg] of its
  ///     own, so insetting it here would make it the one state at 40.
  ///   * content — NOT inset. It owns the padding this parameter exists to
  ///     mirror; insetting it too would double it.
  final EdgeInsetsGeometry? gutter;

  @override
  Widget build(BuildContext context) {
    final value = data;

    if (error != null) {
      return AppErrorState(
        message: error!,
        onRetry: onRetry,
        gutter: gutter,
        // Keep whatever we already had on screen, dimmed.
        staleContent: value != null && !isEmpty(value) ? builder(value) : null,
      );
    }

    // An empty-but-non-null value counts as "nothing to show yet" here, not as
    // a finished empty result.
    //
    // This used to read `loading && value == null`, which quietly failed for
    // the common case of a screen whose list field starts as `const []` rather
    // than null: non-null defeated the skeleton branch, and empty then matched
    // the empty branch below, so the FIRST load rendered "nothing here yet"
    // instead of a skeleton. The screen looked answered before it had asked.
    //
    // Safe against the silent-refresh case: `loading` is true only for a first
    // load, and a refresh holding real rows keeps them via the branch below.
    if (loading && (value == null || isEmpty(value))) {
      // A caller-supplied skeleton is left exactly as given: the ones in this
      // file that are worth passing (bubbles, paragraphs) already carry the
      // padding of the content they imitate, and the point of passing one is
      // that the caller knows the shape better than this widget does.
      if (skeleton != null) return skeleton!;
      final bones = AppSkeleton.rows();
      return gutter == null ? bones : Padding(padding: gutter!, child: bones);
    }

    if (value == null || isEmpty(value)) return empty;

    return builder(value);
  }
}
