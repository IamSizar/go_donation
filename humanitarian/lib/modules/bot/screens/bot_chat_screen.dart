import 'dart:math' as math;
import 'package:flutter_application_1/core/widgets/app_main_menu_button.dart';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_application_1/localization/locale_service.dart';

import '../bot_navigation.dart';
import '../controllers/assistant_controller.dart';
import '../data/bot_strings.dart';
import '../models/bot_message.dart';
import '../models/bot_qa.dart';
import '../widgets/assistant_hint_button.dart' show AssistantTopic;
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';

/// A role-aware AI Support Assistant. Typed questions and chip taps are sent to
/// the backend `/assistant/chat` endpoint (Claude-backed when configured, a
/// keyword engine otherwise). Replies can carry a one-tap navigation action.
class BotChatScreen extends StatefulWidget {
  const BotChatScreen({super.key, this.opening});

  /// K28 — when the assistant is opened from a section's AI icon, the section's
  /// own question is asked straight away, so the user gets the explanation of
  /// where they are standing without having to phrase it. Null (the الرسائل
  /// card, and any role with no FAQ for that section) opens the normal welcome.
  final AssistantTopic? opening;

  @override
  State<BotChatScreen> createState() => _BotChatScreenState();
}

class _BotChatScreenState extends State<BotChatScreen> {
  final AssistantController ctrl = Get.put(AssistantController());
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _inputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll whenever the conversation grows or typing toggles. Both
    // events route through a single coalesced scroll so rapid updates (user
    // message + typing indicator in the same frame) don't fight each other.
    ever<List<BotMessage>>(ctrl.messages, (_) => _scrollToBottom());
    ever<bool>(ctrl.isTyping, (_) => _scrollToBottom());
    _askOpeningQuestion();
  }

  /// Sends the section question the AI icon was tapped from, once, after the
  /// first frame.
  ///
  /// Guarded on an empty conversation: `AssistantController` is a `Get.put`
  /// singleton, so re-entering the assistant from a second section would
  /// otherwise append a fresh question to a conversation already in progress.
  void _askOpeningQuestion() {
    final opening = widget.opening;
    if (opening == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ctrl.messages.isNotEmpty) return;
      _send(opening.question, intentID: opening.intentId);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  bool _scrollQueued = false;

  /// Smoothly scrolls to the bottom. Coalesces multiple calls within one frame
  /// into a single animation, and lands exactly at maxScrollExtent (no
  /// overshoot) so there's no bounce/jank.
  void _scrollToBottom() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      // Tiny moves aren't worth animating — they read as a jitter.
      if ((target - _scrollCtrl.offset).abs() < 4) return;
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // Note #40 — "assistance-related conversations" (the AI assistant chat)
  // are restricted for guests.
  Future<void> _send(String text, {String? intentID}) async {
    if (!await requireUpgrade(context)) return;
    ctrl.send(text, intentID: intentID);
  }

  // Client note — AI Assistant "more developed": free-typed questions, not
  // just the suggestion chips. The welcome bubble already promised this
  // ("type your own question") — this wires it up.
  Future<void> _sendTyped() async {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty || ctrl.isTyping.value) return;
    _inputCtrl.clear();
    await _send(text);
  }

  // Full routing: hand the route key to the central resolver, which switches
  // the base tab and pushes the specific destination screen (e.g. Edit Profile).
  void _navigate(String route) => BotNavigation.go(route);

  @override
  Widget build(BuildContext context) {
    // Canonical assistant locale (en / ar / ckb / kmr) for all bot UI strings.
    final lang = AppLocaleService.assistantLang();
    return Scaffold(
      backgroundColor: AppThemeConfig.backgroundTop(context),
      appBar: _buildAppBar(context, lang),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              final msgs = ctrl.messages;
              return ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  _WelcomeBubble(lang: lang),
                  const SizedBox(height: 18),
                  // Suggestions stay visible; tapping one sends it as a turn.
                  // Localised question text is shown AND sent, while the stable
                  // id routes the backend to the right intent regardless of lang.
                  _SuggestionsSection(
                    qas: ctrl.suggestions,
                    lang: lang,
                    onTap: (qa) => _send(qa.questionFor(lang), intentID: qa.id),
                  ),
                  for (final m in msgs) ...[
                    const SizedBox(height: 14),
                    if (m.isUser)
                      _UserBubble(text: m.text)
                    else ...[
                      _BotBubble(
                        message: m,
                        onAction: m.hasAction
                            ? () => _navigate(m.actionRoute!)
                            : null,
                      ),
                      for (final tr in m.toolResults) ...[
                        const SizedBox(height: 8),
                        _ToolResultCard(result: tr),
                      ],
                    ],
                  ],
                  if (ctrl.isTyping.value) ...[
                    const SizedBox(height: 14),
                    const _TypingBubble(),
                  ],
                  const SizedBox(height: 16),
                ],
              );
            }),
          ),
          // #36 — after 3 user messages, offer to continue on WhatsApp.
          Obx(
            () => ctrl.showWhatsappOffer
                ? _WhatsappOffer(number: ctrl.whatsappNumber.value!)
                : const SizedBox.shrink(),
          ),
          _Composer(
            controller: _inputCtrl,
            onSend: _sendTyped,
            isSending: ctrl.isTyping,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, String lang) {
    return AppBar(
      backgroundColor: AppThemeConfig.surface(context),
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          AppIcons.back(context),
          size: 20,
          color: AppThemeConfig.text(context),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          _BotAvatar(size: 36, iconSize: 20, radius: 11),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                BotStrings.of('title', lang),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
              Text(
                BotStrings.of('subtitle', lang),
                style: TextStyle(
                  fontSize: 11,
                  color: AppThemeConfig.mutedText(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
      // J7 — see chat_conversation_screen: `actions` rather than beside the
      // back arrow, because this AppBar already fills its `leading` slot.
      actions: const [AppMainMenuButton()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: AppThemeConfig.border(context)),
      ),
    );
  }
}

// ─── Welcome bubble ───────────────────────────────────────────────────────────

class _WelcomeBubble extends StatelessWidget {
  const _WelcomeBubble({required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BotAvatar(size: 40, iconSize: 22, radius: 13),
        const SizedBox(width: 10),
        Expanded(
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Text(
              BotStrings.of('welcome', lang),
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Suggestions ─────────────────────────────────────────────────────────────

/// A polished, card-based suggestions panel. Each question is its own tappable
/// row with a colored icon tile, the full question, and a chevron — much
/// clearer than chips when the questions are long.
class _SuggestionsSection extends StatelessWidget {
  const _SuggestionsSection({
    required this.qas,
    required this.onTap,
    required this.lang,
  });

  final List<BotQA> qas;
  final ValueChanged<BotQA> onTap;

  /// Current app locale code, used to render each chip's question text.
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context).withValues(alpha: 0.06),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: AppThemeConfig.accent(context),
                ),
                const SizedBox(width: 7),
                Text(
                  BotStrings.of('suggestionsHeader', lang),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppThemeConfig.accent(context),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < qas.length; i++)
            _SuggestionCard(
              qa: qas[i],
              lang: lang,
              onTap: () => onTap(qas[i]),
              isLast: i == qas.length - 1,
            ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.qa,
    required this.onTap,
    required this.isLast,
    required this.lang,
  });

  final BotQA qa;
  final VoidCallback onTap;
  final bool isLast;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 6 : 8),
      child: Material(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    qa.icon,
                    size: 18,
                    color: AppThemeConfig.accent(context),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    qa.questionFor(lang),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  AppIcons.forward(context),
                  size: 13,
                  color: AppThemeConfig.mutedText(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chat bubbles ─────────────────────────────────────────────────────────────

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppThemeConfig.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppThemeConfig.primary.withValues(alpha: 0.30),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({required this.message, this.onAction});

  final BotMessage message;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final bg = message.isError
        ? Colors.orange.withValues(alpha: 0.08)
        : AppThemeConfig.surface(context);
    final borderColor = message.isError
        ? Colors.orange.withValues(alpha: 0.35)
        : AppThemeConfig.border(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BotAvatar(size: 32, iconSize: 16, radius: 10),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: borderColor),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppThemeConfig.shadow(context),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                if (message.hasAction && onAction != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onAction,
                      icon: Icon(AppIcons.forwardSolid(context), size: 15),
                      label: Text(message.actionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppThemeConfig.accent(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Typing indicator ─────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gentle fade + scale entrance so the typing bubble eases in rather than
    // popping into place.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppMotion.resolve(context, AppMotion.settleDuration),
      curve: AppMotion.resolveCurve(context, Curves.easeOutBack),
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            alignment: AlignmentDirectional.bottomStart,
            child: child,
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BotAvatar(size: 32, iconSize: 16, radius: 10),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: AppThemeConfig.surface(context),
              border: Border.all(color: AppThemeConfig.border(context)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    // Each dot runs the same bounce, offset in phase, producing a
                    // smooth left-to-right wave. A sine curve drives both the
                    // vertical lift and a subtle size/opacity pulse.
                    final phase = (_c.value + i * 0.18) % 1.0;
                    final wave = math.sin(phase * 2 * math.pi);
                    final lift = (wave.clamp(0, 1)) * 6.0; // up to 6px up
                    final scale = 0.85 + 0.30 * wave.clamp(0, 1);
                    final opacity = 0.45 + 0.55 * wave.clamp(0, 1);
                    return Padding(
                      padding: EdgeInsetsDirectional.only(end: i < 2 ? 6 : 0),
                      child: Transform.translate(
                        offset: Offset(0, -lift),
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppThemeConfig.accent(
                                context,
                              ).withValues(alpha: opacity),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared bot avatar ────────────────────────────────────────────────────────

class _BotAvatar extends StatelessWidget {
  const _BotAvatar({
    required this.size,
    required this.iconSize,
    required this.radius,
  });

  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.smart_toy_rounded, color: AppThemeConfig.onAccent(context), size: iconSize),
    );
  }
}

// ─── Tap hint footer ──────────────────────────────────────────────────────────

/// Replaces the free-text input: this assistant is tap-only, so users pick from
/// the recommended questions rather than typing.
// #36 — "Continue on WhatsApp" banner shown after 3 user messages.
class _WhatsappOffer extends StatelessWidget {
  const _WhatsappOffer({required this.number});
  final String number;

  Future<void> _open() async {
    final uri = Uri.parse('https://wa.me/$number');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF25D366).withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'whatsapp_offer'.tr,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _open,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF25D366),
            ),
            child: Text('whatsapp_open'.tr),
          ),
        ],
      ),
    );
  }
}

// ─── Composer ─────────────────────────────────────────────────────────────

/// Client note — AI Assistant "more developed": a real free-text input, not
/// just suggestion chips (the welcome bubble already promised "type your own
/// question" — this was the missing piece). Mirrors chat_conversation_screen's
/// composer styling for consistency with the rest of the app's chat UIs.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.isSending,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final RxBool isSending;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppThemeConfig.surface(context),
          border: Border(
            top: BorderSide(color: AppThemeConfig.border(context)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: BotStrings.of(
                    'inputHint',
                    AppLocaleService.assistantLang(),
                  ),
                  filled: true,
                  fillColor: AppThemeConfig.softSurface(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(
                      color: AppThemeConfig.border(context),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(
                      color: AppThemeConfig.border(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(
              () => AppPressable(
                onTap: isSending.value ? null : onSend,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.accent(context),
                    shape: BoxShape.circle,
                  ),
                  child: isSending.value
                      ? Padding(
                          padding: const EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppThemeConfig.onAccent(context),
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: AppThemeConfig.onAccent(context),
                          size: 20,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tool result cards ────────────────────────────────────────────────────

/// Renders one assistant tool lookup (the user's own wallet/donations/
/// marriage/case/volunteer data) as a compact structured card instead of
/// making the model describe numbers in prose.
class _ToolResultCard extends StatelessWidget {
  const _ToolResultCard({required this.result});
  final AssistantToolResult result;

  @override
  Widget build(BuildContext context) {
    final rows = _rowsFor(result);
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 40),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconFor(result.tool),
                  size: 16,
                  color: AppThemeConfig.accent(context),
                ),
                const SizedBox(width: 6),
                Text(
                  _titleFor(result.tool).tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        row.$1,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        row.$2,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String tool) {
    switch (tool) {
      case 'get_wallet_balance':
        return Icons.account_balance_wallet_rounded;
      case 'get_my_donations':
        return Icons.volunteer_activism_rounded;
      case 'get_my_marriage_profile':
        return Icons.favorite_rounded;
      case 'get_my_beneficiary_status':
        return Icons.fact_check_rounded;
      case 'get_my_volunteer_status':
        return Icons.handshake_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String _titleFor(String tool) {
    switch (tool) {
      case 'get_wallet_balance':
        return 'Wallet balance';
      case 'get_my_donations':
        return 'Your donations';
      case 'get_my_marriage_profile':
        return 'Your marriage profile';
      case 'get_my_beneficiary_status':
        return 'Your case & project';
      case 'get_my_volunteer_status':
        return 'Your volunteer status';
      default:
        return tool;
    }
  }

  /// Maps a tool's raw JSON into (label, value) rows. Returns null for an
  /// error result (the reply text already explains it) or an unknown tool.
  List<(String, String)>? _rowsFor(AssistantToolResult result) {
    final data = result.data;
    if (data['error'] != null) return null;

    switch (result.tool) {
      case 'get_wallet_balance':
        final rows = <(String, String)>[
          ('Balance'.tr, _money(data['balance_iqd'])),
        ];
        final recent = (data['recent_transactions'] as List?) ?? const [];
        if (recent.isEmpty) {
          rows.add(('Recent transactions'.tr, 'No recent transactions.'.tr));
        } else {
          for (final t in recent.take(3)) {
            if (t is Map) {
              rows.add((
                // Isolated: the date follows the transaction type across a
                // neutral bullet.
                '${t['type'] ?? ''} · ${isolatedDate(t['date'])}',
                _money(t['amount_iqd']),
              ));
            }
          }
        }
        return rows;

      case 'get_my_donations':
        final stats = data['stats'];
        final rows = <(String, String)>[];
        if (stats is Map) {
          rows.add((
            'Total donated'.tr,
            '${stats['total_amount'] ?? 0} (${stats['total_count'] ?? 0})',
          ));
        }
        final recent = (data['recent'] as List?) ?? const [];
        if (recent.isEmpty) {
          rows.add(('Your donations'.tr, 'No recent donations.'.tr));
        } else {
          for (final d in recent.take(3)) {
            if (d is Map) {
              rows.add((
                '${d['campaign'] ?? ''} · ${d['payment_status'] ?? ''}',
                '${d['amount'] ?? ''} ${d['currency'] ?? ''}',
              ));
            }
          }
        }
        return rows;

      case 'get_my_marriage_profile':
        final profiles = (data['profiles'] as List?) ?? const [];
        if (profiles.isEmpty) {
          return [('Your marriage profile'.tr, 'No marriage profile yet.'.tr)];
        }
        final rows = <(String, String)>[];
        for (final p in profiles.take(3)) {
          if (p is Map) {
            rows.add((
              '${p['profile_code'] ?? ''}',
              '${p['status'] ?? ''} · ${p['subscription_tier'] ?? ''}',
            ));
          }
        }
        return rows;

      case 'get_my_beneficiary_status':
        final cases = (data['cases'] as List?) ?? const [];
        final requests = (data['project_requests'] as List?) ?? const [];
        if (cases.isEmpty && requests.isEmpty) {
          return [('Your case & project'.tr, 'No case or project found.'.tr)];
        }
        final rows = <(String, String)>[];
        for (final c in cases.take(2)) {
          if (c is Map) {
            rows.add((
              '${c['case_code'] ?? ''}',
              '${c['verification_status'] ?? ''}',
            ));
          }
        }
        for (final r in requests.take(2)) {
          if (r is Map) {
            rows.add((
              localizedContentFromMap(Map<String, dynamic>.from(r), 'title'),
              '${r['status'] ?? ''} · ${r['raised_amount'] ?? 0}/${r['amount_needed'] ?? 0}',
            ));
          }
        }
        return rows;

      case 'get_my_volunteer_status':
        final missions = (data['joined_missions'] as List?) ?? const [];
        if (missions.isEmpty) {
          return [('Your volunteer status'.tr, 'No missions joined yet.'.tr)];
        }
        final rows = <(String, String)>[];
        for (final m in missions.take(3)) {
          if (m is Map) {
            // Two things were reaching the user raw here.
            //
            // `signup_status` is a backend enum — 'approved', 'no_show',
            // 'completion_requested' — and was printed verbatim, so the
            // assistant answered an Arabic reader in English snake_case.
            // localizedTag translates the ones we know and humanises anything
            // the server adds later, instead of leaking the token.
            //
            // The hours carried a Latin "h" for a unit. The count itself is
            // isolated (U+2066/U+2069) before it goes into the phrase because
            // it lands between a bidi-neutral '·' and an Arabic word, which is
            // exactly the run the bidi algorithm reorders.
            final status = localizedTag(m['signup_status']);
            final hours = '@count hours'.trParams({
              // Written as escapes: the literal marks are invisible in a diff.
              'count': '\u2066${m['hours_served'] ?? 0}\u2069',
            });
            rows.add((
              localizedContentFromMap(Map<String, dynamic>.from(m), 'title'),
              status.isEmpty ? hours : '$status · $hours',
            ));
          }
        }
        return rows;

      default:
        return null;
    }
  }

  String _money(dynamic v) {
    final n = num.tryParse('${v ?? 0}') ?? 0;
    return '${NumberFormat.decimalPattern().format(n)} ${localizedCurrency('IQD')}';
  }
}
