import 'package:flutter/material.dart';

/// A single FAQ entry for the support bot — used both to render the suggestion
/// chips and as the on-device offline fallback when the backend is unreachable.
///
/// [keywords] are matched (lowercased) against the user's free-typed input so
/// the bot can respond to natural-language questions as well as chip taps.
///
/// [actionLabel] + [actionRoute] provide an optional CTA button. [actionRoute]
/// is a route key resolved by BotNavigation (e.g. "edit_profile", "marriage",
/// "donate") — so offline answers do FULL routing to the right screen, exactly
/// like the AI-backed replies.
class BotQA {
  const BotQA({
    required this.id,
    required this.icon,
    required this.question,
    required this.answer,
    required this.keywords,
    this.actionLabel,
    this.actionRoute,
    this.questionsByLang,
    this.answersByLang,
    this.keywordsByLang,
  });

  /// Unique key — used to look up the QA in keyword search results.
  final String id;

  /// Icon shown on the suggestion chip.
  final IconData icon;

  /// The question shown as a user bubble when the chip is tapped (English).
  final String question;

  /// The bot's answer shown in the bot bubble (English).
  final String answer;

  /// Lowercase words matched against free-typed user messages (English).
  final List<String> keywords;

  /// Label for the action button shown inside the bot bubble.  Null = no button.
  final String? actionLabel;

  /// Route key (BotNavigation) to navigate to when the CTA is tapped.
  final String? actionRoute;

  /// Per-language question text, keyed by locale ("ar", "ckb", "kmr").
  final Map<String, String>? questionsByLang;

  /// Per-language answer text, keyed by locale ("ar", "ckb", "kmr").
  final Map<String, String>? answersByLang;

  /// Per-language keyword lists, keyed by locale ("ar", "ckb", "kmr").
  final Map<String, List<String>>? keywordsByLang;

  /// The question in [lang], falling back to the English [question].
  String questionFor(String lang) {
    if (lang != 'en' && questionsByLang != null) {
      final q = questionsByLang![lang];
      if (q != null && q.isNotEmpty) return q;
    }
    return question;
  }

  /// The answer in [lang], falling back to the English [answer].
  String answerFor(String lang) {
    if (lang != 'en' && answersByLang != null) {
      final a = answersByLang![lang];
      if (a != null && a.isNotEmpty) return a;
    }
    return answer;
  }

  /// The keyword list for [lang], falling back to the English [keywords].
  List<String> keywordsFor(String lang) {
    if (lang != 'en' && keywordsByLang != null) {
      final k = keywordsByLang![lang];
      if (k != null && k.isNotEmpty) return k;
    }
    return keywords;
  }
}
