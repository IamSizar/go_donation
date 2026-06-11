/// One turn in the assistant conversation.
///
/// [isUser] true  → a message the user sent (right-aligned bubble).
/// [isUser] false → the assistant's reply (left-aligned bubble), which may
/// carry an optional navigation [actionLabel]/[actionRoute].
class BotMessage {
  BotMessage.user(this.text)
      : isUser = true,
        actionLabel = null,
        actionRoute = null,
        isError = false;

  BotMessage.bot(
    this.text, {
    this.actionLabel,
    this.actionRoute,
    this.isError = false,
  }) : isUser = false;

  final String text;
  final bool isUser;

  /// CTA shown under a bot bubble, e.g. "Go to Campaigns". Null = no button.
  final String? actionLabel;

  /// Stable route key returned by the backend (donate, my_donations, …).
  final String? actionRoute;

  /// Marks a soft error/offline reply so the UI can tint it subtly.
  final bool isError;

  bool get hasAction =>
      actionLabel != null && actionLabel!.isNotEmpty && actionRoute != null;
}
