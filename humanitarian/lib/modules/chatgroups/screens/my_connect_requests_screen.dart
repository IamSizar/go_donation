// MyConnectRequestsScreen — the member's own history of "ask our team to
// connect me" requests (OPOS #25284 Phase 5 Task 4), opened from the Messages
// tab's "My Connect Requests" door.
//
// Each request reads top to bottom: its status chip, with the date at the other
// end of the row; what it is about (a donation or a case); the member's own
// message; then what happens next — our team is reviewing it, the conversation
// is ready (tap to go in), or staff's reason for declining it.
//
// An APPROVED request with a group is the one tappable row: it opens that
// group's conversation. That is the point of a request, so the row must lead
// there rather than leaving the member to hunt for the group in the tab.
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
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/my_connect_requests_controller.dart';
import '../models/chat_group_models.dart';
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
  /// pending, declined, or approved before its group exists.
  int? get _openableGroupId => request.isApproved ? request.groupId : null;

  /// Opens [groupId]'s conversation under the neutral "Connection" title.
  ///
  /// A request carries neither the group's kind nor its title, and staff may
  /// approve it into a masked or a team group (ApproveConnectRequest takes a
  /// kind), so the one title that is safe for both — it names no one — is used.
  void _openGroup(int groupId) {
    Get.to(
      () => ChatGroupConversationScreen(
        groupId: groupId,
        title: 'chat_groups_connection_title'.tr,
        api: api,
      ),
    );
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
/// staff's reason for declining. An approved request whose group does not
/// exist yet says nothing, rather than promise a link that is not there.
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
