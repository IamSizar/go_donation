// The one place a chat group's visible title is decided (OPOS #25284 Phase 5).
//
// Two screens open a group's conversation — the Messages tab's group tile and
// an approved connect request — and both must name it the same way. The rule
// also guards a privacy promise: a masked group is ALWAYS "Connection",
// whatever title the server sends, so no title can ever put a real name on a
// masked member's screen. Keeping that rule in one function means the two
// screens cannot drift apart on it.
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// The title a member may see for [group]: "Connection" for a masked group; a
/// team group's own title, or the translated team fallback when it is blank.
String chatGroupTitle(ChatGroupSummary group) {
  if (group.isMasked) return 'chat_groups_connection_title'.tr;
  final title = group.title.trim();
  return title.isEmpty ? 'chat_groups_team_group_title'.tr : title;
}

/// True when [chatGroupTitle] shows words staff typed rather than a translated
/// fallback. Only such a title is laid out in its own text direction; a
/// translated string always follows the screen.
bool hasStaffWrittenTitle(ChatGroupSummary group) =>
    !group.isMasked && group.title.trim().isNotEmpty;
