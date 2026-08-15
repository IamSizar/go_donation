import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

/// What the number in an operation-status indicator actually measures.
///
/// WHY THIS EXISTS (K5)
/// The badge below has always said "Delivered in full" / "Partially received"
/// / "Not received yet". Both of its call sites fed it
/// `campaign.fundedProgress` — money raised ÷ goal — so a campaign that had
/// collected its whole target while distributing nothing showed a green disc
/// reading "تم التسليم بالكامل". The words were right about a quantity nobody
/// was passing in.
///
/// Making this REQUIRED is the fix, not a convenience: an implicit default is
/// precisely what allowed a funding number to inherit delivery words silently.
/// A call site now has to say what its ratio means, and the wording follows.
enum OperationStatusKind {
  /// How much of the aid has reached the family. Green at 100% means the
  /// operation is complete.
  delivery,

  /// How much of the money has been raised against the goal. Green at 100%
  /// means the campaign is funded — it says nothing about distribution.
  funding,
}

/// Client note — "Status of Operations and Donations": a clear, colored
/// indicator for how far an operation has progressed, with the number shown
/// inside the badge itself.
///   • Green  — complete (100%)
///   • Red    — not started (0%)
///   • Orange — partial / still in progress (1-99%)
///
/// The colour ramp is shared by both [OperationStatusKind]s; only the words
/// differ, because only the words make a claim.
class OperationStatusBadge extends StatelessWidget {
  const OperationStatusBadge({
    super.key,
    required this.progress,
    required this.kind,
    this.size = 46,
  });

  /// 0.0 (none) .. 1.0 (complete), interpreted per [kind].
  final double progress;

  /// What [progress] measures. Required — see [OperationStatusKind].
  final OperationStatusKind kind;

  final double size;

  double get _clamped => progress.clamp(0.0, 1.0);

  /// The delivery state, as a semantic token.
  ///
  /// These were hardcoded as #16A34A / #DC2626 / #F59E0B — a green, a red and
  /// an amber picked by eye, which is why a bright signal-green disc sat on a
  /// card whose palette is olive. The three states map exactly onto tokens the
  /// design system already defines, so they use those and adapt to dark mode
  /// for free.
  static Color statusColor(BuildContext context, double progress) {
    final c = progress.clamp(0.0, 1.0);
    if (c >= 1.0) return AppThemeConfig.accent(context); // settled
    if (c <= 0.0) return AppThemeConfig.consequence(context); // nothing yet
    return AppThemeConfig.pending(context); // in flight
  }

  String get _statusLabel => operationStatusLabel(_clamped, kind);

  @override
  Widget build(BuildContext context) {
    final pct = (_clamped * 100).round();
    // Semantics, not just the Tooltip. A tooltip needs a hover or a long
    // press, so on a phone this badge's STATE was carried by its colour and
    // nothing else — which fails the rule the suite pins for AppRow ("status
    // is a word, not colour alone") for exactly the users that rule protects.
    //
    // The percentage inside the disc is not a substitute: it says how far
    // along, not what state that counts as, and a colour-blind user reading
    // "40%" still cannot tell partially-received from overdue.
    //
    // The label is merged rather than replacing the child's own semantics, so
    // the percentage is still announced alongside it.
    return Semantics(
      label: _statusLabel,
      container: true,
      child: Tooltip(
        message: _statusLabel,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor(context, progress),
            border: Border.all(
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.35),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor(context, progress).withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: _clamped >= 1.0
              ? Icon(
                  Icons.check_rounded,
                  color: AppThemeConfig.onAccent(context),
                  size: size * 0.52,
                )
              : Text(
                  '$pct%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(context),
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.30,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The three-state wording for a [progress] of a given [kind].
///
/// One function, shared by the badge and the pill, so the disc on a card and
/// the pill on that card's detail page can never disagree about what the same
/// number means — they did not before, but only because two separate `switch`
/// blocks happened to be written the same day.
String operationStatusLabel(double progress, OperationStatusKind kind) {
  final c = progress.clamp(0.0, 1.0);
  return switch (kind) {
    OperationStatusKind.delivery when c >= 1.0 => 'Delivered in full'.tr,
    OperationStatusKind.delivery when c <= 0.0 => 'Not received yet'.tr,
    OperationStatusKind.delivery => 'Partially received'.tr,
    OperationStatusKind.funding when c >= 1.0 => 'Fully funded'.tr,
    OperationStatusKind.funding when c <= 0.0 => 'Not funded yet'.tr,
    OperationStatusKind.funding => 'Partially funded'.tr,
  };
}

/// A pill variant (colored background + text) for contexts where a full
/// circular badge doesn't fit — e.g. next to a title on a narrow row.
class OperationStatusPill extends StatelessWidget {
  const OperationStatusPill({
    super.key,
    required this.progress,
    required this.kind,
  });

  final double progress;

  /// What [progress] measures. Required — see [OperationStatusKind].
  final OperationStatusKind kind;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final color = OperationStatusBadge.statusColor(context, progress);
    final pct = (clamped * 100).round();
    // Was a second, shorter vocabulary ("Complete" / "In progress" / "Not
    // received") that made a different claim from the disc beside it. One
    // source of wording now, so the pill cannot drift from the badge.
    final label = operationStatusLabel(clamped, kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$pct%',
            style: TextStyle(
              color: AppThemeConfig.onAccent(context),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppThemeConfig.onAccent(context),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
