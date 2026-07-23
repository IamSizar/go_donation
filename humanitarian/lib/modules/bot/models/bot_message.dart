/// One tool the assistant called to answer with the user's own real data
/// (wallet balance, donations, marriage profile, case/project, volunteer
/// status), rendered as a small structured card instead of prose.
class AssistantToolResult {
  const AssistantToolResult({required this.tool, required this.data});

  /// Stable tool name from the backend (e.g. "get_wallet_balance").
  final String tool;

  /// The tool's JSON result, already decoded.
  final Map<String, dynamic> data;
}

/// One turn in the assistant conversation.
///
/// [isUser] true  → a message the user sent (right-aligned bubble).
/// [isUser] false → the assistant's reply (left-aligned bubble), which may
/// carry an optional navigation [actionLabel]/[actionRoute] and any
/// [toolResults] the backend looked up to answer it.
class BotMessage {
  BotMessage.user(this.text)
      : isUser = true,
        actionLabel = null,
        actionRoute = null,
        isError = false,
        toolResults = const [];

  BotMessage.bot(
    this.text, {
    this.actionLabel,
    this.actionRoute,
    this.isError = false,
    this.toolResults = const [],
  }) : isUser = false;

  final String text;
  final bool isUser;

  /// CTA shown under a bot bubble, e.g. "Go to Campaigns". Null = no button.
  final String? actionLabel;

  /// Stable route key returned by the backend (donate, my_donations, …).
  final String? actionRoute;

  /// Marks a soft error/offline reply so the UI can tint it subtly.
  final bool isError;

  /// Structured personal-data lookups the assistant used to answer this turn.
  final List<AssistantToolResult> toolResults;

  bool get hasAction =>
      actionLabel != null && actionLabel!.isNotEmpty && actionRoute != null;
}
