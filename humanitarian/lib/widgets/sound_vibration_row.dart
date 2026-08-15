// Settings row: mute the app's sounds and vibration.
//
// WHY THIS FILE EXISTS (K26)
// The client asked for "full user control over sounds and vibration from an
// app-settings menu". The control had been built and worked — [AppMute]
// persists the choice and AppSound / AppHaptics / AppVoice each return early
// when it is set — but its only UI was a card on `ProfileSection`, and the one
// thing in the app that navigates there is the AI assistant's 'profile' deep
// link. A setting you can only reach by asking a chatbot is not in a settings
// menu, so from the user's side the feature was missing.
//
// This is the same control, given a row shaped like the ones it now sits
// beside (Language, Dark mode, Notifications) in the profile menu.
//
// WHY ITS OWN FILE
// `settings_section.dart` — the natural home by convention — is already 814
// lines, well past the 500-line ceiling. Adding a fourth preference row there
// would push it further in the wrong direction, so the row lives here and is
// imported where it is used.

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_mute.dart';
import 'package:flutter_application_1/core/app_voice.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

/// One settings row: "Mute sounds & vibration", bound directly to [AppMute].
///
/// Stateless on purpose. [AppMute.muted] is a [ValueNotifier], so this row and
/// the older card on `ProfileSection` observe the same value and can never
/// disagree about it — there is no second copy of the state to keep in sync.
///
/// Unlike [NotificationsRow] there is nothing to load and nothing that can
/// fail: the preference is local, written to SharedPreferences, and takes
/// effect immediately. That is why there is no loading, error or retry state
/// here — there is no async region to give one to.
class SoundVibrationRow extends StatelessWidget {
  const SoundVibrationRow({super.key});

  /// Applies the choice: persist it, and stop any summary already being read
  /// aloud so muting takes effect on the current utterance rather than the
  /// next one.
  Future<void> _apply(bool muted) async {
    await AppMute.set(muted);
    if (muted) {
      AppVoice.stop();
    } else {
      // Deliberately after the write, and only when un-muting: the tick is the
      // confirmation that haptics are back. Firing it while muting would be
      // suppressed by AppMute anyway — silence is the correct feedback there.
      AppHaptics.selection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppMute.muted,
      builder: (context, muted, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppThemeConfig.subtleText(
                    context,
                  ).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: AppThemeConfig.subtleText(context),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'mute_all'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // The label names the two things the client asked to
                    // control; this line names the third (spoken summaries),
                    // so nobody is surprised that muting also stops the voice.
                    Text(
                      'mute_all_desc'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Switch.adaptive(
                value: muted,
                activeThumbColor: AppThemeConfig.accent(context),
                onChanged: _apply,
              ),
            ],
          ),
        );
      },
    );
  }
}
