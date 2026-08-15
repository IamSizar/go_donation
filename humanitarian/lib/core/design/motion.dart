// Motion tokens — spring physics, and the accessibility switch that turns
// them off.
//
// WHY THIS FILE EXISTS
// The audit found zero `SpringSimulation`, `SpringDescription`,
// `ScrollSpringSimulation` or `FrictionSimulation` across 169 Dart files.
// Every animation in the app was a fixed-duration tween over a `Curves.ease*`
// curve, spread across 12 arbitrary durations (160…4200ms).
//
// That matters for one specific reason: a fixed-duration tween cannot be
// interrupted cleanly. It runs from a start value to an end value over
// wall-clock time and has no notion of its own velocity, so when a user grabs
// a moving element mid-flight the animation either has to finish first or
// restart from rest — a visible discontinuity. A spring re-targets from
// wherever it currently is, carrying its velocity with it, which is why
// physics-based motion is the enabling mechanism for interruptible UI rather
// than a stylistic preference.
//
// It also found `MediaQuery.disableAnimations` was never read, so a user with
// Reduce Motion enabled at the OS level still got the full animation set —
// including four `easeOutBack` overshoots, exactly the vestibular-trigger
// shape that setting exists to suppress.
//
// USAGE
//   controller.animateWith(AppMotion.settle.simulate(from: 0, to: 1));
//   final d = AppMotion.resolve(context, AppMotion.settleDuration);
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// One named spring, described the way a designer reasons about it rather
/// than in mass/stiffness/damping.
///
/// [dampingRatio] controls overshoot: 1.0 is critically damped (settles with
/// no bounce), below 1.0 overshoots. [response] is roughly how long the value
/// takes to reach its target, in seconds — it is NOT a duration, because a
/// spring has no fixed duration; settle time emerges from the parameters.
@immutable
class AppSpring {
  const AppSpring({
    required this.name,
    required this.dampingRatio,
    required this.response,
  });

  final String name;
  final double dampingRatio;
  final double response;

  /// The Flutter description for this spring.
  ///
  /// Mass is fixed at 1 and stiffness/damping are derived from the two
  /// designer-facing parameters, which is the same mapping the platform
  /// animation APIs use.
  SpringDescription get description {
    final stiffness = _stiffnessFor(response);
    return SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: stiffness,
      ratio: dampingRatio,
    );
  }

  /// A simulation running from [from] to [to], optionally inheriting the
  /// velocity of whatever gesture or animation preceded it.
  ///
  /// Passing the real release velocity is what removes the seam between a
  /// drag and the animation that follows it — the element keeps moving at the
  /// speed the finger left it at instead of restarting from rest.
  SpringSimulation simulate({
    required double from,
    required double to,
    double velocity = 0,
  }) {
    return SpringSimulation(description, from, to, velocity);
  }

  /// A stiffness that produces roughly [response] seconds to target for a
  /// unit mass: ω = 2π / response, k = ω².
  static double _stiffnessFor(double response) {
    final omega = (2 * 3.141592653589793) / response;
    return omega * omega;
  }
}

/// The app's three motion presets. Three, not twelve.
///
/// Pick by what caused the motion, not by how long you want it to take:
///   * the user tapped something          → [snap]
///   * the app is presenting or dismissing → [settle]
///   * the user flicked or threw something → [carry]
abstract final class AppMotion {
  /// Immediate feedback on a tap: press states, selection, toggles.
  /// Critically damped — a control that wobbles after you press it feels
  /// cheap.
  static const AppSpring snap = AppSpring(
    name: 'snap',
    dampingRatio: 1.0,
    response: 0.25,
  );

  /// Presenting and dismissing: sheets, page pushes, expanding sections.
  /// Still critically damped, just less urgent.
  static const AppSpring settle = AppSpring(
    name: 'settle',
    dampingRatio: 1.0,
    response: 0.4,
  );

  /// Motion that follows a gesture carrying momentum — a flicked card, a
  /// thrown sheet. This is the ONLY preset with overshoot, and it is
  /// deliberate: bounce reads as physical when the user's own gesture put the
  /// energy there, and reads as decoration when it didn't.
  static const AppSpring carry = AppSpring(
    name: 'carry',
    dampingRatio: 0.8,
    response: 0.4,
  );

  // Duration equivalents, for the implicit widgets (AnimatedContainer,
  // AnimatedOpacity) that take a Duration rather than a simulation. Keep
  // these in step with the springs above so the app has one rhythm.
  static const Duration snapDuration = Duration(milliseconds: 180);
  static const Duration settleDuration = Duration(milliseconds: 300);
  static const Duration carryDuration = Duration(milliseconds: 380);

  /// Whether the user has asked the system to reduce motion.
  ///
  /// Reduce Motion does not mean "no feedback" — it means no large positional
  /// or vestibular motion. Cross-fades, colour changes and opacity are still
  /// appropriate and still aid comprehension.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Collapses a duration to zero when Reduce Motion is on.
  ///
  /// Wrap every implicit animation's duration in this. It is the cheapest
  /// possible way to honour the setting app-wide:
  ///
  ///   AnimatedContainer(duration: AppMotion.resolve(context, AppMotion.snapDuration), …)
  static Duration resolve(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Replaces an overshooting curve with a flat one under Reduce Motion.
  ///
  /// Only relevant for the implicit-widget path; the spring presets above
  /// should be gated with [reduced] and skipped entirely instead.
  static Curve resolveCurve(BuildContext context, Curve curve) =>
      reduced(context) ? Curves.linear : curve;
}
