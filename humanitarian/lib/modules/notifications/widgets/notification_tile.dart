import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../models/app_notification_model.dart';

/// A redesigned, type-aware alert card.
///
/// Every notification reads at a glance from its category/type:
///   • a colored left accent bar + gradient icon badge in the category colour,
///   • an icon chosen from the notification *type* (chat, donation, campaign…),
///   • a distinct unread state (tinted background, coloured border, bold title)
///     vs. a calm read state (plain surface, muted),
///   • a compact relative time ("now", "5m", "3h", "2d", then the date).
///
/// Swipe-to-read and the inline chat Accept/Decline are preserved.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismissed,
  });

  final AppNotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final style = _NotificationVisuals.of(notification);
    final unread = !notification.isRead;

    final surface = AppThemeConfig.surface(context);
    // Unread cards get a faint wash of the category colour so the eye lands on
    // them first; read cards stay neutral.
    final cardColor = unread
        ? Color.alphaBlend(style.color.withValues(alpha: 0.06), surface)
        : surface;
    final borderColor = unread
        ? style.color.withValues(alpha: 0.45)
        // Pinned categories (urgent / payment) keep a hint of their colour even
        // after they're read, so high-stakes alerts never fully fade out.
        : (style.isPinned
              ? style.color.withValues(alpha: 0.30)
              : AppThemeConfig.border(context));

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: unread
                    ? style.color.withValues(alpha: 0.14)
                    : AppThemeConfig.shadow(context),
                blurRadius: unread ? 16 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Full-height coloured spine = instant type cue. Rendered as a
                // clipped child because a non-uniform border can't have a radius.
                Container(width: 4, color: style.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBadge(style: style, dimmed: !unread),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title + unread dot + relative time
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      notification.localizedTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: unread
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: AppThemeConfig.text(context),
                                        fontSize: 15.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  if (unread) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 9,
                                      height: 9,
                                      margin: const EdgeInsets.only(top: 5),
                                      decoration: BoxDecoration(
                                        color: style.color,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: style.color.withValues(
                                              alpha: 0.5,
                                            ),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Category chip · priority · link · time
                              Row(
                                children: [
                                  _CategoryChip(
                                    style: style,
                                    notification: notification,
                                  ),
                                  if (notification.priority > 0) ...[
                                    const SizedBox(width: 6),
                                    _MiniChip(
                                      icon: Icons.flag_rounded,
                                      label: notification.priority.toString(),
                                      color: Colors.teal.shade600,
                                    ),
                                  ],
                                  if (notification.hasActionUrl) ...[
                                    const SizedBox(width: 6),
                                    _MiniChip(
                                      icon: Icons.open_in_new_rounded,
                                      label: 'Link'.tr,
                                      color: Colors.blue.shade600,
                                    ),
                                  ],
                                  const Spacer(),
                                  if (notification.createdAt != null)
                                    Text(
                                      _relativeTime(
                                        notification.createdAt!.toLocal(),
                                      ),
                                      style: TextStyle(
                                        color: AppThemeConfig.mutedText(
                                          context,
                                        ),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                notification.localizedMessage,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppThemeConfig.mutedText(context),
                                  height: 1.45,
                                  fontSize: 13.5,
                                ),
                              ),
                              // Inline Accept/Decline for incoming chat requests.
                              if (notification.notificationType ==
                                      'chat_request' &&
                                  int.tryParse(notification.relatedEntityId) !=
                                      null) ...[
                                const SizedBox(height: 12),
                                _ChatRequestActions(
                                  threadId: int.parse(
                                    notification.relatedEntityId,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onDismissed == null) return child;

    return Dismissible(
      key: ValueKey('notification-${notification.id}'),
      direction: DismissDirection.horizontal,
      background: _ReadBackground(alignment: Alignment.centerLeft),
      secondaryBackground: _ReadBackground(alignment: Alignment.centerRight),
      onDismissed: (_) => onDismissed?.call(),
      child: child,
    );
  }
}

/// Compact relative time. Language-neutral short units so it works in every
/// locale without extra translation keys; falls back to an absolute date.
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inSeconds < 45) return 'now'.tr;
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('MMM d').format(dt);
}

/// Gradient icon badge in the category colour.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.style, required this.dimmed});

  final _NotificationVisuals style;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dimmed
              ? [
                  style.gradient.first.withValues(alpha: 0.55),
                  style.gradient.last.withValues(alpha: 0.55),
                ]
              : style.gradient,
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: dimmed
            ? null
            : [
                BoxShadow(
                  color: style.color.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Icon(style.icon, color: Colors.white, size: 22),
    );
  }
}

/// The category pill — small icon + localized label in the category colour.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.style, required this.notification});

  final _NotificationVisuals style;
  final AppNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.color),
          const SizedBox(width: 4),
          Text(
            notification.categoryLabel.tr,
            style: TextStyle(
              color: style.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny pill for priority / link affordances.
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadBackground extends StatelessWidget {
  const _ReadBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(Icons.mark_email_read_rounded, color: Colors.green.shade700),
    );
  }
}

