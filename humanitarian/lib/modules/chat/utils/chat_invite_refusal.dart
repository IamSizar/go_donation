// chat_invite_refusal.dart — the sentence a refused chat-invite Accept or
// Decline shows, for the donor chat and the marriage chat alike (OPOS #26433).
//
// WHY THIS EXISTS
// Three places answer a chat invite: the marriage conversation screen, the
// Messages tab's request card and a chat_request notification's inline row.
// Each caught the failure its own way, as the send-failure line, the raw
// exception text, or nothing at all, so a refusal the server had NAMED reached
// the user as something false or unreadable. This file is the one decision
// they now share.
//
// WHAT THE SERVER ANSWERS (backend/internal/handlers, chat.go and
// marriage_chat.go)
//   * accept on a paused or ended thread: 409 `chat_lifecycle_closed`, with
//     `lifecycle` and staff's `lifecycle_reason`;
//   * accept on an archived thread: 404, no code (the thread is hidden from
//     participants, so it reads as closed);
//   * accept on an invite already declined: 409 `chat_invite_declined`;
//   * decline on an active chat: 409 with NO code. It is the only 409 either
//     decline route returns — both stores map "not pending" to it — so the
//     status alone identifies it without reading the English sentence.
// Declining a closed invite is allowed, so Decline stays on a closed thread.
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/modules/chat/widgets/chat_lifecycle_notice.dart';
import 'package:get/get.dart';

/// Which answer to the invite was refused.
enum ChatInviteAnswer { accept, decline }

/// What a refusal means for the user and for the buttons still on screen.
enum ChatInviteRefusal {
  /// Staff paused, ended or archived the thread: Accept must go.
  closed,

  /// The user already declined this invite: it cannot be accepted.
  declined,

  /// The chat is already active: it cannot be declined.
  alreadyActive,

  /// Anything else, including offline: the user may simply try again.
  other,
}

/// The server's machine code for a closed thread's refused accept.
const String chatLifecycleClosedCode = 'chat_lifecycle_closed';

/// The server's machine code for accepting an invite already declined.
const String chatInviteDeclinedCode = 'chat_invite_declined';

/// Classifies [error] thrown by an accept or decline call.
///
/// Only [ApiCodedException] can carry a named refusal; any other error is
/// [ChatInviteRefusal.other].
ChatInviteRefusal classifyChatInviteRefusal(
  Object error,
  ChatInviteAnswer answer,
) {
  if (error is! ApiCodedException) return ChatInviteRefusal.other;
  if (error.code == chatLifecycleClosedCode) return ChatInviteRefusal.closed;
  if (error.code == chatInviteDeclinedCode) return ChatInviteRefusal.declined;
  if (error.code.isNotEmpty) return ChatInviteRefusal.other;
  if (answer == ChatInviteAnswer.accept && error.statusCode == 404) {
    return ChatInviteRefusal.closed;
  }
  if (answer == ChatInviteAnswer.decline && error.statusCode == 409) {
    return ChatInviteRefusal.alreadyActive;
  }
  return ChatInviteRefusal.other;
}

/// The localized sentence for a refused [answer]. Never contains the
/// exception's own text; callers still log [error] themselves.
String chatInviteRefusalMessage(Object error, ChatInviteAnswer answer) {
  switch (classifyChatInviteRefusal(error, answer)) {
    case ChatInviteRefusal.closed:
      return _closedMessage(error as ApiCodedException);
    case ChatInviteRefusal.declined:
      return 'chat_invite_refusal_declined'.tr;
    case ChatInviteRefusal.alreadyActive:
      return 'chat_invite_refusal_already_active'.tr;
    case ChatInviteRefusal.other:
      return failureMessage(
        error,
        answer == ChatInviteAnswer.accept
            ? 'error_chat_accept_failed'
            : 'Could not decline this chat request.',
      );
  }
}

/// The lifecycle notice's own title ("... by our team"), plus staff's reason
/// when they gave one, so the refusal and the banner say the same thing.
String _closedMessage(ApiCodedException error) {
  final paused = error.payload['lifecycle'] == ChatLifecycle.paused;
  final title = paused
      ? 'This conversation has been paused by our team.'.tr
      : 'This conversation has been closed by our team.'.tr;
  final reason = (error.payload['lifecycle_reason'] ?? '').toString().trim();
  if (reason.isEmpty) return title;
  return '$title ${'Reason'.tr}: $reason';
}
