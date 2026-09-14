// ChatGroupsSection — the Messages tab's block for staff-mediated group chats
// (OPOS #25284 Phase 5 Task 4).
//
// Donors, beneficiaries and volunteers never contact each other directly:
// staff put them in a group instead. This block is where a member finds those
// groups, and the requests that lead to them. Top to bottom:
//   * "My Connect Requests" — a standing door to the member's request history.
//     It shows even with no groups, because a pending request is exactly the
//     time a member has none yet;
//   * a Retry banner, only while a load has failed;
//   * "My Connections" — masked groups, where members see aliases only;
//   * "My Team Groups" — team groups, with real names.
//
// WHY THE FOUR STATES ARE WRITTEN OUT INSTEAD OF USING AppAsync
// This block is one child of the Messages tab's ListView, so it has no bounded
// height. AppAsync's error branch puts already-loaded content inside an
// Expanded, which throws in unbounded height — measured, not assumed: "RenderFlex
// children have non-zero flex but incoming height constraints are unbounded".
// So the states keep AppAsync's order and meaning, laid out as a Column:
//   * loading — nothing extra. The 1:1 threads just above already show a
//     skeleton, and most members have no groups, so a second skeleton would
//     promise content that usually never arrives;
//   * error — a compact AppErrorState with Retry, above any groups that had
//     already loaded, which stay readable;
//   * empty — nothing but the door;
//   * content — the two sub-sections.
//
// State lives in ChatGroupsController; this widget renders it and forwards
// taps. Every screen it opens is handed the same ModuleApi.
//
// WHY THE CONTROLLER IS NOT MADE HERE
// MessagesScreen registers ChatGroupsController in its own build; this block
// only finds it. GetX deletes a controller together with the route that was
// current when it was put, and this block — the last child of a lazily built
// list — can first be built while another screen covers Messages. A controller
// made at that moment belonged to the covering screen: it was deleted when that
// screen closed, and the block went on showing a list that never refreshed
// again (reproduced in a widget test for review task #26331).
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import '../controllers/chat_groups_controller.dart';
import '../models/chat_group_models.dart';
import '../screens/chat_group_conversation_screen.dart';
import '../screens/my_connect_requests_screen.dart';
import '../utils/chat_group_title.dart';

/// The avatar's diameter: the same 48 as TileIcon and the Messages tab's
/// thread avatars, so group rows line up with the rows above them.
const double _avatarSize = 48;

/// Past this many unread messages the badge stops counting and shows "99+".
const int _maxBadgeCount = 99;

/// The heading's "(count)" size, copied from messages_screen.dart's
/// _SectionLabel. It sits between AppType.meta and AppType.dense.
const double _countFontSize = 12;

/// The heading's tracking, copied from messages_screen.dart's _SectionLabel.
const double _labelLetterSpacing = 0.3;

/// The Messages tab's group-chat block: the connect-requests door, then the
/// member's masked and team groups.
class ChatGroupsSection extends StatelessWidget {
  /// [api] is injectable so tests can answer without a network. It is handed
  /// on to every screen this block opens; production uses the default. The
  /// groups themselves come from the registered ChatGroupsController.
  const ChatGroupsSection({super.key, this.api = const ModuleApi()});

  /// The API every screen opened from here reads from.
  final ModuleApi api;

  @override
  Widget build(BuildContext context) {
    // Registered by MessagesScreen: see "WHY THE CONTROLLER IS NOT MADE HERE".
    final ctrl = Get.find<ChatGroupsController>();
    // Run when a conversation opened from here closes. Quiet, like the poll:
    // it only brings the badges up to date, so it has nothing to announce.
    Future<void> refreshQuietly() => ctrl.fetchGroups(silent: true);
    return Obx(() {
      final error = ctrl.errorMessage.value;
      final masked = ctrl.masked;
      final teams = ctrl.teams;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.xs),
          _ConnectRequestsDoor(api: api),
          if (error != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpace.xs),
              child: AppErrorState(message: error, onRetry: ctrl.fetchGroups),
            ),
          if (masked.isNotEmpty)
            _GroupList(
              label: 'chat_groups_my_connections',
              groups: masked,
              api: api,
              onReturned: refreshQuietly,
            ),
          if (teams.isNotEmpty)
            _GroupList(
              label: 'chat_groups_my_team_groups',
              groups: teams,
              api: api,
              onReturned: refreshQuietly,
            ),
        ],
      );
    });
  }
}

