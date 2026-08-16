// The inputs and the two notices that make up the owner's خطوبتي edit form
// (K14).
//
// WHY THEY LIVE HERE
// marriage_profile_edit_screen.dart is a form over eleven fields, and holding
// the field builders alongside the state, the validation and the save put it
// past this repo's 500-line ceiling. The split is by responsibility, not by
// line count: this file knows how one control looks, the screen knows what the
// controls mean together and what happens when they are saved.
//
// Nothing here talks to the network or to a controller — every widget takes
// its value and its callback, so the screen stays the only place that decides
// anything.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// A field's caption, above the control it names.
class MarriageEditLabel extends StatelessWidget {
  const MarriageEditLabel(this.translationKey, {super.key});

  final String translationKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      translationKey.tr,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

/// One text input.
///
/// [validator] is optional because most of these fields are free text with no
/// rule to break; the numeric ones pass one in. Validation re-runs on user
/// interaction rather than only on submit, so a rejected field clears itself as
/// soon as it is corrected instead of staying red until the next save.
class MarriageEditTextField extends StatelessWidget {
  const MarriageEditTextField({
    super.key,
    required this.controller,
    required this.labelKey,
    required this.icon,
    this.lines = 1,
    this.keyboard,
    this.validator,
  });

  final TextEditingController controller;
  final String labelKey;
  final IconData icon;
  final int lines;

  /// The keyboard this field deserves — the number pad for age/weight/height,
  /// the default for prose. Never left unset where a specific one exists.
  final TextInputType? keyboard;

  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: Key('marriage_owner_$labelKey'),
        controller: controller,
        keyboardType: keyboard,
        minLines: lines,
        maxLines: lines,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator,
        decoration: InputDecoration(
          labelText: labelKey.tr,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// One fixed-option field.
///
/// [labelOf] rather than a key prefix, because the three call sites label their
/// options differently — gender uses the option itself as the key, the other
/// two build `marital_status_*` / `employment_status_*`.
class MarriageEditDropdown extends StatelessWidget {
  const MarriageEditDropdown({
    super.key,
    required this.value,
    required this.hintKey,
    required this.icon,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final String? value;
  final String hintKey;
  final IconData icon;
  final List<String> options;
  final String Function(String) labelOf;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(prefixIcon: Icon(icon)),
      hint: Text(hintKey.tr),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(labelOf(option))),
      ],
      onChanged: (picked) {
        AppHaptics.selection();
        onChanged(picked);
      },
    );
  }
}

/// The profile photo: tap the avatar to replace it.
///
/// [resolvedUrl] is already absolute — resolving a stored relative path is the
/// screen's job, since it is the one that knows which host the row came from.
class MarriagePhotoField extends StatelessWidget {
  const MarriagePhotoField({
    super.key,
    required this.resolvedUrl,
    required this.uploading,
    required this.onPick,
  });

  final String resolvedUrl;

  /// True while an upload is in flight: the avatar refuses a second tap and
  /// shows its own progress, so one pick cannot become two uploads.
  final bool uploading;

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MarriageEditLabel('marriage_photo'),
        Center(
          child: AppPressable(
            onTap: uploading ? null : onPick,
            semanticLabel: 'marriage_photo'.tr,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppThemeConfig.softSurface(context),
                  backgroundImage: resolvedUrl.isNotEmpty
                      ? NetworkImage(resolvedUrl)
                      : null,
                  child: resolvedUrl.isEmpty
                      ? Icon(
                          Icons.add_a_photo_outlined,
                          size: 28,
                          color: AppThemeConfig.mutedText(context),
                        )
                      : null,
                ),
                if (uploading)
                  const CircularProgressIndicator.adaptive(strokeWidth: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Says which half of the profile the edit screen governs.
///
/// 5.9 — the boundary between "I change this" and "staff change this" is not
/// discoverable from a form that simply lacks the other fields, so it is
/// stated rather than implied. Without it the absent sections read as a
/// missing feature instead of a rule.
class MarriageStaffFieldsNote extends StatelessWidget {
  const MarriageStaffFieldsNote({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppThemeConfig.mutedText(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'marriage_owner_staff_fields_note'.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.5,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last save's failure, shown in the form, with the cause and nothing else.
///
/// Not an [AppErrorState]: that widget's contract is a failed LOAD with a
/// retry, and the retry here is the Save button the user is already looking at.
/// A second "try again" control beside it would be two ways to do one thing.
///
/// In the form rather than in a snackbar for the same reason: a message about a
/// field disappears before the user has finished re-reading the field.
class MarriageSaveFailure extends StatelessWidget {
  const MarriageSaveFailure({super.key, required this.message});

  /// Already localized. Never a server sentence or an exception string.
  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = AppThemeConfig.consequence(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                height: 1.45,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
