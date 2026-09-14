// MyConnectRequestsScreen — the member's own history of "ask our team to
// connect me" requests (OPOS #25284 Phase 5 Task 4), opened from the Messages
// tab's "My Connect Requests" door.
//
// Each request reads top to bottom: its status chip, with the date at the other
// end of the row; what it is about (a donation or a case); the member's own
// message; then what happens next — our team is reviewing it, the conversation
// is ready (tap to go in), or staff's reason for declining it.
//
// An APPROVED request with a group is the one tappable row, announced to
// screen readers as a button: it opens that group's conversation. That is the
// point of a request, so the row must lead there rather than leaving the
// member to hunt for the group in the tab. The conversation opens under the
// group's own title, taken from the Messages tab's ChatGroupsController — this
// screen is only reachable from that tab — and coming back refreshes that
// tab's groups, so the badge for what was just read clears at once.
//
// What people wrote — the member's message, staff's decline reason — is laid
// out in its own direction, not the screen's (see contentDirection).
//
// States come from AppAsync: skeleton, error with Retry, the designed empty
// state, the list. Pull-to-refresh works on the list and on the empty state.
// The page frame gives this AppAsync a bounded height, so after a failed
// refresh it can keep the requests already shown readable under the banner.
// They stay tappable, which is harmless here: opening a group decides nothing.
//
// State lives in MyConnectRequestsController; this screen renders it.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/chat_groups_controller.dart';
import '../controllers/my_connect_requests_controller.dart';
import '../models/chat_group_models.dart';
import '../utils/chat_group_title.dart';
import 'chat_group_conversation_screen.dart';

/// The horizontal screen gutter, shared by the list and by AppAsync's skeleton
/// and error banner, so every state lines up with the rows that replace it.
const EdgeInsetsGeometry _gutter = EdgeInsetsDirectional.symmetric(
  horizontal: AppSpace.lg,
);

/// The member's connect requests, in the order the server returns them.
class MyConnectRequestsScreen extends StatefulWidget {
  /// [api] is injectable so tests can answer without a network. It is handed
  /// on to any conversation opened from here; production uses the default.
  const MyConnectRequestsScreen({super.key, this.api = const ModuleApi()});

  /// The API the requests — and any conversation opened here — read from.
  final ModuleApi api;

  @override
  State<MyConnectRequestsScreen> createState() =>
      _MyConnectRequestsScreenState();
}

class _MyConnectRequestsScreenState extends State<MyConnectRequestsScreen> {
  /// Owns the request list for as long as this screen is open.
  late final MyConnectRequestsController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.put(MyConnectRequestsController(api: widget.api));
  }

  @override
  void dispose() {
    Get.delete<MyConnectRequestsController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SectionScaffold translates its own title and subtitle, so it takes keys.
    return SectionScaffold(
      title: 'chat_groups_my_connect_requests',
      subtitle: 'chat_groups_my_connect_requests_desc',
      child: Obx(
        () => RefreshIndicator(
          onRefresh: _ctrl.fetchRequests,
          child: AppAsync<List<MyConnectRequest>>(
            loading: _ctrl.isLoading.value,
            error: _ctrl.errorMessage.value,
            onRetry: _ctrl.fetchRequests,
            data: _ctrl.requests.toList(growable: false),
            isEmpty: (list) => list.isEmpty,
            gutter: _gutter,
            empty: const _EmptyRequests(),
            builder: _buildList,
          ),
        ),
      ),
    );
  }

  /// The requests, one card each. Always scrollable, so a short list can
  /// still be pulled down to refresh.
  Widget _buildList(List<MyConnectRequest> requests) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.lg,
        AppSpace.xxl,
      ),
      itemCount: requests.length,
      itemBuilder: (context, index) =>
          _RequestTile(request: requests[index], api: widget.api),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

/// The designed empty state, in a scroll view that always scrolls, so pulling
/// down refreshes it like the list it stands in for.
class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const AppEmpty(
            icon: Icons.mark_chat_read_outlined,
            title: 'chat_groups_requests_empty_title',
            message: 'chat_groups_requests_empty_message',
          ),
        ),
      ),
    );
  }
}

// ─── One request ─────────────────────────────────────────────────────────────

