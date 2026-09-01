// SupportChatUnavailableNotice — what the app says when no staff account is
// nominated to receive support chats.
//
// It lives here, and not on the screen that first needed it, because there are
// TWO doors to support chat: the Messages screen and the events section's
// "Message the staff team". They hit the same endpoint and get the same 503,
// so they owe the user the same answer. The second door used to give a generic
// "couldn't send, try again — and if it keeps happening, contact support",
// which is both a retry that cannot work and an instruction to do the thing
// the button was for.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';

/// Shown when no staff account is configured to receive support chats.
///
/// Says what happened, then hands over the channels that work. It is not an
/// error state: nothing has gone wrong from the user's side, there is nothing
/// for them to retry, and the thing they actually wanted — to reach support —
/// is still entirely possible.
class SupportChatUnavailableNotice extends StatelessWidget {
  const SupportChatUnavailableNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        border: Border.all(color: AppThemeConfig.border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat_support_unavailable_title'.tr,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppThemeConfig.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'chat_support_unavailable_body'.tr,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
          const SizedBox(height: 12),
          // Full-width so it reads as the way forward rather than a footnote.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Get.to(() => const TechnicalSupportScreen()),
              child: Text('chat_support_unavailable_action'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
