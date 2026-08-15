import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/stats_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/core/design/motion.dart';

/// Auto-rotating "Our impact" carousel shown near the top of the home tab.
///
/// Fetches the public aggregate numbers (grantors / eligibles / volunteers /
/// completed works / total given) once, then cycles through them on gradient
/// cards with a count-up animation and a dots indicator. It manages its own
/// data and hides itself entirely while loading, on error, or when every number
/// is zero — so it never shows an empty or broken state to the user.
class ImpactStatsSlider extends StatefulWidget {
  const ImpactStatsSlider({super.key});

  @override
  State<ImpactStatsSlider> createState() => _ImpactStatsSliderState();
}

class _ImpactStatsSliderState extends State<ImpactStatsSlider> {
  static const Duration _rotateEvery = Duration(seconds: 4);

  final PageController _pageController = PageController();
  Timer? _timer;
  List<_ImpactSlide> _slides = const [];
  int _current = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await fetchImpactStats();
    if (!mounted) return;
    final slides = stats == null ? const <_ImpactSlide>[] : _buildSlides(stats);
    setState(() {
      _slides = slides;
      _loaded = true;
    });
    if (_slides.length > 1) _startAutoRotate();
  }

  // Client note — the home banner slider shows exactly 3 headline numbers:
  // grantors, beneficiaries, completed activities. Dropping any zero-value
  // metric so we never show a sad "0 Grantors" card.
  List<_ImpactSlide> _buildSlides(ImpactStats s) {
    final all = <_ImpactSlide>[
      if (s.grantors > 0)
        _ImpactSlide(
          icon: Icons.volunteer_activism_rounded,
          value: s.grantors.toDouble(),
          label: 'Grantors'.tr,
          format: _count,
        ),
      if (s.eligibles > 0)
        _ImpactSlide(
          icon: Icons.diversity_1_rounded,
          value: s.eligibles.toDouble(),
          label: 'Beneficiaries'.tr,
          format: _count,
        ),
      if (s.completedWorks > 0)
        _ImpactSlide(
          icon: Icons.workspace_premium_rounded,
          value: s.completedWorks.toDouble(),
          label: 'Completed activities'.tr,
          format: _count,
        ),
    ];
    return all;
  }

  String _count(double v) => NumberFormat.decimalPattern().format(v.round());

  void _startAutoRotate() {
    _timer?.cancel();
    _timer = Timer.periodic(_rotateEvery, (_) {
      if (!mounted || !_pageController.hasClients || _slides.length < 2) return;
      final next = (_current + 1) % _slides.length;
      // The Home tab can be kept alive off-screen (e.g. behind an
      // IndexedStack) so `mounted` stays true even while this widget is
      // briefly deactivated during tab/navigation transitions. Animating the
      // PageController in that window throws (framework asserts the element
      // is active), which otherwise goes uncaught and stalls the frame.
      try {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOutCubic,
        );
      } catch (_) {
        // Skip this rotation tick; the next timer fire will retry.
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide entirely while loading, on error, or when there's nothing to show.
    if (!_loaded || _slides.isEmpty) return const SizedBox.shrink();

    // Size the card to the (clamped) text scale so the fixed-height PageView can
    // never RenderFlex-overflow — including large accessibility text sizes and
    // taller Arabic/Kurdish glyphs. Fixed chrome (icon chip + paddings) ≈ 94px;
    // the number+label text block (≈ 59px at 1.0×) grows with the scale.
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.3);
    final cardHeight = 94 + 59 * textScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.insights_rounded,
              size: 18,
              color: AppThemeConfig.accent(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Our impact'.tr,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppThemeConfig.text(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SizedBox(
            height: cardHeight,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => _ImpactCard(slide: _slides[i]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.settleDuration),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _current ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _current
                      ? AppThemeConfig.accent(context)
                      : AppThemeConfig.accent(context).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ImpactSlide {
  const _ImpactSlide({
    required this.icon,
    required this.value,
    required this.label,
    required this.format,
  });

  final IconData icon;
  final double value;
  final String label;
  final String Function(double) format;
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.slide});

  final _ImpactSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // One accent for every slide. The metrics are told apart by their
        // icon, number and label; giving each its own hue made colour mean
        // "which statistic" instead of meaning anything about state, and put
        // an amber, a magenta and an indigo card on a screen whose palette
        // contains none of them.
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.accent(context).withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Decorative translucent circle for depth.
          Positioned(
            right: -26,
            top: -26,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppThemeConfig.onAccent(context).withValues(alpha: 0.10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppThemeConfig.onAccent(
                      context,
                    ).withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    slide.icon,
                    color: AppThemeConfig.onAccent(context),
                    size: 22,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: slide.value),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(
                        slide.format(v),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppThemeConfig.onAccent(context),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slide.label.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppThemeConfig.onAccent(
                          context,
                        ).withValues(alpha: 0.92),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