/// Accept / Decline buttons shown inline on a `chat_request` notification.
///
/// Uses [Obx] to reactively read the thread's status from [ChatController].
/// This means the done-state persists across notification-list rebuilds:
/// if the thread is already `active` (accepted) or `declined`, the buttons
/// never reappear even when the notification list re-polls.
class _ChatRequestActions extends StatefulWidget {
  const _ChatRequestActions({required this.threadId});
  final int threadId;

  @override
  State<_ChatRequestActions> createState() => _ChatRequestActionsState();
}

class _ChatRequestActionsState extends State<_ChatRequestActions> {
  bool _busy = false;

  // Local "done" is only used as instant feedback during the API call,
  // before the next fetchThreads() result arrives.
  bool _localDone = false;
  String? _localResult;

  ChatController get _ctrl => Get.isRegistered<ChatController>()
      ? Get.find<ChatController>()
      : Get.put(ChatController());

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _ctrl.accept(widget.threadId);
      if (!mounted) return;
      setState(() {
        _localDone = true;
        _localResult = 'Accepted';
        _busy = false;
      });
      Get.to(
        () =>
            ChatConversationScreen(threadId: widget.threadId, title: 'Chat'.tr),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _ctrl.decline(widget.threadId);
      if (!mounted) return;
      setState(() {
        _localDone = true;
        _localResult = 'Declined';
        _busy = false;
      });
    } catch (e) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildDone(String result) {
    return Row(
      children: [
        Icon(
          result == 'Accepted'
              ? Icons.check_circle_rounded
              : Icons.cancel_rounded,
          size: 16,
          color: result == 'Accepted' ? Colors.green : Colors.redAccent,
        ),
        const SizedBox(width: 6),
        Text(
          result.tr,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppThemeConfig.mutedText(context),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : _decline,
            child: Text('Decline'.tr),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : _accept,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('Accept'.tr),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Obx reacts to ChatController.threads changes, so this widget
    // automatically updates when accept/decline completes (fetchThreads
    // refreshes the list) — and also stays correct across notification
    // list rebuilds because it reads persisted singleton state.
    return Obx(() {
      // Look up the thread's current status from the singleton controller.
      ChatThread? thread;
      for (final t in _ctrl.threads) {
        if (t.id == widget.threadId) {
          thread = t;
          break;
        }
      }

      if (thread != null && thread.status == 'active') {
        return _buildDone('Accepted');
      }
      if (thread != null && thread.status == 'declined') {
        return _buildDone('Declined');
      }

      // Thread not yet in list (controller may not have fetched yet) or
      // still pending — fall back to local state for instant feedback
      // during the in-flight API call.
      if (_localDone) return _buildDone(_localResult ?? '');

      return _buildButtons();
    });
  }
}

/// Per-type/category visual styling: a colour, a 2-stop gradient for the icon
/// badge, and an icon. Colour comes from the category (urgent/payment/…) while
/// the icon is refined by the concrete notification *type* so a chat request,
/// a donation and a campaign update each look distinct even within a category.
class _NotificationVisuals {
  const _NotificationVisuals({
    required this.color,
    required this.gradient,
    required this.icon,
    required this.isPinned,
  });

  final Color color;
  final List<Color> gradient;
  final IconData icon;
  final bool isPinned;

  factory _NotificationVisuals.of(AppNotificationModel n) {
    final base = _byCategory(n.normalizedCategory);
    final icon = _iconForType(n.notificationType) ?? base.icon;
    return _NotificationVisuals(
      color: base.color,
      gradient: base.gradient,
      icon: icon,
      isPinned: base.isPinned,
    );
  }

  static _NotificationVisuals _byCategory(String category) {
    switch (category) {
      case 'urgent':
        return _NotificationVisuals(
          color: Colors.red.shade600,
          gradient: [Colors.red.shade600, Colors.deepOrange.shade400],
          icon: Icons.priority_high_rounded,
          isPinned: true,
        );
      case 'payment':
        return _NotificationVisuals(
          color: Colors.green.shade600,
          gradient: [Colors.green.shade600, Colors.teal.shade400],
          icon: Icons.payments_rounded,
          isPinned: true,
        );
      case 'campaign':
        return _NotificationVisuals(
          color: Colors.indigo.shade500,
          gradient: [Colors.indigo.shade500, Colors.blue.shade400],
          icon: Icons.campaign_rounded,
          isPinned: false,
        );
      case 'system':
        return _NotificationVisuals(
          color: Colors.blueGrey.shade600,
          gradient: [Colors.blueGrey.shade600, Colors.blueGrey.shade400],
          icon: Icons.settings_suggest_rounded,
          isPinned: false,
        );
      case 'reminder':
        return _NotificationVisuals(
          color: Colors.amber.shade800,
          gradient: [Colors.amber.shade700, Colors.orange.shade400],
          icon: Icons.event_available_rounded,
          isPinned: false,
        );
      default:
        return _NotificationVisuals(
          color: AppThemeConfig.primary,
          gradient: [
            AppThemeConfig.primary,
            AppThemeConfig.primary.withValues(alpha: 0.65),
          ],
          icon: Icons.notifications_active_rounded,
          isPinned: false,
        );
    }
  }

  /// Refine the icon by the concrete notification type. Returns null to keep
  /// the category default.
  static IconData? _iconForType(String type) {
    final t = type.trim().toLowerCase();
    if (t.contains('chat') || t.contains('message')) {
      return Icons.forum_rounded;
    }
    if (t.contains('donation') || t.contains('payment')) {
      return Icons.volunteer_activism_rounded;
    }
    if (t.contains('sponsor') || t.contains('kafala')) {
      return Icons.diversity_1_rounded;
    }
    if (t.contains('project') || t.contains('campaign')) {
      return Icons.campaign_rounded;
    }
    if (t == 'media_post' || t == 'news' || t == 'activity') {
      return Icons.article_rounded;
    }
    if (t.contains('partner')) {
      return Icons.handshake_rounded;
    }
    if (t.contains('support') || t.contains('ticket')) {
      return Icons.support_agent_rounded;
    }
    if (t.contains('marriage')) {
      return Icons.favorite_rounded;
    }
    if (t.contains('volunteer') || t.contains('mission')) {
      return Icons.assignment_turned_in_rounded;
    }
    if (t.contains('reminder') || t.contains('due')) {
      return Icons.event_available_rounded;
    }
    if (t.contains('approve') || t.contains('accepted')) {
      return Icons.verified_rounded;
    }
    if (t.contains('reject') || t.contains('declined')) {
      return Icons.cancel_rounded;
    }
    return null;
  }
}
