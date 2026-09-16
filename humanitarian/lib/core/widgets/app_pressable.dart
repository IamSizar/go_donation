// AppPressable — the app's tappable primitive.
//
// WHY THIS WIDGET EXISTS
// A design audit found `onTapDown` used exactly zero times across 169 Dart
// files, against 305 `onTap:` handlers. Every explicit tap in the app reacted
// on RELEASE. Material's InkWell partly covers that with its ripple (65 files
// use one), but 27 files used a bare GestureDetector, which draws nothing at
// all — those taps had no acknowledgement whatsoever until the action
// completed.
//
// That matters more than it sounds. Perceived responsiveness is set by the
// gap between the finger landing and the first pixel changing; once that gap
// is visible, the interface stops feeling direct no matter how fast the
// action behind it is.
//
// WHAT THIS DOES DIFFERENTLY
//   * Reacts on pointer-DOWN, within one frame.
//   * Scales to 0.97 — enough to read as a press, not enough to shift layout
//     (the scale is a paint-time transform, so nothing around it reflows).
//   * Releases on a SPRING, not a tween, so a rapid tap-tap-tap re-targets
//     from wherever the animation currently is instead of snapping back to
//     rest and starting over. This is the interruptibility the audit found
//     missing everywhere.
//   * Honours Reduce Motion: the scale is skipped entirely and the press is
//     signalled with opacity instead, which is non-vestibular.
//   * Enforces a 44×44 minimum touch target, expanding the hit area beyond
//     the visual bounds when the child is smaller.
//
// USAGE
//   AppPressable(
//     onTap: () => controller.submit(),
//     haptic: AppPressHaptic.success,   // only for genuine commits
//     child: const Text('Give now'),
//   )
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_application_1/core/design/motion.dart';

/// Which haptic, if any, a press should fire.
///
/// Deliberately an enum rather than a bool: the audit found the app already
/// had a good typed haptic vocabulary (`AppHaptics.gentle/selection/success/
/// error`) and the point is to keep naming feedback for WHAT HAPPENED rather
/// than for how strong it buzzes. Over-feedback trains people to ignore all
/// of it, so [none] is the default.
enum AppPressHaptic {
  /// No haptic. Correct for most taps — navigation, opening a sheet.
  none,

  /// A light tick. For selection changes: picking an amount, a chip, a tab.
  selection,

  /// A firmer confirmation. For genuine commits only: submitting a gift,
  /// confirming a form.
  success,
}

