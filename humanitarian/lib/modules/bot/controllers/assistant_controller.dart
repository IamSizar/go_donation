import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';

import '../bot_navigation.dart';
import '../data/bot_questions.dart';
import '../data/bot_strings.dart';
import '../models/bot_message.dart';
import '../models/bot_qa.dart';

/// Drives the AI Support Assistant conversation.
///
/// Calls the backend `/assistant/chat` endpoint, which answers with Claude when
/// an API key is configured server-side, or a keyword engine otherwise. If the
/// network call fails entirely, we fall back to the on-device [BotQA] table so
/// the assistant still responds offline.
class AssistantController extends GetxController {
  final messages = <BotMessage>[].obs;
  final isTyping = false.obs;

  // #36 — support WhatsApp handoff. The number is fetched once; the offer shows
  // once the user has sent at least 3 messages.
  final whatsappNumber = RxnString();
  static const int _whatsappAfterMessages = 3;

  late final String roleId;
  late final List<BotQA> suggestions;

  @override
  void onInit() {
    super.onInit();
    roleId = sharedPreferences.getString('role_id') ?? '1';
    suggestions = getBotQAs(roleId);
    _loadWhatsapp();
  }

  Future<void> _loadWhatsapp() async {
    whatsappNumber.value = await const ModuleApi().supportWhatsapp();
  }

  /// True once WhatsApp is configured AND the user has sent ≥3 messages.
  bool get showWhatsappOffer {
    final n = whatsappNumber.value;
    if (n == null || n.isEmpty) return false;
    return messages.where((m) => m.isUser).length >= _whatsappAfterMessages;
  }

  /// Minimum time the typing indicator stays on screen, so the "AI is thinking"
  /// animation is clearly visible — even when the local engine answers
  /// instantly (e.g. tapping a suggested question). Real network latency is
  /// absorbed into this window rather than added on top.
  static const int _minThinkMs = 1500;

  /// Sends [text] as a user turn and appends the assistant's reply.
  ///
  /// [intentID] is the stable chip id (e.g. `"d_donate"`) when the message
  /// originates from a suggestion-chip tap. Leave null for free-typed input.
  /// The backend uses it so the local fallback can resolve the intent directly
  /// without keyword matching — important once other languages are added.
  Future<void> send(String text, {String? intentID}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isTyping.value) return;

    // Show the user's message immediately, then the typing indicator.
    messages.add(BotMessage.user(trimmed));
    isTyping.value = true;

    final startedMs = DateTime.now().millisecondsSinceEpoch;

    // Current app locale as a canonical assistant code: en / ar / ckb / kmr.
    // Uses AppLocaleService (not languageCode) because Sorani and Badini both
    // reuse the "ar" language code and would otherwise be indistinguishable.
    final lang = AppLocaleService.assistantLang();

    // Resolve the reply (from backend, or on-device fallback) without adding it
    // to the list yet — we hold it back until the typing animation has shown.
    BotMessage reply;
    try {
      final history = messages
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();

      final payload = <String, dynamic>{
        'messages': history,
        'lang': lang,
      };
      if (intentID != null && intentID.isNotEmpty) {
        payload['intent_id'] = intentID;
      }

      final res = await const ModuleApi().postJson(
        assistantChatUrl,
        payload,
      );

      final replyText = (res['reply'] ?? '').toString().trim();
      String? label;
      String? route;
      final action = res['action'];
      if (action is Map) {
        label = action['label']?.toString();
        route = action['route']?.toString();
        if (route == 'none' || route == null || route.isEmpty) {
          label = null;
          route = null;
        }
      }

      reply = replyText.isEmpty
          ? _localFallbackMessage(trimmed, lang, intentID: intentID)
          : BotMessage.bot(replyText, actionLabel: label, actionRoute: route);
    } catch (_) {
      reply = _localFallbackMessage(trimmed, lang, intentID: intentID);
    }

    // Keep the typing bubble visible for at least _minThinkMs.
    final elapsed = DateTime.now().millisecondsSinceEpoch - startedMs;
    if (elapsed < _minThinkMs) {
      await Future.delayed(Duration(milliseconds: _minThinkMs - elapsed));
    }

    isTyping.value = false;
    messages.add(reply);
  }

  /// Offline answer in the user's [lang], routing to the same concrete screen
  /// the AI would. Mirrors the backend's local engine:
  ///   1. If [intentID] is set (chip tap), resolve the QA by stable id directly.
  ///   2. Otherwise keyword-match using the language-appropriate keyword list.
  /// The answer + CTA label are returned localized, falling back to English.
  BotMessage _localFallbackMessage(String query, String lang, {String? intentID}) {
    BotQA? match;

    // 1. Chip tap → resolve by id (language-independent, always exact).
    if (intentID != null && intentID.isNotEmpty) {
      for (final qa in suggestions) {
        if (qa.id == intentID) {
          match = qa;
          break;
        }
      }
    }

    // 2. Free-typed input → keyword-match in the current language.
    if (match == null) {
      final lower = query.toLowerCase();
      for (final qa in suggestions) {
        if (qa.keywordsFor(lang).any((k) => lower.contains(k.toLowerCase()))) {
          match = qa;
          break;
        }
      }
    }

    if (match == null) {
      return BotMessage.bot(BotStrings.of('error', lang), isError: true);
    }

    return BotMessage.bot(
      match.answerFor(lang),
      actionLabel: BotNavigation.localizedLabel(
        match.actionRoute,
        lang,
        match.actionLabel,
      ),
      actionRoute: match.actionRoute,
    );
  }
}
