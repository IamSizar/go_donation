// notification_summary_card.dart — the hero card at the top of the alerts
// list: how many are unread, the two list-wide actions (mark all read, clear
// read), and the All / Unread / Read counts.
//
// MODULE MAP
//   • screens/notifications_screen.dart — the screen: the list, its four
//     states, and the filter row.
//   • widgets/notification_summary_card.dart (this file) —
//     NotificationSummaryCard and its private pieces (the ringing bell, the
//     stat pill).
//   • widgets/notification_tile.dart — one row of the list.
//
// Split out of the screen when the clear-read action was added (client report,
// 2026-09-16): the screen had already passed the 500-line limit and this is
// the piece of it with its own subject.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:get/get.dart';

import '../controllers/notifications_controller.dart';

/// Phase 27.1 — redesigned hero card.
///
/// Three states:
///   • unread > 0  → gradient card, animated bell + red dot, big "N new"
///     headline, "Mark all read" CTA. Bell ringing animation runs while
///     unread is non-zero (rocks left-right ~12° on a 1.6s loop).
///   • unread == 0 → softer gradient, static checkmark, "All caught up"
///     headline, no CTA.
///   • Below either state, a thin row of pills (All / Read / Unread)
///     keeps the previous quick-stat affordance.
class NotificationSummaryCard extends StatelessWidget {
  const NotificationSummaryCard({
    super.key,
    required this.controller,
    this.countsKnown = true,
  });

  final NotificationsController controller;

  /// False when the last load failed and nothing is cached, so the counts
  /// below are absences rather than zeros.
  final bool countsKnown;