/// A tappable wrapper that gives immediate, interruptible press feedback.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = AppPressHaptic.none,
    this.pressedScale = 0.97,
    this.minTouchTarget = 44,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.behavior = HitTestBehavior.opaque,
    this.expand = false,
  });

  final Widget child;

  /// Fill the width offered by the parent instead of shrink-wrapping.
  ///
  /// Off by default. The touch target normally sizes to its child, so a 16pt
  /// icon gets a 44pt tap area rather than a full-width one — which is right
  /// almost everywhere. It is wrong inside an [Expanded] or a stretched
  /// [Column], where the caller has already decided the width and expects the
  /// pressable to honour it; set this there.
  final bool expand;

  /// Fires on release, inside the bounds — standard tap semantics. A null
  /// [onTap] with a null [onLongPress] renders the child inert (no press
  /// feedback), which is the correct appearance for a disabled control.
  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  /// Which haptic to fire on a completed tap. See [AppPressHaptic].
  final AppPressHaptic haptic;

  /// How far to scale down while held. 0.97 is Apple's rough house value —
  /// perceptible without being cartoonish.
  final double pressedScale;

  /// Minimum tappable square. The hit area is expanded to this even when the
  /// visible child is smaller, so small icons do not require precise aim.
  final double minTouchTarget;

  /// Announced by screen readers. Worth passing for anything icon-only: the
  /// audit found 29 IconButtons in the app and only 10 with any label at all.
  final String? semanticLabel;

  final bool excludeFromSemantics;

  final HitTestBehavior behavior;

  bool get _enabled => onTap != null || onLongPress != null;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable>
    with SingleTickerProviderStateMixin {
  /// Drives 0.0 (at rest) → 1.0 (fully pressed).
  ///
  /// Created eagerly in [initState] rather than with `late final`. A lazy
  /// field is only constructed on first read — and for an inert instance
  /// (null onTap) the first read is `dispose()`, which would construct a
  /// Ticker while the element is being torn down and throw "Looking up a
  /// deactivated widget's ancestor is unsafe". Eager creation costs nothing
  /// and removes the whole class of problem.
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController.unbounded(vsync: this, value: 0);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  /// Animates the press value toward [target] on a spring.
  ///
  /// `animateWith` starts the simulation from the controller's CURRENT value
  /// and velocity, which is what makes a press that arrives mid-release
  /// continue smoothly instead of jumping. A `Tween` + duration cannot do
  /// this — it would restart from wherever it happened to be, at zero
  /// velocity.
  void _springTo(double target) {
    if (AppMotion.reduced(context)) {
      // Reduce Motion: no spring, no overshoot, no scale. Jump the value so
      // the opacity treatment below still gives feedback.
      _press.value = target;
      return;
    }
    _press.animateWith(
      AppMotion.snap.simulate(
        from: _press.value,
        to: target,
        velocity: _press.velocity,
      ),
    );
  }

  /// Presses on the RAW POINTER event, not on `GestureDetector.onTapDown`.
  ///
  /// This distinction is the whole point of the widget. `onTapDown` is not
  /// dispatched when the finger lands — `TapGestureRecognizer` holds it until
  /// it either wins the gesture arena or hits `kPressTimeout` (100ms). So a
  /// press built on `onTapDown` can be up to a tenth of a second late, which
  /// is exactly the latency that makes an interface stop feeling direct.
  ///
  /// `Listener.onPointerDown` fires in the same frame as the touch. Tap
  /// SEMANTICS still come from the GestureDetector below — this only drives
  /// the visual.
  void _handlePointerDown(PointerDownEvent _) => _springTo(1);

  /// Releases on pointer-up regardless of whether the tap was recognised, so
  /// "press, slide away, lift" correctly returns to rest.
  void _handlePointerUp(PointerEvent _) => _springTo(0);

  void _handleTap() {
    switch (widget.haptic) {
      case AppPressHaptic.none:
        break;
      case AppPressHaptic.selection:
        HapticFeedback.selectionClick();
      case AppPressHaptic.success:
        HapticFeedback.mediumImpact();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    // An inert child still gets its touch target and semantics, just no
    // press animation and no gesture handlers.
    if (!widget._enabled) {
      return _withTouchTarget(_withSemantics(widget.child, enabled: false));
    }

    final reduced = AppMotion.reduced(context);

    final animated = AnimatedBuilder(
      animation: _press,
      // The child is built once and reused every frame — only the transform
      // above it is recomputed, so pressing never rebuilds the subtree.
      child: widget.child,
      builder: (context, child) {
        // Clamp because an under-damped spring can overshoot past 1.0, and a
        // scale below the target would read as a glitch.
        final t = _press.value.clamp(0.0, 1.0);

        if (reduced) {
          // Non-vestibular equivalent: a small opacity dip conveys the press
          // without any positional motion.
          return Opacity(opacity: 1 - (0.18 * t), child: child);
        }

        return Transform.scale(
          scale: 1 - ((1 - widget.pressedScale) * t),
          // Scaling about the centre keeps the element anchored where the
          // finger is rather than drifting toward a corner.
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          child: child,
        );
      },
    );

    // ORDER MATTERS — the touch target goes INSIDE the gesture handlers.
    //
    // It used to sit outside them, which built a 44pt box whose extra area was
    // DEAD: `Center` shrink-wraps its child, so the GestureDetector nested
    // within it only ever covered the child's own bounds. A 16pt icon measured
    // 44x44 to `tester.getSize` while rejecting every tap more than 8pt from
    // its centre — the constraint was real, the hit area was not. Wrapping the
    // padded box in the handlers instead makes the whole 44pt square live.
    //
    // The scale still wraps `animated` only, so the visual press is unchanged.
    return _withSemantics(
      // Listener drives the VISUAL (immediate, raw pointer events).
      // GestureDetector drives the SEMANTIC tap (arena-resolved, so it
      // still cooperates correctly with scrolling and other recognizers —
      // dragging a list that contains these must scroll, not tap).
      Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerUp,
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          child: _withTouchTarget(animated),
        ),
      ),
      enabled: true,
    );
  }

  Widget _withSemantics(Widget child, {required bool enabled}) {
    if (widget.excludeFromSemantics) {
      return ExcludeSemantics(child: child);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      // Merges the child's own text into one announcement, so a card with a
      // title and three metadata lines reads as a single button rather than
      // four disconnected fragments.
      container: true,
      child: child,
    );
  }

  Widget _withTouchTarget(Widget child) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.minTouchTarget,
        minHeight: widget.minTouchTarget,
      ),
      // widthFactor/heightFactor make Center shrink-wrap its child. That is
      // what keeps a small icon's tap area at 44pt instead of full-width, but
      // it also makes the pressable ignore an Expanded parent — hence the
      // opt-out.
      child: Center(
        widthFactor: widget.expand ? null : 1,
        heightFactor: 1,
        child: child,
      ),
    );
  }
}
