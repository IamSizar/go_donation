import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
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
  int _lastTickSlice = 0;
  final _random = Random();

  int get _slices => motivationalTasks.length;
  double get _sliceAngle => 2 * pi / _slices;

  @override
  void initState() {
    super.initState();
    // R2 #46 — a longer, softer deceleration (easeOutQuart over 5s) reads as
    // a real wheel losing momentum instead of a tween that stops abruptly.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..addListener(_onTick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _angle => _spinning ? _animation.value : _currentAngle;

  /// Which slice boundary has most recently passed the pointer.
  int _sliceUnderPointer(double angle) =>
      ((angle + _sliceAngle / 2) / _sliceAngle).floor();

  /// A light tick each time a slice passes the pointer, like a real wheel's
  /// flapper. Goes through AppHaptics, so the app's mute setting applies.
  void _onTick() {
    final slice = _sliceUnderPointer(_angle);
    if (slice != _lastTickSlice) {
      _lastTickSlice = slice;
      AppHaptics.selection();
    }
  }

  void _spin() {
    if (_spinning) return;
    final targetIndex = _random.nextInt(_slices);
    // Land the pointer (fixed at top) inside the target slice — not always
    // dead centre, which looks scripted — after several full turns.
    final jitter = (_random.nextDouble() - 0.5) * _sliceAngle * 0.6;
    final base = _currentAngle % (2 * pi);
    final landing = (2 * pi - targetIndex * _sliceAngle + jitter) % (2 * pi);
    var delta = landing - base;
    if (delta < 0) delta += 2 * pi;
    final turns = 5 + _random.nextInt(2);
    final end = _currentAngle + delta + turns * 2 * pi;
    _animation = Tween<double>(begin: _currentAngle, end: end).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppMotion.resolveCurve(context, Curves.easeOutQuart),
      ),
    );
    _lastTickSlice = _sliceUnderPointer(_currentAngle);
    setState(() => _spinning = true);
    _controller
      ..duration = AppMotion.reduced(context)
          ? const Duration(milliseconds: 600)
          : const Duration(milliseconds: 5000)
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        _currentAngle = end % (2 * pi);
        setState(() => _spinning = false);
        AppHaptics.success();
        _showResult(targetIndex);
      });
    AppHaptics.gentle();
  }

  void _showResult(int index) {
    showChallengeSheet(
      context,
      icon: wheelSliceIcons[index],
      task: motivationalTasks[index].tr,
    );
  }

  @override
  Widget build(BuildContext context) {
    // R2 #46 — no explanation subtitle (said once, by the button).
    return SectionScaffold(
      title: 'Wheel of Fortune',
      subtitle: '',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = min(constraints.maxWidth - 40, 340.0);
          return Column(
            children: [
              const Spacer(),
              SizedBox(
                width: size,
                height: size + 22,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: 22,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.30),
                              blurRadius: 30,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        // The painter draws the rotation itself (not a
                        // Transform), so labels can stay upright wherever
                        // the wheel stops.
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => CustomPaint(
                            size: Size.square(size),
                            painter: _WheelPainter(
                              rotation: _angle,
                              labels: motivationalTaskShortLabels
                                  .map((l) => l.tr)
                                  .toList(),
                              icons: wheelSliceIcons,
                              colors: wheelSliceColors,
                              rim: _kWheelRim,
                              textDirection: Directionality.of(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The hub carries the logo and does not rotate, so the
                    // brand mark always reads upright.
                    Positioned(
                      top: 22 + size / 2 - 36,
                      child: const _WheelHub(),
                    ),
                    Positioned(
                      top: 0,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          // The pointer kicks back as each divider passes it
                          // and settles as the wheel slows.
                          final frac =
                              ((_angle + _sliceAngle / 2) % _sliceAngle) /
                              _sliceAngle;
                          final kick = _spinning && frac < 0.35
                              ? -0.32 * (1 - frac / 0.35)
                              : 0.0;
                          return Transform.rotate(
                            angle: kick,
                            alignment: const Alignment(0, -0.6),
                            child: const _WheelPointer(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _spinning ? null : _spin,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      _spinning ? 'Spinning…'.tr : 'Spin the wheel'.tr,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// R2 #46 — the result card shared by the wheel and the coupon: the slice's
/// icon in a brand disc, «تحديك», the challenge, one button.
Future<void> showChallengeSheet(
  BuildContext context, {
  required IconData icon,
  required String task,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppThemeConfig.elevatedSurface(sheetContext),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppThemeConfig.border(sheetContext)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.of(sheetContext).accentWash,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 30,
                color: AppThemeConfig.accent(sheetContext),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your challenge'.tr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppThemeConfig.mutedText(sheetContext),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              task,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: AppThemeConfig.text(sheetContext),
              ),
            ),
            const SizedBox(height: 22),
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

/// The wheel's slice colours, in order.
///
/// R2 #46 — the client called the old eight-colour rainbow amateur. The
/// wheel now uses the brand's own four tones (deep green, ivory, the logo's
/// teal, mint), repeated so no two neighbouring slices match; thin white
/// dividers keep every slice distinct. Label ink is still picked per slice by
/// [wheelLabelInk] (see test/design/wheel_label_contrast_test.dart).
@visibleForTesting
const List<Color> wheelSliceColors = [
  Color(0xFF2F5D4A),
  Color(0xFFF3EFE4),
  Color(0xFF1F6F8B),
  Color(0xFF6FBF9C),
  Color(0xFF2F5D4A),
  Color(0xFFF3EFE4),
  Color(0xFF1F6F8B),
  Color(0xFF6FBF9C),
];

/// One icon per slice, same order as [motivationalTasks]. Also used by the
/// coupon's back face and the shared result sheet.
const List<IconData> wheelSliceIcons = [
  Icons.volunteer_activism_rounded,
  Icons.family_restroom_rounded,
  Icons.ios_share_rounded,
  Icons.campaign_rounded,
  Icons.category_rounded,
  Icons.group_add_rounded,
  Icons.chat_bubble_rounded,
  Icons.newspaper_rounded,
];

const Color _kWheelRim = Color(0xFF1B3A2E);

/// Whichever of white or [kInkDark] is actually readable on [slice].
@visibleForTesting
Color wheelLabelInk(Color slice) => inkOn(slice);

class _WheelHub extends StatelessWidget {
  const _WheelHub();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _kWheelRim, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/branding/tawazzn_icon.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _WheelPointer extends StatelessWidget {
  const _WheelPointer();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(34, 44),
      painter: _PointerPainter(AppThemeConfig.accent(context)),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.rotation,
    required this.labels,
    required this.icons,
    required this.colors,
    required this.rim,
    required this.textDirection,
  });

  final double rotation;
  final List<String> labels;
  final List<IconData> icons;
  final List<Color> colors;
  final Color rim;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final slices = labels.length;
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    const rimWidth = 12.0;
    final radius = outer - rimWidth;
    final sliceAngle = 2 * pi / slices;
    // Pointer is fixed at the top (12 o'clock / -90°); slice 0 is centred
    // under it.
    final first = -pi / 2 - sliceAngle / 2 + rotation;

    // Rim.
    canvas.drawCircle(center, outer, Paint()..color = rim);

    // Slices: flat brand colours, no gloss.
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < slices; i++) {
      canvas.drawArc(
        rect,
        first + i * sliceAngle,
        sliceAngle,
        true,
        Paint()..color = colors[i % colors.length],
      );
    }

    // Soft inner shade toward the rim gives depth without a rainbow sheen.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.10),
          ],
          const [0.75, 1.0],
        ),
    );

    // Dividers and the rim's studs, one per boundary.
    final divider = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2;
    final stud = Paint()..color = Colors.white;
    for (var i = 0; i < slices; i++) {
      final a = first + i * sliceAngle;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(center, center + dir * radius, divider);
      canvas.drawCircle(center + dir * (outer - rimWidth / 2), 3, stud);
    }

    // Icon near the rim and label inside it, both laid along the slice's
    // centre line and flipped on the left half so nothing on the left reads
    // upside down. Text uses the app's direction: drawing Arabic as LTR is
    // what broke the old labels' letter shapes.
    for (var i = 0; i < slices; i++) {
      final mid = first + i * sliceAngle + sliceAngle / 2;
      final ink = wheelLabelInk(colors[i % colors.length]);
      final flip = cos(mid) < -0.01;
      final side = flip ? -1.0 : 1.0;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(flip ? mid + pi : mid);

      final icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icons[i].codePoint),
          style: TextStyle(
            fontFamily: icons[i].fontFamily,
            package: icons[i].fontPackage,
            fontSize: 20,
            color: ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(
        canvas,
        Offset(side * radius * 0.83 - icon.width / 2, -icon.height / 2),
      );

      final band = radius * 0.46;
      final label = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      // Long labels shrink to fit the band instead of being cut off.
      final scale = min(1.0, band / label.width);
      canvas.translate(side * radius * 0.50, 0);
      canvas.scale(scale);
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.labels != labels ||
      oldDelegate.colors != colors ||
      oldDelegate.textDirection != textDirection;
}

/// Fixed pin marking the winning slice: a rounded drop in the brand accent
/// with a white edge, pointing down into the wheel.
class _PointerPainter extends CustomPainter {
  _PointerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w / 2;
    final path = Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * 0.36, h * 0.72, 0, h * 0.58, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..cubicTo(w, h * 0.58, w * 0.64, h * 0.72, w / 2, h)
      ..close();
    canvas.drawShadow(path, Colors.black, 4, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      Offset(w / 2, r),
      r * 0.32,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) =>
      oldDelegate.color != color;
}
