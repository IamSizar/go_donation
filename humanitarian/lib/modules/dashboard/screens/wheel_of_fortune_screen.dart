import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/motivational_tasks.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Client note — Quick Actions #4: "Wheel of Fortune". Spinning the wheel
/// lands on one of [motivationalTasks] at random and shows it as a
/// motivational challenge. Self-contained preview (no backend/reward system
/// yet) — added now so the entry point exists ahead of the full feature.
class WheelOfFortuneScreen extends StatefulWidget {
  const WheelOfFortuneScreen({super.key});

  @override
  State<WheelOfFortuneScreen> createState() => _WheelOfFortuneScreenState();
}

class _WheelOfFortuneScreenState extends State<WheelOfFortuneScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _currentAngle = 0;
  bool _spinning = false;
  final _random = Random();

  int get _slices => motivationalTasks.length;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spin() {
    if (_spinning) return;
    final sliceAngle = 2 * pi / _slices;
    final targetIndex = _random.nextInt(_slices);
    // Land the pointer (fixed at top) in the middle of the target slice,
    // after several full extra turns for a satisfying spin.
    final targetAngle =
        -(targetIndex * sliceAngle + sliceAngle / 2) + (6 * 2 * pi);
    _animation = Tween<double>(
      begin: _currentAngle,
      end: _currentAngle + targetAngle,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    setState(() => _spinning = true);
    _controller
      ..reset()
      ..forward().whenComplete(() {
        _currentAngle = (_currentAngle + targetAngle) % (2 * pi);
        setState(() => _spinning = false);
        _showResult(targetIndex);
      });
  }

  void _showResult(int index) {
    final task = motivationalTasks[index].tr;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppThemeConfig.elevatedSurface(sheetContext),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppThemeConfig.border(sheetContext)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.celebration_rounded,
                color: Color(0xFFF59E0B),
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'Your challenge'.tr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppThemeConfig.mutedText(sheetContext),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                task,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(sheetContext),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text('Got it'.tr),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Wheel of Fortune',
      subtitle: 'Spin the wheel for a motivational giving challenge.',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            SizedBox(
              width: 300,
              height: 306,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 26,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final angle = _spinning
                            ? _animation.value
                            : _currentAngle;
                        return Transform.rotate(angle: angle, child: child);
                      },
                      // THE BUG THIS FIXES: the wheel used to sit directly in
                      // the Stack with no shadow of its own, so against a
                      // flat background it read as a printed sticker, not an
                      // object. A circular drop shadow underneath — offset
                      // down, soft, dark — is what actually sells "floating
                      // disc" instead of "flat art".
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: -4,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          size: const Size(280, 280),
                          painter: _WheelPainter(
                            labels: motivationalTaskShortLabels
                                .map((l) => l.tr)
                                .toList(),
                            colors: wheelSliceColors,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Fixed pointer (does not rotate) — marks the winning slice
                  // at the top of the wheel.
                  Positioned(
                    top: 0,
                    child: CustomPaint(
                      size: const Size(36, 34),
                      painter: _PointerPainter(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // THE BUG THIS FIXES: this button was full-bleed edge-to-edge
            // (SectionScaffold's child has no side padding of its own here),
            // unlike every other action button in the app. 20px matches the
            // page gutter used everywhere else.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _spinning ? null : _spin,
                  icon: const Icon(Icons.casino_rounded),
                  label: Text(
                    _spinning ? 'Spinning…'.tr : 'Spin the wheel'.tr,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wheel's slice colours, in order.
///
/// A saturated rainbow, and deliberately KEPT that way. It is the one place the
/// app leaves its single-accent palette, because a fortune wheel's segment
/// colours are what make it legible AS a wheel — eight tints of the brand green
/// would be eight slices nobody could tell apart, which is the whole affordance
/// gone. The legibility problem the rainbow caused is fixed in [wheelLabelInk],
/// which changes the text and leaves every hue alone.
@visibleForTesting
const List<Color> wheelSliceColors = [
  Color(0xFF2F5D4A),
  Color(0xFFF59E0B),
  Color(0xFFDB2777),
  Color(0xFF4F46E5),
  Color(0xFF16A34A),
  Color(0xFFDC2626),
  Color(0xFF0891B2),
  Color(0xFFEA580C),
];

/// Whichever of white or [kInkDark] is actually readable on [slice].
///
/// The labels were all white. On a rainbow that does not work: white measured
/// 2.15:1 on the amber slice — below even the 3:1 floor for non-text UI, never
/// mind the 4.5:1 this 12px bold text needs — plus 3.30:1 on green, 3.56:1 on
/// orange and 3.68:1 on cyan. Four of eight slices carried labels that could
/// not be read.
///
/// Picking the ink per slice fixes all four WITHOUT touching a single hue, and
/// keeping the hues is the point: the segment colours are what make the thing
/// read as a fortune wheel at all. See test/design/wheel_label_contrast_test.dart.
@visibleForTesting
Color wheelLabelInk(Color slice) => inkOn(slice);

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.labels, required this.colors});

  final List<String> labels;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final slices = labels.length;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sliceAngle = 2 * pi / slices;
    // Pointer is fixed at the top (12 o'clock / -90°); start slices there too.
    var startAngle = -pi / 2 - sliceAngle / 2;
    // THE BUG THIS FIXES: flat Paint()..color per slice is exactly what made
    // this read as a printed sticker — a real physical wheel catches light
    // unevenly across its face. A radial gradient from a lightened center to
    // the base hue at the rim gives each slice a subtle dome/bulge instead
    // of a flat fill, without changing the hue that makes the slice
    // identifiable.
    for (var i = 0; i < slices; i++) {
      final base = colors[i % colors.length];
      final hsl = HSLColor.fromColor(base);
      final highlight = hsl
          .withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0))
          .toColor();
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, radius, [highlight, base], [
          0.0,
          1.0,
        ]);
      canvas.drawArc(rect, startAngle, sliceAngle, true, paint);
      startAngle += sliceAngle;
    }

    // Glassy highlight sweeping the upper-left quadrant — the same trick a
    // physical glossy disc shows under a single light source. Purely
    // additive over the slice gradients above, so it never fights their hue
    // or the label contrast math below (which reads `colors`, not the
    // painted pixels).
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    canvas.drawRect(
      Rect.fromCircle(center: center, radius: radius),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(center.dx - radius * 0.35, center.dy - radius * 0.4),
          radius * 1.1,
          [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.0)],
          [0.0, 0.6],
        ),
    );
    canvas.restore();

    // Metallic-looking bezel: a wider soft ring rather than the old 3px flat
    // stroke, so the rim itself reads as a raised edge, not a page divider.
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..shader = ui.Gradient.sweep(center, [
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.25),
        ], const [0.0, 0.25, 0.5, 1.0])
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Slice labels, drawn radially (from ~30% to ~85% of the radius) so each
    // one points from center to rim. Flipped for the left half of the wheel
    // so the text always reads upright, never upside down.
    startAngle = -pi / 2 - sliceAngle / 2;
    for (var i = 0; i < slices; i++) {
      final midAngle = startAngle + sliceAngle / 2;
      final ink = wheelLabelInk(colors[i % colors.length]);
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            // The halo lifts the label off the slice, so it has to oppose the
            // ink: a black shadow under dark text just muddies it.
            shadows: [
              Shadow(
                color: ink == Colors.white
                    ? Colors.black45
                    : Colors.white.withValues(alpha: 0.45),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.52);

      final flip = cos(midAngle) < 0;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(flip ? midAngle + pi : midAngle);
      final startX = radius * 0.32;
      final endX = radius * 0.86;
      final dx = flip ? -endX : startX;
      textPainter.paint(canvas, Offset(dx, -textPainter.height / 2));
      canvas.restore();
      startAngle += sliceAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.labels != labels || oldDelegate.colors != colors;
}

/// Fixed downward-pointing triangle marking the winning slice at the top of
/// the (rotating) wheel.
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFF0F172A));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) => false;
}
