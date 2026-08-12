// The appearance control: System / Light / Dark.
//
// WHY THIS IS A WIDGET AND NOT TWO SWITCHES
// The app had two separate dark-mode switches — one in Settings, one in
// Profile — each rebuilding the same row from scratch. They were already
// drifting (different icon sizes, different paddings), and making both
// tri-state would have meant writing the three-way control twice. This is the
// one control; both screens embed it.
//
// WHY A SEGMENTED CONTROL RATHER THAN A SWITCH
// A switch can only express two states. Appearance has three, and the third
// (System) is the default and the one most users should stay on — it has to
// be visible, not hidden behind "off".
import 'package:flutter/material.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:get/get.dart';

/// One selectable appearance, paired with the icon and label that describe it.
class _ThemeOption {
  const _ThemeOption(this.mode, this.icon, this.label);

  final ThemeMode mode;
  final IconData icon;

  /// A translation KEY — callers apply `.tr`.
  final String label;
}

const List<_ThemeOption> _options = [
  // System first: it is the default, and reading order should put the
  // recommended choice first rather than bury it between the two overrides.
  _ThemeOption(ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
  _ThemeOption(ThemeMode.light, Icons.light_mode_rounded, 'Light'),
  _ThemeOption(ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
];

/// A three-way appearance picker bound to [appThemeMode].
///
/// Writes through [setAppThemeMode], so the choice persists and applies to the
/// whole app immediately — there is no confirm step and nothing to save.
class AppThemeModePicker extends StatelessWidget {
  const AppThemeModePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, current, _) {
        return Row(
          children: [
            for (final option in _options) ...[
              Expanded(
                child: _ThemeSegment(
                  option: option,
                  selected: option.mode == current,
                  onTap: () {
                    if (option.mode == current) return;
                    AppHaptics.selection();
                    setAppThemeMode(option.mode);
                  },
                ),
              ),
              if (option != _options.last) const SizedBox(width: AppSpace.xs),
            ],
          ],
        );
      },
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeConfig.accent(context);
    // Foreground is onAccent on the selected fill, NOT Colors.white: the dark
    // palette's accent is a light mint, and white on it measures 2.19:1.
    final foreground = selected
        ? AppThemeConfig.onAccent(context)
        : AppThemeConfig.mutedText(context);

    return AppPressable(
      // The Expanded above has already decided this segment's width; without
      // `expand` the pressable would shrink-wrap to its label and the three
      // segments would render as narrow pills with gaps between them.
      expand: true,
      onTap: onTap,
      semanticLabel: option.label.tr,
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.snapDuration),
        curve: Curves.easeOut,
        // double.infinity, not just `expand` on the pressable above: the touch
        // target centres its child under LOOSE constraints, so a Container
        // with no width sizes to its Column and renders as a narrow pill in
        // the middle of its third. It has to claim the width itself.
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: selected ? accent : AppThemeConfig.softSurface(context),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? accent : AppThemeConfig.border(context),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(option.icon, size: 20, color: foreground),
            const SizedBox(height: 6),
            Text(
              option.label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: AppType.meta,
                fontWeight: AppType.wAction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
