// One gender option on the profile-edit screen.
//
// WHY THIS IS ITS OWN WIDGET
// It was written inline, which made the thing worth testing — how it looks
// when it cannot be used — unreachable from a test without pumping the whole
// profile screen and its network calls. Pulling it out costs one small file
// and makes the locked state directly assertable.
//
// THE RULE IT ENFORCES
// Gender cannot be changed after sign-up. The chips were already inert, but
// they were painted with explicit colours that overrode Flutter's disabled
// treatment, so they still looked tappable. A control that invites a tap and
// then ignores it leaves the user unable to tell whether the app is broken,
// the tap missed, or the action is simply not allowed.
//
// The SELECTED chip keeps its normal appearance even when locked: it is not
// decoration, it is how the user reads their own recorded gender. Muting it
// into unreadability to signal "locked" would trade one defect for a worse one.
import 'package:flutter/material.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';

class GenderChoiceChip extends StatelessWidget {
  const GenderChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.locked,
    required this.onSelected,
  });

  /// The already-translated option text.
  final String label;

  /// Whether this option is the user's recorded gender.
  final bool selected;

  /// Whether the choice is fixed and no option may be picked.
  final bool locked;

  /// Called when the user picks this option. Ignored entirely while [locked].
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    // Unavailable options are muted; the recorded value is not, so it stays
    // readable at full contrast.
    // onAccent rather than a literal white: in dark mode the accent is a
    // light mint and white on it fails contrast. (The chip theme happened to
    // override the literal, so this rendered correctly by accident — which is
    // not a thing to rely on.)
    final labelColor = selected
        ? AppThemeConfig.onAccent(context)
        : locked
        ? AppThemeConfig.mutedText(context)
        : AppThemeConfig.text(context);

    final borderColor = selected
        ? AppThemeConfig.accent(context)
        : locked
        ? AppThemeConfig.border(context).withValues(alpha: 0.4)
        : AppThemeConfig.border(context);

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // Null is what actually makes the chip inert; the colours above are what
      // make that inertness visible.
      onSelected: locked ? null : (_) => onSelected(),
      labelStyle: TextStyle(
        color: labelColor,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: AppThemeConfig.accent(context),
      backgroundColor: AppThemeConfig.softSurface(context),
      // Without this, a disabled ChoiceChip falls back to the theme's disabled
      // colour and stops matching the rest of the form.
      disabledColor: AppThemeConfig.softSurface(context),
      side: BorderSide(color: borderColor),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}
