// AppRow — the list row that carries campaigns, donations, missions,
// partners, city places and marketplace products.
//
// WHY ONE ROW
// The audit counted 138 Cards and 274 Containers across the app, most of them
// hand-assembled per screen with their own padding, radius and shadow. That
// is why there were 23 border radii and 10+ shadow blur values: every list
// invented its own card.
//
// This replaces the card entirely. Rows are separated by a hairline instead
// of by elevation, which is calmer, denser, and removes the whole question of
// which shadow a given list should use.
//
// The trailing slot is deliberately narrow and right-aligned with tabular
// figures, because the commonest thing on the end of a row in this app is an
// amount, and a column of amounts is only scannable when the digits line up.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// Semantic status colours for [AppStatusTag].
enum AppStatusTone {
  /// Settled, confirmed, delivered.
  settled,

  /// In flight: unconfirmed money, an upcoming due date, pending review.
  pending,

  /// Needs attention, failed, urgent.
  attention,

  /// No colour — the default state needs no emphasis.
  neutral,
}

/// A single list row: title, metadata, optional progress, optional trailing.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.title,
    this.meta,
    this.onTap,
    this.trailing,
    this.progress,
    this.progressTone = AppStatusTone.settled,
    this.progressStart,
    this.progressEnd,
    this.showDivider = true,
    this.leading,
  });

  /// Translated via `.tr`.
  final String title;

  /// A supporting line — counts, dates, reference codes. Translated via `.tr`.
  final String? meta;

  final VoidCallback? onTap;

  /// The far end of the row. For money use [AppRowAmount].
  final Widget? trailing;

  /// 0.0–1.0. Draws a 2px rule beneath the row's text when non-null.
  final double? progress;

  /// Colours the filled part of [progress].
  final AppStatusTone progressTone;

  /// Labels under the progress rule — typically "6,400,000 of 10,000,000"
  /// and "64%". Both translated via `.tr`.
  final String? progressStart;
  final String? progressEnd;

  /// The hairline beneath the row. Turn off for the last row in a group.
  final bool showDivider;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    final content = Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: TextStyle(
                        fontSize: AppType.dense,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        height: AppType.leadDense,
                        color: c.ink,
                      ),
                    ),
                    if (meta != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta!.tr,
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
                const SizedBox(width: AppSpace.sm),
                trailing!,
              ],
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpace.xs),
            AppProgressRule(value: progress!, tone: progressTone),
            if (progressStart != null || progressEnd != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (progressStart ?? '').tr,
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: c.inkTertiary,
                      ),
                    ),
                  ),
                  Text(
                    (progressEnd ?? '').tr,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: c.inkTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );

    final row = onTap == null
        ? content
        : AppPressable(
            onTap: onTap,
            // A row is a big target already; scaling the whole thing reads as
            // a wobble, so keep the press subtle.
            pressedScale: 0.99,
            minTouchTarget: 0,
            child: content,
          );

    if (!showDivider) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Container(height: 1, color: c.line),
      ],
    );
  }
}

/// The 2px progress rule used inside [AppRow].
///
/// Deliberately a rule rather than a chunky bar: it reads as a measurement of
/// the row above it rather than as a separate component.
class AppProgressRule extends StatelessWidget {
  const AppProgressRule({
    super.key,
    required this.value,
    this.tone = AppStatusTone.settled,
    this.height = 2,
  });

  /// 0.0–1.0. Values outside are clamped rather than overflowing.
  final double value;
  final AppStatusTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      // Announces as a progress bar with a percentage rather than being
      // invisible to a screen reader.
      value: '${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: c.groundSunken,
          valueColor: AlwaysStoppedAnimation<Color>(_toneColor(c, tone)),
        ),
      ),
    );
  }
}

/// A small status word. Never colour alone — the word carries the meaning and
/// the colour reinforces it, so it still works in greyscale and for
/// colour-blind users.
class AppStatusTag extends StatelessWidget {
  const AppStatusTag({super.key, required this.label, required this.tone});

  /// Translated via `.tr`.
  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = _toneColor(c, tone);
    final bg = switch (tone) {
      AppStatusTone.settled => c.accentWash,
      AppStatusTone.pending => c.pendingWash,
      AppStatusTone.attention => c.consequenceWash,
      AppStatusTone.neutral => c.groundSunken,
    };

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpace.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.tr.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: AppType.wLabel,
          letterSpacing: 0.7,
          color: fg,
        ),
      ),
    );
  }
}

/// A right-aligned amount with an optional status tag beneath it.
///
/// Uses tabular figures so a column of these lines up regardless of the
/// digits — the single most useful thing you can do to a list of money.
class AppRowAmount extends StatelessWidget {
  const AppRowAmount({super.key, required this.amount, this.status, this.tone});

  /// Pre-formatted for the locale. This widget does not format — callers own
  /// that, because Arabic and Kurdish need Eastern Arabic numerals.
  final String amount;

  /// Translated via `.tr`.
  final String? status;
  final AppStatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          amount,
          style: TextStyle(
            fontSize: AppType.body,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: c.ink,
          ),
        ),
        if (status != null) ...[
          const SizedBox(height: AppSpace.xxs),
          AppStatusTag(label: status!, tone: tone ?? AppStatusTone.neutral),
        ],
      ],
    );
  }
}

Color _toneColor(AppColors c, AppStatusTone tone) => switch (tone) {
  AppStatusTone.settled => c.accent,
  AppStatusTone.pending => c.pending,
  AppStatusTone.attention => c.consequence,
  AppStatusTone.neutral => c.inkTertiary,
};
