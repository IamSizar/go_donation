// The three outcomes of asking the server to open a support thread.
//
// WHY A TYPE RATHER THAN A NULLABLE INT
// The old call returned `int?`, which gave "it worked" and both ways of
// failing exactly two states between them. The screen therefore treated a
// PERMANENT refusal the same as a dropped connection, and showed a Retry
// button for a condition that no number of retries can change: when no staff
// account has been nominated as the support recipient, the server answers 503
// and will keep answering 503 until someone picks one in the dashboard.
//
// Offering Retry there is worse than offering nothing, because it tells the
// user the problem is on their side and asks them to keep trying. Meanwhile
// two support channels that DO work — the ticket form and the WhatsApp
// handoff — sit one screen away, unmentioned.
sealed class SupportChatResult {
  const SupportChatResult();

  /// A thread is open; [threadId] is ready to push a conversation screen with.
  const factory SupportChatResult.opened(int threadId) = SupportChatOpened;

  /// No staff account is configured to receive support chats. Permanent until
  /// staff change it, so the user is offered the channels that work instead.
  const factory SupportChatResult.unavailable() = SupportChatUnavailable;

  /// Anything else — offline, timeout, a server error. Worth retrying.
  ///
  /// [detail] is for the LOG only. It is the server's own sentence, in
  /// English, and putting it on an Arabic screen is the exact leak this app
  /// has spent the week removing.
  const factory SupportChatResult.failed(String detail) = SupportChatFailed;
}

class SupportChatOpened extends SupportChatResult {
  const SupportChatOpened(this.threadId);
  final int threadId;
}

class SupportChatUnavailable extends SupportChatResult {
  const SupportChatUnavailable();
}

class SupportChatFailed extends SupportChatResult {
  const SupportChatFailed(this.detail);
  final String detail;
}
