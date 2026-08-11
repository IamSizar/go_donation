import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

/// Client note — "Status of Operations and Donations": a clear, colored
/// indicator for how much of a donation-funded operation has been delivered,
/// with the number shown inside the badge itself.
///   • Green  — fully delivered / complete (100%)
///   • Red    — nothing received yet (0%)
///   • Orange — partially received / still in progress (1-99%)
class OperationStatusBadge extends StatelessWidget {
  const OperationStatusBadge({
    super.key,
    required this.progress,
    this.size = 46,
  });

  /// 0.0 (nothing received) .. 1.0 (fully delivered).
  final double progress;
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

  String get _statusLabel {
    if (_clamped >= 1.0) return 'Delivered in full'.tr;
    if (_clamped <= 0.0) return 'Not received yet'.tr;
    return 'Partially received'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_clamped * 100).round();
    return Tooltip(
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
    );
  }
}

/// A pill variant (colored background + text) for contexts where a full
/// circular badge doesn't fit — e.g. next to a title on a narrow row.
class OperationStatusPill extends StatelessWidget {
  const OperationStatusPill({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final color = OperationStatusBadge.statusColor(context, progress);
    final pct = (clamped * 100).round();
    final label = clamped >= 1.0
        ? 'Complete'.tr
        : clamped <= 0.0
        ? 'Not received'.tr
        : 'In progress'.tr;
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
