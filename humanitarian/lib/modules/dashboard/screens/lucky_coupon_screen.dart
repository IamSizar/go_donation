import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/data/motivational_tasks.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/design/motion.dart';

/// Client note — Quick Actions #4: "Scratch the Lucky Coupon". Tapping the
/// coupon reveals one of [motivationalTasks] at random. Self-contained
/// preview (no backend/reward system yet) — added now so the entry point
/// exists ahead of the full feature.
class LuckyCouponScreen extends StatefulWidget {
  const LuckyCouponScreen({super.key});

  @override
  State<LuckyCouponScreen> createState() => _LuckyCouponScreenState();
}

class _LuckyCouponScreenState extends State<LuckyCouponScreen> {
  final _random = Random();
  String? _revealedTask;

  void _scratch() {
    if (_revealedTask != null) return;
    setState(() {
      _revealedTask =
          motivationalTasks[_random.nextInt(motivationalTasks.length)].tr;
    });
  }

  void _reset() => setState(() => _revealedTask = null);

  @override
  Widget build(BuildContext context) {
    final revealed = _revealedTask != null;
    return SectionScaffold(
      title: 'Lucky Coupon',
      subtitle: 'Scratch the coupon for a motivational giving challenge.',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _scratch,
              child: AnimatedSwitcher(
                duration: AppMotion.resolve(context, AppMotion.carryDuration),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: revealed
                    ? _RevealedCard(
                        key: const ValueKey('revealed'),
                        task: _revealedTask!,
                      )
                    : const _ScratchCard(key: ValueKey('hidden')),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: revealed ? _reset : _scratch,
                icon: Icon(
                  revealed ? Icons.refresh_rounded : Icons.touch_app_rounded,
                ),
                label: Text(
                  revealed ? 'Try another coupon'.tr : 'Scratch the coupon'.tr,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScratchCard extends StatelessWidget {
  const _ScratchCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 180,
      decoration: BoxDecoration(
        color: Color(0xFF6B7280),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.card_giftcard_rounded,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            'Tap to scratch'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// The revealed coupon's fill. The same amber the wheel uses, deliberately —
/// the two games share a "prize" colour.
const Color _kCouponAmber = Color(0xFFF59E0B);

class _RevealedCard extends StatelessWidget {
  const _RevealedCard({super.key, required this.task});

  final String task;

  @override
  Widget build(BuildContext context) {
    // The challenge was white on the amber: 2.15:1, measured from the rendered
    // pixels of the wheel's identically-coloured slice. At 16px w800 this is
    // still ordinary text — WCAG's large-text allowance starts at 18.66px bold
    // — so 4.5:1 applies and white missed it by more than half. The fill is the
    // reward's identity and stays; the ink flips. The icon flips with it: it
    // sits in the same column, and a white icon over dark text reads as a bug.
    final ink = inkOn(_kCouponAmber);
    return Container(
      width: 280,
      height: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCouponAmber,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_rounded, color: ink, size: 32),
          const SizedBox(height: 10),
          Text(
            task,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