  @override
  Widget build(BuildContext context) {
    final total = controller.notifications.length;
    final unread = controller.unreadCount;
    final read = total - unread;
    final hasUnread = countsKnown && unread > 0;

    // A single accent surface in both states. This was two hardcoded
    // gradients — brand-primary when unread, a raw 0xFF16A34A/0xFF22C55E green
    // pair when caught up — neither of which resolved through the token layer,
    // so neither adapted to dark mode. The unread/caught-up distinction is
    // already carried by the headline text and the bell-vs-check mark; it did
    // not need a second, redundant colour encoding.
    final surface = AppThemeConfig.accent(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Hero ----
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BellOrCheck(hasUnread: hasUnread, unreadCount: unread),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !countsKnown
                          ? 'Notifications'.tr
                          : hasUnread
                          ? '@n new'.trParams({'n': '$unread'})
                          : 'All caught up'.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppThemeConfig.onAccent(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !countsKnown
                          ? 'We could not check for new notifications.'.tr
                          : hasUnread
                          ? 'Tap any alert to open it.'.tr
                          : 'No unread notifications.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.onAccent(
                          context,
                        ).withValues(alpha: 0.88),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasUnread)
                Material(
                  color: AppThemeConfig.onAccent(
                    context,
                  ).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                  child: InkWell(
                    onTap: controller.markAllAsRead,
                    borderRadius: BorderRadius.circular(99),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.done_all_rounded,
                            size: 16,
                            color: AppThemeConfig.onAccent(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Mark all'.tr,
                            style: TextStyle(
                              color: AppThemeConfig.onAccent(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // ---- Clear-read action ----
        // Only shown when there is something to clear. The client asked that
        // old notifications go away; the server retires read rows older than
        // 30 days on its own (notify.List), and this is the same thing on
        // demand, for anybody who does not want to wait a month.
        //
        // Read rows only, and behind a confirm: an unread notification is one
        // the user has not seen, and losing a case update to a mis-tap is not
        // a trade this screen makes.
        if (countsKnown && read > 0) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _confirmClearRead(context, read),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text(
                'Clear @n read'.trParams({'n': '$read'}),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppThemeConfig.mutedText(context),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        // ---- Stat pills row ----
        Row(
          children: [
            Expanded(
              child: _StatPill(
                icon: Icons.inbox_rounded,
                label: 'All'.tr,
                value: total,
                known: countsKnown,
                accent: AppThemeConfig.accent(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatPill(
                icon: Icons.fiber_manual_record_rounded,
                label: 'Unread'.tr,
                value: unread,
                known: countsKnown,
                accent: hasUnread
                    ? AppThemeConfig.accent(context)
                    : AppThemeConfig.subtleText(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatPill(
                icon: Icons.mark_email_read_rounded,
                label: 'Read'.tr,
                value: read,
                known: countsKnown,
                accent: AppThemeConfig.subtleText(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Confirms, then clears — the platform's own dialog, destructive styling on
  /// the affirmative choice, and a success haptic once the rows are gone.
  Future<void> _confirmClearRead(BuildContext context, int read) async {
    final confirmed = await showAdaptiveConfirm(
      context,
      title: 'Clear read notifications?'.tr,
      message:
          'This removes @n read notifications from your list. Unread ones stay.'
              .trParams({'n': '$read'}),
      confirmLabel: 'Clear'.tr,
      cancelLabel: 'Cancel'.tr,
      isDestructive: true,
    );
    if (!confirmed) return;
    await controller.clearReadNotifications();
    AppHaptics.success();
  }
}

/// Bell that rocks left-right while unread > 0. When unread == 0, we
/// render a static check-circle on a translucent background instead.
class _BellOrCheck extends StatefulWidget {
  const _BellOrCheck({required this.hasUnread, required this.unreadCount});

  final bool hasUnread;
  final int unreadCount;

  @override
  State<_BellOrCheck> createState() => _BellOrCheckState();
}

class _BellOrCheckState extends State<_BellOrCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _swing;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    // Sine-ish wobble between -0.18 and +0.18 radians (~10°) so the bell
    // looks like it's gently ringing. Curve.easeInOut keeps the motion
    // smooth at the extremes; loop while unread > 0.
    _swing = Tween<double>(
      begin: -0.18,
      end: 0.18,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    // The swing is started from didChangeDependencies rather than here,
    // because deciding whether to swing at all requires MediaQuery, which is
    // not safe to read during initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSwing();
  }

  @override
  void didUpdateWidget(covariant _BellOrCheck old) {
    super.didUpdateWidget(old);
    _syncSwing();
  }

  /// Starts or stops the bell swing to match the unread state.
  ///
  /// Reduce Motion parks the bell instead of swinging it. A ±10° rotation
  /// repeating with reverse:true is a 3.2s cycle — a slow looping oscillation
  /// with no end condition, which is the specific shape the setting exists to
  /// suppress. The unread state is still conveyed: the badge count next to the
  /// bell carries it, so nothing is lost by holding still.
  void _syncSwing() {
    final shouldSwing = widget.hasUnread && !AppMotion.reduced(context);
    if (shouldSwing && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!shouldSwing && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0.5; // park at neutral
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppThemeConfig.onAccent(context).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (widget.hasUnread)
            AnimatedBuilder(
              animation: _swing,
              builder: (context, child) =>
                  Transform.rotate(angle: _swing.value, child: child),
              child: Icon(
                Icons.notifications_active_rounded,
                color: AppThemeConfig.onAccent(context),
                size: 30,
              ),
            )
          else
            Icon(
              Icons.check_circle_rounded,
              color: AppThemeConfig.onAccent(context),
              size: 30,
            ),
          // Red badge with count when unread > 0, capped at "99+".
          if (widget.hasUnread)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppThemeConfig.consequence(context),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: AppThemeConfig.onAccent(context),
                    width: 2,
                  ),
                ),
                child: Text(
                  widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact stat pill below the hero. icon + count + label.
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.known = true,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color accent;

  /// When false the count is UNKNOWN, not zero, and renders as an em dash.
  /// "0" would be a specific claim we cannot support after a failed load.
  final bool known;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  known ? '$value' : '—',
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
