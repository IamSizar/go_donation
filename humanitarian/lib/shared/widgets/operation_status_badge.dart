import 'package:flutter/material.dart';
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

  static const Color _green = Color(0xFF16A34A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _orange = Color(0xFFF59E0B);

  double get _clamped => progress.clamp(0.0, 1.0);

  Color get _color {
    if (_clamped >= 1.0) return _green;
    if (_clamped <= 0.0) return _red;
    return _orange;
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
          color: _color,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _color.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _clamped >= 1.0
            ? Icon(Icons.check_rounded, color: Colors.white, size: size * 0.52)
            : Text(
                '$pct%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
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
    final color = clamped >= 1.0
        ? OperationStatusBadge._green
        : clamped <= 0.0
        ? OperationStatusBadge._red
        : OperationStatusBadge._orange;
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
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
