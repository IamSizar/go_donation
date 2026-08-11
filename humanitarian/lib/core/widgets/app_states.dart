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
  final Widget? staleContent;

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

    if (staleContent == null) return banner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
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

  @override
  Widget build(BuildContext context) {
    final value = data;

    if (error != null) {
      return AppErrorState(
        message: error!,
        onRetry: onRetry,
        // Keep whatever we already had on screen, dimmed.
        staleContent: value != null && !isEmpty(value) ? builder(value) : null,
      );
    }

    if (loading && value == null) {
      return skeleton ?? AppSkeleton.rows();
    }

    if (value == null || isEmpty(value)) return empty;

    return builder(value);
  }
}
