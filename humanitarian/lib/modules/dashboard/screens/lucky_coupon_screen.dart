import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/data/motivational_tasks.dart';
import 'package:flutter_application_1/modules/dashboard/screens/wheel_of_fortune_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Client note — Quick Actions #4: "Scratch the Lucky Coupon". Tapping the
/// coupon reveals one of [motivationalTasks] at random. Self-contained
/// preview (no backend/reward system yet).
///
/// R2 #46 — the grey box / amber box looked amateur. The coupon is now a
/// ticket in the brand's colours (deep green face with the logo, ivory back)
/// and turns over in 3D to reveal the challenge. A real finger-scratch
/// effect is a separate request (#44, waiting for scope).
class LuckyCouponScreen extends StatefulWidget {
  const LuckyCouponScreen({super.key});

  @override
  State<LuckyCouponScreen> createState() => _LuckyCouponScreenState();
}

class _LuckyCouponScreenState extends State<LuckyCouponScreen>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  late final AnimationController _flip;
  int? _index;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_index != null || _flip.isAnimating) return;
    setState(() => _index = _random.nextInt(motivationalTasks.length));
    _flip
      ..duration = AppMotion.resolve(
        context,
        const Duration(milliseconds: 750),
      )
      ..forward(from: 0).whenComplete(AppHaptics.success);
    AppHaptics.gentle();
  }

  Future<void> _reset() async {
    if (_flip.isAnimating) return;
    AppHaptics.selection();
    await _flip.reverse();
    if (mounted) setState(() => _index = null);
  }

  @override
  Widget build(BuildContext context) {
    final revealed = _index != null;
    return SectionScaffold(
      title: 'Lucky Coupon',
      subtitle: '',
      child: Column(
        children: [
          const Spacer(),
          GestureDetector(
            onTap: _reveal,
            child: AnimatedBuilder(
              animation: _flip,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_flip.value);
                final angle = t * pi;
                final showBack = angle > pi / 2;
                // Lift slightly mid-turn so it feels picked up, not hinged.
                final lift = 1 + 0.06 * sin(t * pi);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(angle)
                    ..scaleByDouble(lift, lift, 1, 1),
                  child: showBack && _index != null
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(pi),
                          child: _CouponBack(index: _index!),
                        )
                      : const _CouponFront(),
                );
              },
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: revealed ? _reset : _reveal,
                icon: Icon(
                  revealed ? Icons.refresh_rounded : Icons.touch_app_rounded,
                ),
                label: Text(
                  revealed ? 'Try another coupon'.tr : 'Scratch the coupon'.tr,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _kCouponWidth = 300;
const double _kCouponHeight = 190;
const Color _kCouponGreen = Color(0xFF2F5D4A);
const Color _kCouponIvory = Color(0xFFF3EFE4);

/// Ticket outline: rounded corners plus a half-circle notch on each side.
class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper();

  @override
  Path getClip(Size size) {
    const notch = 14.0;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)),
      );
    final notches = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(0, size.height / 2), radius: notch),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width, size.height / 2),
          radius: notch,
        ),
      );
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _Ticket extends StatelessWidget {
  const _Ticket({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PhysicalShape(
      clipper: const _TicketClipper(),
      color: color,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      child: SizedBox(
        width: _kCouponWidth,
        height: _kCouponHeight,
        child: child,
      ),
    );
  }
}

class _CouponFront extends StatelessWidget {
  const _CouponFront();

  @override
  Widget build(BuildContext context) {
    return _Ticket(
      color: _kCouponGreen,
      child: Stack(
        children: [
          // A faint dotted perforation across the middle, like a real ticket.
          Positioned.fill(child: CustomPaint(painter: _PerforationPainter())),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/branding/tawazzn_icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Tap to scratch'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
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

class _CouponBack extends StatelessWidget {
  const _CouponBack({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final ink = inkOn(_kCouponIvory);
    return _Ticket(
      color: _kCouponIvory,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: _kCouponGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(
                wheelSliceIcons[index],
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your challenge'.tr,
              style: TextStyle(
                color: ink.withValues(alpha: 0.65),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              motivationalTasks[index].tr,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.10);
    // Fine dot grid as a subtle foil texture.
    for (var y = 12.0; y < size.height; y += 14) {
      for (var x = 12.0; x < size.width; x += 14) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
