// AppFigure — the headline number, and the pair beneath it.
//
// This is the app's signature element and the one place the brand name is
// doing work. Tawazon (توازن) means BALANCE, and the product's whole job is
// holding the person who gives and the person who receives on the same scale.
// So the home screen leads with one figure hanging off a heavy rule, and
// immediately pairs it with its counterweight.
//
// WHY A PAIR RATHER THAN ONE BIG NUMBER
// The old dashboard showed a single total. A single total is flattering and
// slightly dishonest: it folds unconfirmed money in with delivered money.
// Splitting it — 9 delivered / 3 awaiting confirmation — is both truer to how
// this system actually works (a donation is `registered` until staff confirm
// it, which is why a campaign can show less than donors have pledged) and
// more useful, because the pending count is the number a user can act on.
//
// TYPOGRAPHY
// The figure is set at 38pt in weight 300 — LIGHT, not bold. A large number
// does not need weight to dominate; it needs room. Negative tracking keeps
// the digits from drifting apart as they grow, and tabular figures stop the
// layout shifting when the value updates.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/tokens.dart';

/// The headline figure: a rule, a label, the number, and a caption.
class AppFigure extends StatelessWidget {
  const AppFigure({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.tone,
  });

  /// Small uppercase label above the number. Translated via `.tr`.
  final String label;

  /// The number itself, pre-formatted for the locale.
  ///
  /// This widget never formats. Arabic and Kurdish want Eastern Arabic
  /// numerals and locale-aware grouping, which is the caller's job — passing
  /// a raw int here would quietly render Latin digits to three quarters of
  /// the user base.
  final String value;

  /// A unit set small and quiet beside the number ("IQD", "hrs").
  /// Translated via `.tr`.
  final String? unit;

  /// A line beneath. Translated via `.tr`.
  final String? caption;

  /// Colours the rule and label. Null uses ink, which is correct for a
  /// neutral figure; pass a tone when the figure itself carries state.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accentColor = tone ?? c.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The heavy rule. This is the "balance beam" the figure hangs from,
        // and the only 1.5px line in the system.
        Container(height: 1.5, color: accentColor),
        const SizedBox(height: AppSpace.sm),
        Text(
          label.tr.toUpperCase(),
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: AppType.wLabel,
            letterSpacing: AppType.trackLabel,
            color: tone ?? c.inkTertiary,
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.display,
                  fontWeight: AppType.wDisplay,
                  letterSpacing: AppType.trackDisplay,
                  height: AppType.leadDisplay,
                  // Tabular so the layout does not jitter as the value
                  // changes — this number updates after every donation.
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: c.ink,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpace.xxs),
              Text(
                unit!.tr,
                style: TextStyle(
                  fontSize: AppType.dense,
                  fontWeight: FontWeight.w500,
                  color: c.inkSecondary,
                ),
              ),
            ],
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(
            caption!.tr,
            style: TextStyle(
              fontSize: AppType.meta,
              height: AppType.leadDense,
              color: c.inkSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Two figures side by side, split by a hairline — the counterweight to
/// [AppFigure].
///
/// Use it for genuinely paired quantities: delivered vs awaiting, given vs
/// received, done vs remaining. Do not use it as a generic two-column stat
/// grid; the whole point is that the two halves relate to each other.
class AppStatPair extends StatelessWidget {
  const AppStatPair({
    super.key,
    required this.startValue,
    required this.startLabel,
    required this.endValue,
    required this.endLabel,
    this.startTone,
    this.endTone,
    this.onStartTap,
    this.onEndTap,
  });

  /// Pre-formatted, for the same locale reason as [AppFigure.value].
  final String startValue;

  /// Translated via `.tr`.
  final String startLabel;

  final String endValue;
  final String endLabel;

  /// Colour for each figure. The commonest use is a neutral start and
  /// `pending` on the end, so unconfirmed money reads as unconfirmed.
  final Color? startTone;
  final Color? endTone;

  final VoidCallback? onStartTap;
  final VoidCallback? onEndTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: c.line),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Half(
                    value: startValue,
                    label: startLabel,
                    tone: startTone,
                    onTap: onStartTap,
                  ),
                ),
                // The divider between the halves. Directional, so it sits on
                // the correct side under RTL without any override.
                Container(width: 1, color: c.line),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppSpace.sm,
                    ),
                    child: _Half(
                      value: endValue,
                      label: endLabel,
                      tone: endTone,
                      onTap: onEndTap,
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

class _Half extends StatelessWidget {
  const _Half({
    required this.value,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final String value;
  final String label;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: AppType.heading,
              fontWeight: AppType.wBody,
              letterSpacing: -0.5,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: tone ?? c.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.tr,
            style: TextStyle(
              fontSize: AppType.label,
              height: AppType.leadDense,
              color: c.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