// ─── The door ────────────────────────────────────────────────────────────────

/// The standing door to the member's connect-request history.
class _ConnectRequestsDoor extends StatelessWidget {
  const _ConnectRequestsDoor({required this.api});

  /// Handed to the requests screen, and from there to any group it opens.
  final ModuleApi api;

  @override
  Widget build(BuildContext context) {
    // SectionTile translates its own title and subtitle, so it takes keys.
    return SectionTile(
      icon: Icons.mark_chat_read_outlined,
      title: 'chat_groups_my_connect_requests',
      subtitle: 'chat_groups_my_connect_requests_desc',
      color: AppThemeConfig.accent(context),
      onTap: () => Get.to(() => MyConnectRequestsScreen(api: api)),
    );
  }
}

// ─── Group lists ─────────────────────────────────────────────────────────────

/// One sub-section: a heading with its count, then one tile per group.
class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.label,
    required this.groups,
    required this.api,
    required this.onReturned,
  });

  /// The heading's translation key.
  final String label;

  /// The groups in this sub-section, in server order.
  final List<ChatGroupSummary> groups;

  /// Handed to each conversation opened from here.
  final ModuleApi api;

  /// Run when a conversation opened from here closes.
  final Future<void> Function() onReturned;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label: label, count: groups.length),
        for (final group in groups)
          _GroupTile(group: group, api: api, onReturned: onReturned),
      ],
    );
  }
}

/// A sub-section heading with its count.
///
/// Copied from `_SectionLabel` in lib/modules/chat/screens/messages_screen.dart
/// — same weight, colour, tracking and sizes — so these headings read as
/// siblings of "Conversations" above them. It is a copy rather than shared
/// because the original is private to a file already over the 500-line cap.
/// The gaps are snapped to the spacing scale, and the padding is directional.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  /// The heading's translation key.
  final String label;

  /// How many groups sit under it.
  final int count;

  @override
  Widget build(BuildContext context) {
    final muted = AppThemeConfig.mutedText(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpace.xxs,
        AppSpace.sm,
        AppSpace.xxs,
        AppSpace.xs,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label.tr,
              style: TextStyle(
                fontSize: AppType.dense,
                fontWeight: FontWeight.w900,
                color: muted,
                letterSpacing: _labelLetterSpacing,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xxs),
          Text(
            '($count)',
            style: TextStyle(fontSize: _countFontSize, color: muted),
          ),
        ],
      ),
    );
  }
}

// ─── One group ───────────────────────────────────────────────────────────────

