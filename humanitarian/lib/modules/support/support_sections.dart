import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Support is split into two departments (client meeting): events
/// (قسم دعم خاص بالفعاليات) and volunteers (قسم دعم خاص بالمتطوعين). Each has its
/// own staff on the dashboard, so every ticket and support chat says which one
/// it is for.
///
/// Entry points that already know the department (the events section's tile,
/// the volunteers screen's tile) pass it straight through; the generic ones
/// (Messages, the ticket form, the profile menu) ask with [pickSupportSection].
const String kSupportSectionEvents = 'events';
const String kSupportSectionVolunteers = 'volunteers';
const List<String> kSupportSections = [
  kSupportSectionEvents,
  kSupportSectionVolunteers,
];

/// The translated department name, or null for a ticket / chat opened before
/// the split (it carries no section).
String? supportSectionLabel(Object? section) => switch ('$section') {
  kSupportSectionEvents => 'support_section_events'.tr,
  kSupportSectionVolunteers => 'support_section_volunteers'.tr,
  _ => null,
};

IconData supportSectionIcon(String section) => section == kSupportSectionEvents
    ? Icons.celebration_rounded
    : Icons.volunteer_activism_rounded;

/// Asks which department the user wants. Returns null when the sheet is
/// dismissed, in which case the caller does nothing.
Future<String?> pickSupportSection(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    // Sized to its content rather than capped at half the screen, and
    // scrollable, so two tiles plus a heading fit on a short phone.
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppThemeConfig.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
    ),
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'support_section_title'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(sheet),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'support_section_hint'.tr,
            style: TextStyle(color: AppThemeConfig.mutedText(sheet)),
          ),
          const SizedBox(height: 16),
          for (final s in kSupportSections) ...[
            SectionTile(
              icon: supportSectionIcon(s),
              title: 'support_section_$s',
              subtitle: 'support_section_${s}_desc',
              color: AppThemeConfig.accent(sheet),
              onTap: () => Navigator.of(sheet).pop(s),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

/// The ticket form's department choice: two chips side by side, nothing
/// preselected unless the screen was opened from a section that already knows.
class SupportSectionSelector extends StatelessWidget {
  const SupportSectionSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'support_section_title'.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final s in kSupportSections) ...[
              if (s != kSupportSections.first) const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  selected: value == s,
                  onSelected: (_) => onChanged(s),
                  avatar: Icon(supportSectionIcon(s), size: 18),
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      supportSectionLabel(s)!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  showCheckmark: false,
                ),
              ),
            ],
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
