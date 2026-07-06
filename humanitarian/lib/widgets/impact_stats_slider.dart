import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/stats_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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

  // Build the visible cards, dropping any zero-value metric so we never show a
  // sad "0 Volunteers" card. Order = most impressive first.
  List<_ImpactSlide> _buildSlides(ImpactStats s) {
    final all = <_ImpactSlide>[
      if (s.totalGiven > 0)
        _ImpactSlide(
          icon: Icons.payments_rounded,
          value: s.totalGiven.toDouble(),
          label: 'Total given',
          format: _money,
          gradient: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
        ),
      if (s.completedWorks > 0)
        _ImpactSlide(
          icon: Icons.workspace_premium_rounded,
          value: s.completedWorks.toDouble(),
          label: 'Completed works',
          format: _count,
          gradient: const [Color(0xFF4F46E5), Color(0xFF3B82F6)],
        ),
      if (s.grantors > 0)
        _ImpactSlide(
          icon: Icons.volunteer_activism_rounded,
          value: s.grantors.toDouble(),
          label: 'Grantors',
          format: _count,
          gradient: const [Color(0xFFF59E0B), Color(0xFFEA580C)],
        ),
      if (s.volunteers > 0)
        _ImpactSlide(
          icon: Icons.handshake_rounded,
          value: s.volunteers.toDouble(),
          label: 'Volunteers',
          format: _count,
          gradient: const [Color(0xFF0891B2), Color(0xFF06B6D4)],
        ),
      if (s.eligibles > 0)
        _ImpactSlide(
          icon: Icons.diversity_1_rounded,
          value: s.eligibles.toDouble(),
          label: 'Eligibles',
          format: _count,
          gradient: const [Color(0xFFDB2777), Color(0xFFF43F5E)],
        ),
    ];
    return all;
  }

  String _count(double v) => NumberFormat.decimalPattern().format(v.round());

  String _money(double v) =>
      '${NumberFormat.decimalPattern().format(v.round())} IQD';

  void _startAutoRotate() {
    _timer?.cancel();
    _timer = Timer.periodic(_rotateEvery, (_) {
      if (!mounted || !_pageController.hasClients || _slides.length < 2) return;
      final next = (_current + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
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
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
    final cardHeight = 94 + 59 * textScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.insights_rounded,
                size: 18, color: Color(0xFF14B8A6)),
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
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _current ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _current
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF0F766E).withValues(alpha: 0.25),
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
    required this.gradient,
  });

  final IconData icon;
  final double value;
  final String label;
  final String Function(double) format;
  final List<Color> gradient;
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.slide});

  final _ImpactSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: slide.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: slide.gradient.last.withValues(alpha: 0.35),
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
                color: Colors.white.withValues(alpha: 0.10),
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
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(slide.icon, color: Colors.white, size: 22),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
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
                        color: Colors.white.withValues(alpha: 0.92),
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