/// One request as a card. An approved request with a group opens that group's
/// conversation when tapped; every other request is read-only.
class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.api});

  /// The request to show.
  final MyConnectRequest request;

  /// Handed to the conversation screen.
  final ModuleApi api;

  /// The group this request leads to, or null when there is none to open:
  /// pending, declined, or — defensively — an approved row with no group id.
  /// The server never sends that: approval creates the group in the same
  /// transaction (backend/internal/chatgroups/chatgroups_connect.go).
  int? get _openableGroupId => request.isApproved ? request.groupId : null;

  /// The title [groupId]'s conversation opens under, named the way the
  /// Messages tab names it: a team's own title, or "Connection" for a masked
  /// group. A request carries neither the group's kind nor its title, so both
  /// come from that tab's ChatGroupsController. A group not in its list yet
  /// opens as "Connection", which names no one and so is safe for either kind.
  static String _titleFor(int groupId) {
    final groups = Get.isRegistered<ChatGroupsController>()
        ? Get.find<ChatGroupsController>().groups
        : const <ChatGroupSummary>[];
    for (final group in groups) {
      if (group.id == groupId) return chatGroupTitle(group);
    }
    return 'chat_groups_connection_title'.tr;
  }

  /// Opens [groupId]'s conversation, then — once the member comes back —
  /// quietly refreshes the Messages tab's groups, so the unread badge for what
  /// was just read clears now rather than at the next 5-second poll.
  Future<void> _openGroup(int groupId) async {
    await Get.to(
      () => ChatGroupConversationScreen(
        groupId: groupId,
        title: _titleFor(groupId),
        api: api,
      ),
    );
    if (Get.isRegistered<ChatGroupsController>()) {
      await Get.find<ChatGroupsController>().fetchGroups(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupId = _openableGroupId;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        // Transparent Material, so the ripple paints above the panel's fill.
        child: Material(
          type: MaterialType.transparency,
          // One announcement per card. A card that opens a conversation is a
          // button, so a screen reader says it can be activated.
          child: Semantics(
            button: groupId != null,
            container: true,
            child: InkWell(
              onTap: groupId == null ? null : () => _openGroup(groupId),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusRow(request: request),
                    _RequestBody(request: request),
                    _NextStep(request: request, canOpen: groupId != null),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The status chip at the reading start, the date at the reading end.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.request});

  /// The request whose status and date are shown.
  final MyConnectRequest request;

  @override
  Widget build(BuildContext context) {
    final createdAt = request.createdAt;
    return Row(
      children: [
        _StatusChip(request: request),
        const Spacer(),
        if (createdAt != null)
          Text(
            // Intl.defaultLocale follows the app's language
            // (AppLocaleService.syncDateFormatLocale), so this skeleton prints
            // Arabic month names on an Arabic screen.
            DateFormat.yMMMd().format(createdAt.toLocal()),
            style: TextStyle(
              fontSize: AppType.meta,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
      ],
    );
  }
}

/// The request's status as a tinted pill, drawn in the theme's status pairs —
/// each ink on its own wash, measured for contrast in tokens.dart.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.request});

  /// The request whose status is shown.
  final MyConnectRequest request;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Any status the app does not know reads as pending — the model's own
    // default when the server omits one.
    final (String key, Color ink, Color wash) = request.isApproved
        ? ('chat_groups_status_approved', c.accent, c.accentWash)
        : request.isDeclined
        ? ('chat_groups_status_declined', c.consequence, c.consequenceWash)
        : ('chat_groups_status_pending', c.pending, c.pendingWash);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpace.xs,
        vertical: AppSpace.xxs,
      ),
      decoration: BoxDecoration(color: wash, borderRadius: AppRadius.fullAll),
      child: Text(
        key.tr,
        style: TextStyle(
          fontSize: AppType.meta,
          fontWeight: AppType.wLabel,
          color: ink,
        ),
      ),
    );
  }
}

/// What the request is about, then the member's own words.
class _RequestBody extends StatelessWidget {
  const _RequestBody({required this.request});

  /// The request whose subject and message are shown.
  final MyConnectRequest request;

  /// The translation key naming the request's subject, or null for a context
  /// this app version does not know — better silent than wrong.
  static String? _subjectKey(String contextType) => switch (contextType) {
    'donation' => 'chat_groups_about_donation',
    'case' => 'chat_groups_about_case',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final subject = _subjectKey(request.contextType);
    final message = request.message.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subject != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            subject.tr,
            style: TextStyle(
              fontSize: AppType.meta,
              fontWeight: AppType.wLabel,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
        ],
        if (message.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(
            message,
            // The member's own words, in their own direction: English on an
            // Arabic screen otherwise shows its full stop at the wrong end.
            textDirection: contentDirection(
              message,
              fallback: Directionality.of(context),
            ),
            style: TextStyle(
              fontSize: AppType.body,
              height: AppType.leadDense,
              color: AppThemeConfig.text(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// What happens next: our team is reviewing it; the conversation is ready; or
/// staff's reason for declining. An approved row with no group id — which the
/// server never sends, since approval creates the group in the same
/// transaction — says nothing, rather than promise a link that is not there.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.request, required this.canOpen});

  /// The request whose next step is shown.
  final MyConnectRequest request;

  /// True when tapping the card opens the request's group.
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final reason = request.declineReason;
    final Widget? step = request.isDeclined && reason != null
        ? _DeclineReason(reason: reason)
        : canOpen
        ? const _OpenConversationHint()
        : request.isPending
        ? Text(
            'chat_groups_pending_hint'.tr,
            style: TextStyle(
              fontSize: AppType.dense,
              color: AppThemeConfig.mutedText(context),
            ),
          )
        : null;
    if (step == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.sm),
      child: step,
    );
  }
}

/// "Open the conversation", with a chevron that points the way the row leads.
class _OpenConversationHint extends StatelessWidget {
  const _OpenConversationHint();

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeConfig.accent(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            'chat_groups_open_conversation'.tr,
            style: TextStyle(
              fontSize: AppType.dense,
              fontWeight: AppType.wLabel,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.xxs),
        // Self-mirroring, so it points left in Arabic (directional_icons.dart).
        Icon(AppIcons.forward(context), size: AppType.dense, color: accent),
      ],
    );
  }
}

/// Staff's reason for declining, set apart on a recessed panel and introduced
/// by a label, so it reads as our team speaking rather than as the member's
/// own message above it.
class _DeclineReason extends StatelessWidget {
  const _DeclineReason({required this.reason});

  /// The reason exactly as staff wrote it.
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: AppRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat_groups_decline_reason_label'.tr,
            style: TextStyle(
              fontSize: AppType.meta,
              fontWeight: AppType.wLabel,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            reason,
            // Staff's own words, in their own direction, like the message.
            textDirection: contentDirection(
              reason,
              fallback: Directionality.of(context),
            ),
            style: TextStyle(
              fontSize: AppType.dense,
              height: AppType.leadDense,
              color: AppThemeConfig.text(context),
            ),
          ),
        ],
      ),
    );
  }
}
