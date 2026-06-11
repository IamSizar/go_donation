import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/locale_service.dart';

import '../bot_navigation.dart';
import '../controllers/assistant_controller.dart';
import '../data/bot_strings.dart';
import '../models/bot_message.dart';
import '../models/bot_qa.dart';

/// A role-aware AI Support Assistant. Typed questions and chip taps are sent to
/// the backend `/assistant/chat` endpoint (Claude-backed when configured, a
/// keyword engine otherwise). Replies can carry a one-tap navigation action.
class BotChatScreen extends StatefulWidget {
  const BotChatScreen({super.key});

  @override
  State<BotChatScreen> createState() => _BotChatScreenState();
}

class _BotChatScreenState extends State<BotChatScreen> {
  final AssistantController ctrl = Get.put(AssistantController());
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll whenever the conversation grows or typing toggles. Both
    // events route through a single coalesced scroll so rapid updates (user
    // message + typing indicator in the same frame) don't fight each other.
    ever<List<BotMessage>>(ctrl.messages, (_) => _scrollToBottom());
    ever<bool>(ctrl.isTyping, (_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
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

  void _send(String text, {String? intentID}) {
    ctrl.send(text, intentID: intentID);
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
                    onTap: (qa) => _send(
                      qa.questionFor(lang),
                      intentID: qa.id,
                    ),
                  ),
                  for (final m in msgs) ...[
                    const SizedBox(height: 14),
                    if (m.isUser)
                      _UserBubble(text: m.text)
                    else
                      _BotBubble(
                        message: m,
                        onAction: m.hasAction
                            ? () => _navigate(m.actionRoute!)
                            : null,
                      ),
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
          _TapHint(lang: lang),
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
          Icons.arrow_back_ios_rounded,
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
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade400.withValues(alpha: 0.06),
            Colors.indigo.shade400.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
                  color: Colors.deepPurple.shade500,
                ),
                const SizedBox(width: 7),
                Text(
                  BotStrings.of('suggestionsHeader', lang),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.deepPurple.shade700,
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
                    color: Colors.deepPurple.shade500,
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
                  Icons.arrow_forward_ios_rounded,
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
      alignment: Alignment.centerRight,
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
                      icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                      label: Text(message.actionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade600,
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
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            alignment: Alignment.bottomLeft,
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
                      padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                      child: Transform.translate(
                        offset: Offset(0, -lift),
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.deepPurple.shade400.withValues(
                                    alpha: opacity,
                                  ),
                                  Colors.indigo.shade400.withValues(
                                    alpha: opacity,
                                  ),
                                ],
                              ),
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
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade600, Colors.indigo.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: iconSize),
    );
  }
}

// ─── Tap hint footer ──────────────────────────────────────────────────────────

/// Replaces the free-text input: this assistant is tap-only, so users pick from
/// the recommended questions rather than typing.
class _TapHint extends StatelessWidget {
  const _TapHint({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        border: Border(top: BorderSide(color: AppThemeConfig.border(context))),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        13,
        16,
        13 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 17,
            color: Colors.deepPurple.shade400,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              BotStrings.of('tapHint', lang),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
