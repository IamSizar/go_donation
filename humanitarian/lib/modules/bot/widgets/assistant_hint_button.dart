// The AI icon that sits beside each section header.
//
// WHY THIS FILE EXISTS (K28)
// The client asked for an AI chatbot AND "an AI icon beside each menu offering
// a short explanation of that section and answering FAQs". The chatbot half was
// built and is genuinely good. The icon half was not: `BotChatScreen` had one
// entry point in the whole app — a card at the top of الرسائل — so someone
// standing on دليل المدينة wondering what it was had nowhere to ask.
//
// HOW THE TOPIC IS RESOLVED, AND WHY IT NEEDED NO NEW DATA
// `BotNavigation` already keys every destination ('donate', 'market',
// 'kafala', …), and every `BotQA` that leads somewhere carries the matching
// `actionRoute` — in four languages, per role, with an offline answer. So the
// section's own question is already written; it only had to be looked up.
// Nothing here introduces a second mapping table to fall out of sync, and no
// new Kurdish was invented: the button's label is the assistant's own name,
// which `BotStrings` already translates.

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/bot/data/bot_questions.dart';
import 'package:flutter_application_1/modules/bot/data/bot_strings.dart';
import 'package:flutter_application_1/modules/bot/screens/bot_chat_screen.dart';
import 'package:get/get.dart';

/// The question to open the assistant with for one section, and the stable
/// intent id that lets the offline engine answer it without keyword matching.
class AssistantTopic {
  const AssistantTopic({required this.intentId, required this.question});

  /// The `BotQA.id`, e.g. `d_market`. Language-independent.
  final String intentId;

  /// The question as the reader's own language phrases it. It is sent as the
  /// user's first turn, so it has to read like something they would type.
  final String question;
}

/// Finds the question this role would ask about the section behind [route].
///
/// Returns NULL when the current role's FAQ table has nothing for that
/// section, and that is the important case. `AssistantController` resolves an
/// offline answer by searching `getBotQAs(roleId)` only, so seeding another
/// role's intent would open the assistant on its "I didn't understand that"
/// bubble — a worse greeting than no greeting. The button then opens the
/// assistant on its normal welcome, whose suggestion chips are that role's
/// real FAQs, which still answers the client's ask.
AssistantTopic? assistantTopicFor(
  String route, {
  required String roleId,
  required String lang,
}) {
  if (route.trim().isEmpty) return null;
  for (final qa in getBotQAs(roleId)) {
    if (qa.actionRoute == route) {
      return AssistantTopic(intentId: qa.id, question: qa.questionFor(lang));
    }
  }
  return null;
}

/// A small AI glyph, sized to sit in a section header next to the title.
///
/// Deliberately not a floating button or a banner: the client asked for an
/// icon *beside each menu*, and a header affordance is the one place that is
/// true on every screen without competing with the screen's own content.
class AssistantHintButton extends StatelessWidget {
  const AssistantHintButton({super.key, required this.route});

  /// A `BotNavigation` route key naming the section this button sits on.
  final String route;

  void _open() {
    AppHaptics.selection();
    final roleId = sharedPreferences.getString('role_id') ?? '1';
    final lang = AppLocaleService.assistantLang();
    Get.to(
      () => BotChatScreen(
        opening: assistantTopicFor(route, roleId: roleId, lang: lang),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // The assistant's own translated name, in all four languages already.
    final label = BotStrings.of('title', AppLocaleService.assistantLang());

    return AppPressable(
      onTap: _open,
      semanticLabel: label,
      child: Tooltip(
        message: label,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.auto_awesome_rounded, size: 17, color: c.accent),
        ),
      ),
    );
  }
}
