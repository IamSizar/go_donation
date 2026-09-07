/// MarriageChatsSection — the engagement (خطوبة) channels, inside «الرسائل».
///
/// WHY THIS EXISTS
/// The client reported that they could not find the messaging channels at all:
/// "لم نعلم طريقة استخدامهم او من اين". Two of the five they asked about — the
/// engagement↔staff channel and the engagement group chat — were reachable
/// only by going Events tab → «قسم الفعاليات» → and then one of two rows. That
/// is two levels deep, under a tab whose name says nothing about messaging,
/// and nowhere near the screen actually called "Messages". A user looking for
/// their messages looked in Messages and found no trace of them.
///
/// Both entries now also appear here, so «الرسائل» answers "where are my
/// conversations?" on its own. The originals in the Events group screen are
/// deliberately LEFT IN PLACE: they are the contextual entry (you are already
/// in the events section, you message the events staff), and removing them
/// would break a path the client may already have been taught.
///
/// ROLE SEPARATION — the point of the gate below
/// Zaid's requirement: "make sure of propper seperation, like each chat
/// appears for the correct role". A volunteer must not see engagement chats.
/// The gate is deliberately BOTH role and data:
///
///   • roleKey == 'marriage' → always shown, even with no threads yet. An
///     engagement user with no accepted meeting still needs to see WHERE the
///     section lives — an empty section that is present is the answer to the
///     client's complaint, and a section that only appears once you already
///     have a conversation cannot teach anyone how to start one.
///   • any other role → shown only if the server actually returned threads.
///     RoleDashboardController's own notes record a device found holding a
///     stale role_id for an account the server reported differently, so real
///     data outranks the role string; a genuine participant is never hidden
///     from their own conversation by a stale label.
///   • neither → nothing renders. A volunteer, donor or beneficiary with no
///     engagement threads sees no engagement UI at all.
///
/// Identity masking is NOT implemented here and must not be: the marriage
/// endpoints mask server-side (`other_label` is a public profile code or a
/// placeholder — see MarriageChatsScreen). This widget shows counts and entry
/// points only, so there is nothing here that could leak a name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_chats_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// The server's role key for an engagement/marriage account, as
/// `dashboardTitleForRole` in widgets/dashboard.dart spells it.
const String kMarriageRoleKey = 'marriage';

class MarriageChatsSection extends StatefulWidget {
  const MarriageChatsSection({super.key, this.api = const ModuleApi()});

  /// Seam for tests, defaulted so the single call site is unchanged.
  final ModuleApi api;

  @override
  State<MarriageChatsSection> createState() => _MarriageChatsSectionState();
}

class _MarriageChatsSectionState extends State<MarriageChatsSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  /// A failed fetch must not hide the section for an engagement user: the
  /// entries are how they reach staff, and staff is who they would ask about
  /// a failure. So the error is swallowed into an empty list here and the
  /// role half of the gate keeps the tiles on screen.
  Future<List<Map<String, dynamic>>> _fetch() async {
    try {
      return await widget.api.marriageChats();
    } catch (e) {
      debugPrint('marriageChats failed in MessagesScreen section: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// The role as the SERVER last reported it, empty when the controller has
  /// not been registered (this screen can be opened without the dashboard
  /// having built, e.g. from a notification).
  String get _roleKey => Get.isRegistered<RoleDashboardController>()
      ? Get.find<RoleDashboardController>().roleKey.value.trim()
      : '';

  @override
  Widget build(BuildContext context) {
    final isMarriageRole = _roleKey == kMarriageRoleKey;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final threads = snapshot.data ?? const <Map<String, dynamic>>[];
        // The gate. Renders nothing at all for a role this does not belong to.
        if (!isMarriageRole && threads.isEmpty) return const SizedBox.shrink();

        final accent = AppThemeConfig.accent(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Item 5 of the client's list — the three-way group thread.
              // The subtitle names the participants and states the masking,
              // because "who can read this" is the first thing a user of a
              // matchmaking chat needs to know and the screen is where they
              // ask it (rule 5.9).
              SectionTile(
                icon: Icons.forum_outlined,
                title: 'messages_marriage_chats_title',
                subtitle: 'messages_marriage_chats_desc',
                color: accent,
                onTap: () => Get.to(() => const MarriageChatsScreen()),
              ),
              const SizedBox(height: 10),
              // Item 4 — the engagement user's own line to staff. Same
              // support_user_id as every other staff channel, so it shows the
              // same "not configured yet" notice when none is set.
              SectionTile(
                icon: Icons.support_agent_rounded,
                title: 'messages_marriage_staff_title',
                subtitle: 'messages_marriage_staff_desc',
                color: accent,
                onTap: () => ChatActions.startSupportChat(
                  context,
                  conversationTitle: 'messages_marriage_staff_title'.tr,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}
