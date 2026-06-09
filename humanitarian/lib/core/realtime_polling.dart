// Phase 27 — shared real-time polling mixin for GetxControllers.
//
// Why a mixin: a handful of controllers across donor / beneficiary /
// admin all want the same behavior — pull fresh state from the API
// every N seconds, pause when the app is backgrounded, swallow
// network errors so a flaky tower doesn't blow up the UI. Phase 25
// implemented this inline in two places (notifications + volunteer
// dashboard); this mixin DRYs that up so the rest of the app can
// adopt it with one line.
//
// Usage:
//
//   class MyDonationsController extends GetxController
//       with RealtimePollingMixin {
//     @override
//     Future<void> realtimePoll() => fetchMyDonations();
//
//     @override
//     void onInit() {
//       super.onInit();
//       fetchMyDonations();   // initial load
//       startPolling();       // then refresh every pollInterval
//     }
//   }
//
// realtimePoll() must be idempotent and swallow its own errors (or
// surface them via state). The mixin catches anything that escapes,
// but you'll typically want a useful state-error message instead of
// silent failure.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Lifecycle observer helper — kept separate so the mixin doesn't have
/// to declare itself as a WidgetsBindingObserver (which would force
/// every subclass to implement the full observer surface).
class _LifecycleProxy with WidgetsBindingObserver {
  _LifecycleProxy(this.onChange);
  final void Function(AppLifecycleState) onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}

mixin RealtimePollingMixin on GetxController {
  Timer? _pollTimer;
  _LifecycleProxy? _proxy;
  bool _pollInFlight = false;

  /// How often to poll. Override for slower-moving controllers.
  /// Default 5s matches the volunteer / notifications polling cadence.
  Duration get pollInterval => const Duration(seconds: 5);

  /// Implemented by the controller. Called every pollInterval AND
  /// immediately when the app resumes from background. Must be
  /// idempotent. Errors should be returned as state — don't throw.
  Future<void> realtimePoll();

  /// Call once from onInit() (after the initial fetch).
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _tick());
    _proxy ??= _LifecycleProxy(_onLifecycle);
    WidgetsBinding.instance.addObserver(_proxy!);
  }

  /// Manually stop polling (rarely needed — onClose handles it).
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_proxy != null) {
      WidgetsBinding.instance.removeObserver(_proxy!);
      _proxy = null;
    }
  }

  Future<void> _tick() async {
    // Dedupe: if a previous tick is still in flight (slow network),
    // skip this one. The next interval will retry.
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      await realtimePoll();
    } catch (_) {
      // Outermost safety net — realtimePoll should already swallow.
    } finally {
      _pollInFlight = false;
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Refresh immediately on return, then resume the periodic timer.
        _tick();
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(pollInterval, (_) => _tick());
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _pollTimer?.cancel();
        _pollTimer = null;
        break;
    }
  }

  @override
  void onClose() {
    stopPolling();
    super.onClose();
  }
}

/// Detect status transitions between two snapshots of the same list.
///
/// Useful pattern for "show a snackbar when admin approves my X":
///
///   final transitions = detectStatusTransitions(
///     items: donations,
///     keyOf: (d) => d.id.toString(),
///     statusOf: (d) => d.status,
///     previous: _lastSnapshot,
///   );
///   _lastSnapshot = {for (final d in donations) d.id.toString(): d.status};
///   for (final t in transitions) {
///     Get.snackbar('Update', 'Donation #${t.key} → ${t.toStatus}');
///   }
///
/// Returns transitions where `previous[key]` existed AND differs from the
/// new status — so the very first poll (when previous is empty) reports
/// nothing, which is what you want (those aren't "transitions", they're
/// initial state).
List<StatusTransition> detectStatusTransitions<T>({
  required Iterable<T> items,
  required String Function(T) keyOf,
  required String Function(T) statusOf,
  required Map<String, String> previous,
}) {
  final out = <StatusTransition>[];
  for (final item in items) {
    final k = keyOf(item);
    final s = statusOf(item);
    final old = previous[k];
    if (old != null && old != s) {
      out.add(StatusTransition(key: k, fromStatus: old, toStatus: s));
    }
  }
  return out;
}

/// One detected change: a row whose status moved from X to Y.
class StatusTransition {
  const StatusTransition({
    required this.key,
    required this.fromStatus,
    required this.toStatus,
  });

  final String key;
  final String fromStatus;
  final String toStatus;
}
