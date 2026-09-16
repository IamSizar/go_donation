// messages_support_tiles.dart — the support-bot door pinned at the top of the
// Messages tab.
//
// The support chat and ticket-form tiles stay inline in MessagesScreen,
// because they share its supportChatError / supportChatUnavailable notifiers
// and openSupportChat. Moved out of messages_screen.dart unchanged
// (OPOS #26495).
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/bot/screens/bot_chat_screen.dart';
import 'package:get/get.dart';

// ─── Support-bot entry card ───────────────────────────────────────────────────

/// A card pinned at the top of the Messages screen that opens the support bot.
class BotAssistantCard extends StatelessWidget {
  const BotAssistantCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 8),
      child: InkWell(
        onTap: () => Get.to(() => const BotChatScreen()),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeConfig.accent(context).withValues(alpha: 0.10),
            border: Border.all(
              color: Colors.deepPurple.withValues(alpha: 0.22),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppThemeConfig.accent(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: AppThemeConfig.onAccent(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Support Assistant'.tr,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppThemeConfig.accent(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ask me anything — I\'ll guide you through the app'.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronForward(context),
                color: AppThemeConfig.accent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
