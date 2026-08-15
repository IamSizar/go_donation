// The اللعبة hub — one door to both of the app's games.
//
// WHY THIS SCREEN EXISTS (J6)
// [WheelOfFortuneScreen] and [LuckyCouponScreen] were both finished and
// working, but the only thing in the app that navigated to either of them was
// the quick-actions panel on the donor Home (lib/widgets/dashboard.dart). That
// panel is rendered for the donor role alone, so a recipient, a volunteer or a
// marriage user had no route to the games at all — which is why the client
// still read اللعبة as missing from the eleven-entry profile menu.
//
// The client asked for ONE menu entry ("اللعبة"), and there are two games, so
// the entry lands here and this screen offers both. It adds no new game logic
// and no new vocabulary: every string on it already existed in all four
// locales for the two screens it links to.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/modules/dashboard/screens/lucky_coupon_screen.dart';
import 'package:flutter_application_1/modules/dashboard/screens/wheel_of_fortune_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      // Empty subtitle: each card below carries the one-line explanation of
      // its own game, so a hub-level sentence would only repeat them.
      title: 'Game',
      subtitle: '',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          _GameCard(
            icon: Icons.casino_rounded,
            titleKey: 'Wheel of Fortune',
            descriptionKey:
                'Spin the wheel for a motivational giving challenge.',
            onTap: () => Get.to(() => const WheelOfFortuneScreen()),
          ),
          const SizedBox(height: 12),
          _GameCard(
            icon: Icons.card_giftcard_rounded,
            titleKey: 'Lucky Coupon',
            descriptionKey:
                'Scratch the coupon for a motivational giving challenge.',
            onTap: () => Get.to(() => const LuckyCouponScreen()),
          ),
        ],
      ),
    );
  }
}

/// One game: its icon, its name and what playing it does.
///
/// No async work happens on this screen — both destinations are self-contained
/// and hold their own state — so there is no loading/error/empty state to
/// design here. The four-state rule applies to async regions; this list is a
/// fixed two.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
    required this.onTap,
  });

  final IconData icon;
  final String titleKey;
  final String descriptionKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeConfig.accent(context);
    return AppPressable(
      onTap: onTap,
      // Opening a screen is navigation, not a commit, so a light tick is the
      // right amount of feedback (see AppPressHaptic's doc comment).
      haptic: AppPressHaptic.selection,
      child: GlassPanel(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleKey.tr,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descriptionKey.tr,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