/// One group: its avatar, title, last message and unread badge. Tapping it
/// opens the conversation under the same title.
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.api,
    required this.onReturned,
  });

  /// The group to show.
  final ChatGroupSummary group;

  /// Handed to the conversation screen.
  final ModuleApi api;

  /// Run when the conversation opened from this tile closes.
  final Future<void> Function() onReturned;

  /// Opens this group's conversation under the title shown on the tile, then
  /// runs [onReturned] once the member comes back: reading the conversation
  /// cleared its unread count on the server, and the badge should say so now
  /// rather than at the next 5-second poll.
  Future<void> _open() async {
    await Get.to(
      () => ChatGroupConversationScreen(
        groupId: group.id,
        title: chatGroupTitle(group),
        api: api,
      ),
    );
    await onReturned();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        // Transparent Material, so the ripple paints above the panel's fill
        // rather than beneath it, where it would never be seen.
        child: Material(
          type: MaterialType.transparency,
          // One button for the whole row, so a screen reader announces the
          // title, last message and unread count together, as a thing to tap.
          child: Semantics(
            button: true,
            container: true,
            child: InkWell(
              onTap: _open,
              child: Padding(
                padding: const EdgeInsetsDirectional.all(AppSpace.sm),
                child: _content(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The avatar, the text and — only when something is unread — the badge.
  Widget _content() {
    final hasUnread = group.unreadCount > 0;
    return Row(
      children: [
        _GroupAvatar(isMasked: group.isMasked),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: _GroupText(group: group)),
        if (hasUnread) ...[
          const SizedBox(width: AppSpace.xs),
          _UnreadBadge(groupId: group.id, count: group.unreadCount),
        ],
      ],
    );
  }
}

/// A round mark saying what kind of group this is: a shield for a masked
/// connection, where identities are protected, and people for a team.
class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.isMasked});

  /// True for a masked connection.
  final bool isMasked;

  @override
  Widget build(BuildContext context) {
    // Decorative: the title beside it already says what the group is.
    return ExcludeSemantics(
      child: Container(
        width: _avatarSize,
        height: _avatarSize,
        decoration: BoxDecoration(
          // accentWash carries accent at a measured 6.44:1 (tokens.dart).
          color: AppColors.of(context).accentWash,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isMasked ? Icons.shield_outlined : Icons.groups_outlined,
          color: AppThemeConfig.accent(context),
        ),
      ),
    );
  }
}

/// The group's title over its last message. An unread group shows its message
/// in full-strength ink, so it stands out without a second colour.
///
/// Words people typed — a team's title, the last message — are laid out in
/// their own direction, not the screen's: an English message on an Arabic
/// screen would otherwise show its full stop at the wrong end (".See you").
/// Translated strings always follow the screen.
class _GroupText extends StatelessWidget {
  const _GroupText({required this.group});

  /// The group whose title and last message are shown.
  final ChatGroupSummary group;

  @override
  Widget build(BuildContext context) {
    final preview = group.lastMessage.trim();
    final hasUnread = group.unreadCount > 0;
    final screen = Directionality.of(context);
    final ink = AppThemeConfig.text(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chatGroupTitle(group),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: hasStaffWrittenTitle(group)
              ? contentDirection(group.title, fallback: screen)
              : null,
          style: TextStyle(
            fontSize: AppType.body,
            fontWeight: AppType.wLabel,
            color: ink,
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(
          preview.isEmpty ? 'chat_groups_no_messages_yet'.tr : preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: preview.isEmpty
              ? null
              : contentDirection(preview, fallback: screen),
          style: TextStyle(
            fontSize: AppType.dense,
            fontWeight: hasUnread ? AppType.wLabel : AppType.wBody,
            color: hasUnread ? ink : AppThemeConfig.mutedText(context),
          ),
        ),
      ],
    );
  }
}

/// How many messages are unread, as an accent disc. A screen reader hears a
/// sentence ("Unread messages: 3") instead of a bare number.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.groupId, required this.count});

  /// The group the badge belongs to; part of its key, so tests can find it.
  final int groupId;

  /// How many messages are unread. Always above zero here.
  final int count;

  @override
  Widget build(BuildContext context) {
    final shown = count > _maxBadgeCount ? '$_maxBadgeCount+' : '$count';
    return Semantics(
      label: 'chat_groups_unread_count'.trParams({'count': '$count'}),
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('chat_group_unread_$groupId'),
          constraints: const BoxConstraints(
            minWidth: AppSpace.xl,
            minHeight: AppSpace.xl,
          ),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpace.xxs,
          ),
          alignment: AlignmentDirectional.center,
          decoration: BoxDecoration(
            color: AppThemeConfig.accent(context),
            borderRadius: AppRadius.fullAll,
          ),
          child: Text(
            shown,
            style: TextStyle(
              fontSize: AppType.meta,
              fontWeight: AppType.wLabel,
              // onAccent is the theme's contrast-checked pair for accent.
              color: AppThemeConfig.onAccent(context),
            ),
          ),
        ),
      ),
    );
  }
}
