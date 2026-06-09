import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:get/get.dart';

import '../../../api/profile_api.dart';
import '../../../api/registration_api.dart';
import '../../../core/app_state.dart';
import '../../../core/auth_navigation.dart';
import '../../../core/theme/app_theme_config.dart';
import '../../../routes/app_routes.dart';

/// Modern splash: mesh backdrop, glass hero, gradient wordmark, bottom shimmer bar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _meshController;
  late final AnimationController _orbitController;
  late final AnimationController _introController;
  late final AnimationController _barController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _timer = Timer(const Duration(milliseconds: 2400), _handleNavigation);
  }

  Future<void> _handleNavigation() async {
    final userId = sharedPreferences.getString('id_user');
    final accessToken = currentApiAccessToken();
    if ((userId != null && userId.isNotEmpty) &&
        (accessToken == null || accessToken.isEmpty)) {
      final restored = await ensureApiSession(expectedUserId: userId);
      if (!restored) {
        await sharedPreferences.remove('id_user');
        await sharedPreferences.remove('role_id');
        await sharedPreferences.remove('registration_status');
      }
    }
    final effectiveUserId = sharedPreferences.getString('id_user');
    String regStatus = '';
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      final id = int.tryParse(effectiveUserId);
      if (id != null && id > 0) {
        // Authoritative approval status (ungated endpoint; also refreshes
        // role_id). Drives where a returning user lands.
        final st = await fetchRegistrationStatus();
        if (st != null) {
          regStatus = (st['registration_status'] ?? '').toString();
        }
        // Best-effort profile prefs for approved users (403s while pending).
        final account = await fetchUserAccount(id);
        if (account != null) {
          await applyUserAccountToSharedPreferences(account);
        }
      }
    }

    if (!mounted) return;

    _meshController.stop();
    _orbitController.stop();
    _barController.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (effectiveUserId == null || effectiveUserId.isEmpty) {
        Get.offAllNamed(AppRoutes.welcome);
      } else {
        routeByRegistrationStatus(regStatus);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _meshController.dispose();
    _orbitController.dispose();
    _introController.dispose();
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final g1 = AppThemeConfig.heroGradient[0];
    final g2 = AppThemeConfig.heroGradient[1];

    final fadeIntro = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.1, 1, curve: Curves.easeOutCubic),
    );
    final slideIntro =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
        );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _SplashMeshBackdrop(
            controller: _meshController,
            isDark: isDark,
            accent: g1,
            accent2: g2,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.15,
                colors: [
                  Colors.transparent,
                  (isDark ? Colors.black : const Color(0xFF0F172A)).withValues(
                    alpha: isDark ? 0.45 : 0.06,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: fadeIntro,
              child: SlideTransition(
                position: slideIntro,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      _GlassHeroMark(
                        orbitController: _orbitController,
                        isDark: isDark,
                        g1: g1,
                        g2: g2,
                      ),
                      const SizedBox(height: 34),
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [g1, g2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: Text(
                          'Humanitarian Platform',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                                height: 1.05,
                                color: Colors.white,
                                fontSize: 32,
                              ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Spacer(flex: 3),
                      _ShimmerLoadingBar(
                        controller: _barController,
                        g1: g1,
                        g2: g2,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashMeshBackdrop extends StatelessWidget {
  const _SplashMeshBackdrop({
    required this.controller,
    required this.isDark,
    required this.accent,
    required this.accent2,
  });

  final AnimationController controller;
  final bool isDark;
  final Color accent;
  final Color accent2;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value * math.pi * 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(math.cos(t * 0.4) * 0.3, -1),
              end: Alignment(-math.sin(t * 0.35) * 0.25, 1.1),
              colors: isDark
                  ? const [
                      Color(0xFF040A12),
                      Color(0xFF0B1624),
                      Color(0xFF0F2235),
                    ]
                  : const [
                      Color(0xFFF0FDFA),
                      Color(0xFFEFF6FF),
                      Color(0xFFF8FAFC),
                    ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _glowOrb(
                Alignment(
                  -0.9 + math.sin(t) * 0.08,
                  -0.75 + math.cos(t * 0.9) * 0.06,
                ),
                240,
                accent.withValues(alpha: isDark ? 0.14 : 0.22),
              ),
              _glowOrb(
                Alignment(
                  0.85 - math.cos(t * 0.8) * 0.1,
                  -0.2 + math.sin(t * 0.7) * 0.08,
                ),
                200,
                accent2.withValues(alpha: isDark ? 0.12 : 0.18),
              ),
              _glowOrb(
                Alignment(
                  math.sin(t * 1.1) * 0.15,
                  0.82 - controller.value * 0.05,
                ),
                280,
                Colors.white.withValues(alpha: isDark ? 0.04 : 0.35),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _glowOrb(Alignment alignment, double size, Color color) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color, blurRadius: 90, spreadRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassHeroMark extends StatelessWidget {
  const _GlassHeroMark({
    required this.orbitController,
    required this.isDark,
    required this.g1,
    required this.g2,
  });

  final AnimationController orbitController;
  final bool isDark;
  final Color g1;
  final Color g2;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: orbitController,
      builder: (context, child) {
        final angle = orbitController.value * math.pi * 2;
        return SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: const Size(168, 168),
                  painter: _OrbitRingPainter(
                    color: g1,
                    stroke: 2.2,
                    startAngle: 0,
                    sweep: 2.1,
                    opacity: isDark ? 0.85 : 1,
                  ),
                ),
              ),
              Transform.rotate(
                angle: -angle * 0.85,
                child: CustomPaint(
                  size: const Size(148, 148),
                  painter: _OrbitRingPainter(
                    color: g2,
                    stroke: 1.8,
                    startAngle: 1.2,
                    sweep: 1.8,
                    opacity: isDark ? 0.75 : 0.95,
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.14 : 0.55,
                        ),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                Colors.white.withValues(alpha: 0.10),
                                Colors.white.withValues(alpha: 0.04),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.92),
                                Colors.white.withValues(alpha: 0.72),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: g1.withValues(alpha: isDark ? 0.2 : 0.12),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [g1, g2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: g2.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  _OrbitRingPainter({
    required this.color,
    required this.stroke,
    required this.startAngle,
    required this.sweep,
    required this.opacity,
  });

  final Color color;
  final double stroke;
  final double startAngle;
  final double sweep;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: opacity);
    canvas.drawArc(rect, startAngle, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.stroke != stroke ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.sweep != sweep ||
        oldDelegate.opacity != opacity;
  }
}

class _ShimmerLoadingBar extends StatelessWidget {
  const _ShimmerLoadingBar({
    required this.controller,
    required this.g1,
    required this.g2,
    required this.isDark,
  });

  final AnimationController controller;
  final Color g1;
  final Color g2;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final shift = controller.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final band = w * 0.42;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                      Positioned(
                        left: (w - band) * shift,
                        top: 0,
                        bottom: 0,
                        width: band,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                g1.withValues(alpha: 0),
                                g1,
                                g2,
                                g2.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
