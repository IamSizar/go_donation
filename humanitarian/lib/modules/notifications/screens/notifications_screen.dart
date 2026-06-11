import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import '../controllers/notifications_controller.dart';
import '../widgets/notification_tile.dart';

class NotificationsScreen extends GetView<NotificationsController> {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: 'Notifications'),
            ),
            Expanded(
              child: Obx(() {
                final items = controller.filteredNotifications;
                // Only show the full-screen spinner on the very first load,
                // when there's nothing to display yet. Once the list exists,
                // background polls update it in place without ever swapping it
                // out for a spinner (which read as an ugly reload every ~5s).
                if (controller.isLoading.value &&
                    controller.notifications.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final error = controller.errorMessage.value;
                if (error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        error,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: controller.refreshNotifications,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      _NotificationSummary(controller: controller),
                      const SizedBox(height: 16),
                      _FilterSection(controller: controller),
                      const SizedBox(height: 16),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 40,
                          ),
                          child: Text(
                            'No notifications match the selected filters.'.tr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        )
                      else ...[
                        for (var i = 0; i < items.length; i++) ...[
                          NotificationTile(
                            notification: items[i],
                            onTap: () => controller.openNotification(items[i]),
                            onDismissed: items[i].isRead
                                ? null
                                : () => controller.markAsRead(items[i]),
                          ),
                          if (i < items.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

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
class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.notifications.length;
    final unread = controller.unreadCount;
    final read = total - unread;
    final hasUnread = unread > 0;

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    // Gradient anchors: vivid when there's something unread, calm when
    // empty. Both keep enough contrast for the white text on top.
    final gradient = hasUnread
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, primary.withValues(alpha: 0.72)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF16A34A), // green-600
              const Color(0xFF22C55E).withValues(alpha: 0.78),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Hero ----
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (hasUnread ? primary : const Color(0xFF16A34A))
                    .withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
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
                      hasUnread
                          ? '@n new'.trParams({'n': '$unread'})
                          : 'All caught up'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasUnread
                          ? 'Tap any alert to open it.'.tr
                          : 'No unread notifications.'.tr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasUnread)
                Material(
                  color: Colors.white.withValues(alpha: 0.18),
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
                          const Icon(
                            Icons.done_all_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Mark all'.tr,
                            style: const TextStyle(
                              color: Colors.white,
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
        // ---- Stat pills row ----
        Row(
          children: [
            Expanded(
              child: _StatPill(
                icon: Icons.inbox_rounded,
                label: 'All'.tr,
                value: total,
                accent: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatPill(
                icon: Icons.fiber_manual_record_rounded,
                label: 'Unread'.tr,
                value: unread,
                accent: hasUnread
                    ? const Color(0xFFEF4444) // red-500
                    : theme.disabledColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatPill(
                icon: Icons.mark_email_read_rounded,
                label: 'Read'.tr,
                value: read,
                accent: const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
      ],
    );
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
    _swing = Tween<double>(begin: -0.18, end: 0.18).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.hasUnread) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BellOrCheck old) {
    super.didUpdateWidget(old);
    if (widget.hasUnread && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.hasUnread && _ctrl.isAnimating) {
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
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (widget.hasUnread)
            AnimatedBuilder(
              animation: _swing,
              builder: (context, child) => Transform.rotate(
                angle: _swing.value,
                child: child,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Colors.white,
                size: 30,
              ),
            )
          else
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 30,
            ),
          // Red badge with count when unread > 0, capped at "99+".
          if (widget.hasUnread)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
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
  });

  final IconData icon;
  final String label;
  final int value;
  final Color accent;

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
                  '$value',
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

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final categories = const [
      ('all', 'All categories'),
      ('urgent', 'Urgent'),
      ('payment', 'Payment'),
      ('campaign', 'Campaign'),
      ('system', 'System'),
      ('reminder', 'Reminder'),
      ('normal', 'Normal'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter by status'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const [
                ('all', 'All'),
                ('unread', 'Unread'),
                ('read', 'Read'),
              ])
                ChoiceChip(
                  label: Text(entry.$2.tr),
                  selected: controller.selectedReadStatus.value == entry.$1,
                  onSelected: (_) => controller.setReadStatus(entry.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Filter by category'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in categories)
                ChoiceChip(
                  label: Text(entry.$2.tr),
                  selected: controller.selectedCategory.value == entry.$1,
                  onSelected: (_) => controller.setCategory(entry.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Filter by type'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: controller.selectedType.value,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppThemeConfig.softSurface(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppThemeConfig.border(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppThemeConfig.border(context)),
              ),
            ),
            items: [
              DropdownMenuItem<String>(
                value: 'all',
                child: Text('All types'.tr),
              ),
              ...controller.availableTypes.map(
                (type) =>
                    DropdownMenuItem<String>(value: type, child: Text(type)),
              ),
            ],
            onChanged: (value) => controller.setType(value ?? 'all'),
          ),
        ],
      ),
    );
  }
}
