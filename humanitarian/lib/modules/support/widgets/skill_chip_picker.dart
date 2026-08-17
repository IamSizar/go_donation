// Phase 26 — structured skill picker for the volunteer application form.
//
// v3 design (Phase 26.2): the inline grid of 28 chips made the form
// way too tall, so we collapsed the picker into a single trigger row
// (SkillPickerField) that opens a searchable bottom-sheet (_SkillPickerSheet)
// when tapped. Selected chips render inline below the trigger with a
// tap-to-remove ✕ on each, so the volunteer can see and prune their
// picks without re-opening the sheet.
//
// The old inline SkillChipPicker is kept exported for any caller that
// has plenty of vertical space (admin SPA preview, future settings page).
//
// Internal lookup tables stay in this file so the pure-data catalogue
// (lib/data/skill_catalogue.dart) doesn't have to import flutter/material.

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/contrast.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/data/skill_catalogue.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/design/motion.dart';

/// Per-skill Material icon. Keyed by the canonical catalogue key.
const Map<String, IconData> _skillIcons = {
  // transport
  'driver_car': Icons.directions_car_rounded,
  'driver_truck': Icons.local_shipping_rounded,
  'motorcycle': Icons.two_wheeler_rounded,
  // trades
  'electrician': Icons.electrical_services_rounded,
  'plumber': Icons.plumbing_rounded,
  'carpenter': Icons.carpenter_rounded,
  'mason': Icons.foundation_rounded,
  'mechanic': Icons.build_rounded,
  // medical
  'first_aid': Icons.healing_rounded,
  'nurse': Icons.medication_rounded,
  'doctor': Icons.local_hospital_rounded,
  'mental_health': Icons.psychology_rounded,
  'eldercare': Icons.elderly_rounded,
  // service
  'cook': Icons.restaurant_rounded,
  'cleaner': Icons.cleaning_services_rounded,
  'tailor': Icons.checkroom_rounded,
  // office / digital
  'designer': Icons.brush_rounded,
  'photographer': Icons.camera_alt_rounded,
  'videographer': Icons.videocam_rounded,
  'social_media': Icons.share_rounded,
  'it_support': Icons.computer_rounded,
  'data_entry': Icons.keyboard_rounded,
  // teaching / language
  'teacher': Icons.school_rounded,
  'translator_ar': Icons.translate_rounded,
  'translator_en': Icons.translate_rounded,
  'counselor': Icons.support_agent_rounded,
  // field work
  'distribution': Icons.inventory_2_rounded,
  'survey': Icons.assignment_rounded,
  'logistics': Icons.route_rounded,
  'warehouse': Icons.warehouse_rounded,
};

/// Per-category styling — icon + accent color used for the card tint,
/// chip outline, and selected-state fill.
///
/// These seven hues are the category's IDENTITY, not a text colour. They are
/// what makes النقل readable-at-a-glance as a different thing from طبي, so
/// they are never adjusted — every fill, wash, and border below uses the raw
/// hue. What IS adjusted is the ink drawn on top of them, via
/// [skillCategoryInk] and friends. See
/// test/design/skill_chip_contrast_test.dart.
class _CategoryStyle {
  const _CategoryStyle({required this.icon, required this.color});
  final IconData icon;
  final Color color;
}

const Map<String, _CategoryStyle> _categoryStyle = {
  'transport': _CategoryStyle(
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF4F46E5),
  ), // indigo
  'trades': _CategoryStyle(
    icon: Icons.construction_rounded,
    color: Color(0xFFEA580C),
  ), // orange
  'medical': _CategoryStyle(
    icon: Icons.medical_services_rounded,
    color: Color(0xFFDC2626),
  ), // red
  'service': _CategoryStyle(
    icon: Icons.room_service_rounded,
    color: Color(0xFF2F5D4A),
  ), // brand
  'office': _CategoryStyle(
    icon: Icons.laptop_mac_rounded,
    color: Color(0xFF7C3AED),
  ), // purple
  'teaching': _CategoryStyle(
    icon: Icons.menu_book_rounded,
    color: Color(0xFF16A34A),
  ), // green
  'field': _CategoryStyle(
    icon: Icons.terrain_rounded,
    color: Color(0xFF92400E),
  ), // brown
};

// ─── Readable ink on the category hues ──────────────────────────────────────
//
// WHY THIS BLOCK EXISTS
// Every label in this file used to be drawn in the raw category hue on a 6%
// wash of that same hue. Measured against the real composite, 8 of 14
// hue×theme pairs missed WCAG's 4.5:1 text floor — brand green at 2.33:1 and
// indigo at 2.79:1 in dark, orange at 3.03:1 and green at 2.82:1 in light.
// The white-on-solid selected pill missed it too, on orange (3.56:1) and
// green (3.30:1).
//
// The fix mirrors the community-services category pills: hold every hue byte
// identical and derive the INK from the maths, so an eighth category added
// later is compliant by construction rather than by luck.

/// How much of the category hue tints a category card.
const double _kCategoryWash = 0.06;

/// The header icon's rounded tile, washed ON TOP of the card wash.
const double _kIconTileWash = 0.14;

/// How much of the hue tints an inline preview chip on the form.
const double _kPreviewWash = 0.10;

/// The seven category accents, keyed by catalogue category key.
///
/// Exposed so the contrast guard measures the hues the screen actually draws
/// rather than a copy that can drift out of step with them.
@visibleForTesting
Map<String, Color> get skillCategoryAccents => {
  for (final entry in _categoryStyle.entries) entry.key: entry.value.color,
};

/// A category card's opaque fill: the hue washed over [surface] beneath it.
///
/// Opaque on purpose — contrast is only defined between opaque colours, and
/// measuring the translucent wash instead of the composite is exactly how a
/// chip can look measured without being measured.
@visibleForTesting
Color skillCategoryFill(Color accent, Color surface) =>
    Color.alphaBlend(accent.withValues(alpha: _kCategoryWash), surface);

/// TEXT colour for the category heading and for an UNSELECTED chip's label —
/// the hue, made readable on the card fill both of them sit on.
///
/// 13px w500 (chip) and 15px w700 (heading) are both ordinary body text —
/// WCAG's large-text exemption starts at 18.66px bold — so 4.5:1 is the bar.
@visibleForTesting
Color skillCategoryInk(Color accent, Color surface, Color ink) => readableOn(
  tint: accent,
  background: skillCategoryFill(accent, surface),
  ink: ink,
);

/// ICON colour for the category header glyph inside its 14% tile.
///
/// Held to 3.0:1, not 4.5:1: the glyph sits immediately beside the category
/// name and says the same thing, so it is decoration over text that already
/// carries the meaning. Raw hue measured as low as 2.13:1 there, below even
/// that floor, which is why it is corrected at all.
@visibleForTesting
Color skillCategoryIconInk(Color accent, Color surface, Color ink) =>
    readableOn(
      tint: accent,
      background: Color.alphaBlend(
        accent.withValues(alpha: _kIconTileWash),
        skillCategoryFill(accent, surface),
      ),
      ink: ink,
      minRatio: 3.0,
    );

/// Ink for anything drawn ON a solid accent: a SELECTED chip, the count badge.
///
/// Was hardcoded white, which fails on the two brightest hues — 3.56:1 on
/// orange and 3.30:1 on green. [inkOn] keeps white on the five hues where it
/// already wins and flips to the near-black ink on those two (5.02:1, 5.42:1).
/// The FILL stays the raw hue, so the category still reads as itself.
@visibleForTesting
Color skillSelectedInk(Color accent) => inkOn(accent);

/// An inline preview chip's opaque fill on the form's card surface.
@visibleForTesting
Color skillPreviewFill(Color accent, Color card) =>
    Color.alphaBlend(accent.withValues(alpha: _kPreviewWash), card);

/// TEXT colour for an inline preview chip's label. 12px w600 — body text.
@visibleForTesting
Color skillPreviewInk(Color accent, Color card, Color ink) => readableOn(
  tint: accent,
  background: skillPreviewFill(accent, card),
  ink: ink,
);

/// Colour of a preview chip's ✕ button.
///
/// 3.0:1, the floor for meaningful non-text UI: unlike the header glyph this
/// one is not decorative — it is the only affordance that says "tap here to
/// drop this skill", and no adjacent text repeats it.
///
/// The 70% fade is kept as the starting point rather than discarded, so a hue
/// whose faded ✕ already clears the floor keeps the lighter weight the design
/// intended; only the ones that miss get nudged.
@visibleForTesting
Color skillPreviewRemoveInk(Color accent, Color card, Color ink) {
  final fill = skillPreviewFill(accent, card);
  return readableOn(
    tint: Color.alphaBlend(accent.withValues(alpha: 0.70), fill),
    background: fill,
    ink: ink,
    minRatio: 3.0,
  );
}

class SkillChipPicker extends StatelessWidget {
  const SkillChipPicker({
    super.key,
    required this.selectedKeys,
    required this.onChanged,
  });

  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onChanged;

  /// GetX exposes locale via .languageCode + .scriptCode; flatten back to
  /// the single tag the catalogue understands.
  String _resolveLocale() {
    final code = Get.locale?.languageCode ?? 'en';
    final script = Get.locale?.scriptCode;
    if (script == 'Arab') return 'ckb';
    if (script == 'Latn' && code == 'ku') return 'kmr';
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final locale = _resolveLocale();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top summary strip — shows count + clear-all when anything's picked.
        if (selectedKeys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '@n selected'.trParams({'n': '${selectedKeys.length}'}),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => onChanged(<String>{}),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('Clear'.tr),
                ),
              ],
            ),
          ),
        ...kSkillCategories.map(
          (cat) => _CategoryCard(
            category: cat,
            locale: locale,
            selectedKeys: selectedKeys,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// One category's card: tinted background, header row with icon + count
/// badge, then a wrap of chips below.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.locale,
    required this.selectedKeys,
    required this.onChanged,
  });

  final SkillCategory category;
  final String locale;
  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // Fallback to a neutral accent if catalogue grows a category we
    // haven't styled yet — keeps the chip rendering sane.
    final style =
        _categoryStyle[category.key] ??
        _CategoryStyle(
          icon: Icons.work_outline_rounded,
          color: Theme.of(context).colorScheme.primary,
        );
    final accent = style.color;
    // The inline picker is embedded in a GlassPanel, which paints `card`;
    // that is the opaque colour the 6% wash actually composites over.
    final colors = AppColors.of(context);
    final surface = colors.card;
    final headingInk = skillCategoryInk(accent, surface, colors.ink);
    final iconInk = skillCategoryIconInk(accent, surface, colors.ink);
    final pickedCount = category.skills
        .where((s) => selectedKeys.contains(s.key))
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: _kCategoryWash),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: _kIconTileWash),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 18, color: iconInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.labelFor(locale),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: headingInk,
                  ),
                ),
              ),
              if (pickedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$pickedCount',
                    style: TextStyle(
                      color: skillSelectedInk(accent),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: category.skills
                .map((skill) {
                  final isSelected = selectedKeys.contains(skill.key);
                  final icon =
                      _skillIcons[skill.key] ?? Icons.work_outline_rounded;
                  return _SkillPill(
                    label: skill.labelFor(locale),
                    icon: icon,
                    accent: accent,
                    ink: headingInk,
                    selected: isSelected,
                    onTap: () {
                      final next = Set<String>.from(selectedKeys);
                      if (isSelected) {
                        next.remove(skill.key);
                      } else {
                        next.add(skill.key);
                      }
                      onChanged(next);
                    },
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

/// A single skill pill. Animates between selected (filled) and unselected
/// (outlined) on tap. Replaces FilterChip so we get full control over
/// the icon placement, border weight, and ink color.
class _SkillPill extends StatelessWidget {
  const _SkillPill({
    required this.label,
    required this.icon,
    required this.accent,
    required this.ink,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// The category hue. Drives the fill and border only — never the text.
  final Color accent;

  /// Label colour while UNSELECTED: [accent] made readable on the category
  /// card behind this chip, computed by the parent because only the parent
  /// knows which opaque surface that card composites over.
  final Color ink;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Selected: ink chosen against the solid accent (white loses on the two
    // brightest hues). Unselected: the pre-corrected category ink. The chip
    // icon repeats the label beside it, so it simply shares the label's
    // colour rather than being measured separately.
    final fg = selected ? skillSelectedInk(accent) : ink;
    final bg = selected ? accent : Colors.transparent;
    final border = selected ? accent : accent.withValues(alpha: 0.40);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        splashColor: accent.withValues(alpha: 0.18),
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.snapDuration),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SkillPickerField — compact trigger + bottom-sheet picker
// ============================================================================

/// Default skill picker for forms. Renders a single tappable trigger row;
/// on tap, opens a 85%-height bottom sheet with a search box, grouped
/// category sections, and a sticky footer showing selected count. Picked
/// skills appear as removable chips inline under the trigger.
///
/// API matches SkillChipPicker so callers can swap one for the other.
class SkillPickerField extends StatelessWidget {
  const SkillPickerField({
    super.key,
    required this.selectedKeys,
    required this.onChanged,
  });

  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onChanged;

  String _resolveLocale() {
    final code = Get.locale?.languageCode ?? 'en';
    final script = Get.locale?.scriptCode;
    if (script == 'Arab') return 'ckb';
    if (script == 'Latn' && code == 'ku') return 'kmr';
    return code;
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // We let the sheet draw its own rounded top + drag handle for
      // tighter control over the layout.
      builder: (ctx) =>
          _SkillPickerSheet(initial: selectedKeys, onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = _resolveLocale();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final count = selectedKeys.length;
    final hasPicks = count > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Trigger row ----
        Material(
          color: hasPicks
              ? primary.withValues(alpha: 0.05)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _openSheet(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primary.withValues(alpha: hasPicks ? 0.45 : 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      hasPicks
                          ? Icons.edit_rounded
                          : Icons.add_circle_outline_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasPicks
                              ? '@n skill@s picked'.trParams({
                                  'n': '$count',
                                  's': count == 1 ? '' : 's',
                                })
                              : 'Pick your skills'.tr,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasPicks
                              ? 'Tap to add or remove'.tr
                              : 'Browse 28 skills across 7 categories'.tr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.disabledColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    AppIcons.chevronForward(context),
                    color: primary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ---- Selected chip preview (tap ✕ to remove without re-opening) ----
        if (hasPicks) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selectedKeys
                .map((key) {
                  final entry = findSkillByKey(key);
                  if (entry == null) return const SizedBox.shrink();
                  final accent = _accentForKey(key);
                  final icon = _skillIcons[key] ?? Icons.work_outline_rounded;
                  return _RemovableChip(
                    label: entry.labelFor(locale),
                    icon: icon,
                    accent: accent,
                    onRemove: () {
                      final next = Set<String>.from(selectedKeys)..remove(key);
                      onChanged(next);
                    },
                  );
                })
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

/// Look up which category a skill key belongs to and return that
/// category's accent color. Used so the inline preview chips match the
/// colors the volunteer just saw in the sheet.
Color _accentForKey(String key) {
  for (final cat in kSkillCategories) {
    for (final s in cat.skills) {
      if (s.key == key) {
        return _categoryStyle[cat.key]?.color ?? const Color(0xFF6B7280);
      }
    }
  }
  return const Color(0xFF6B7280);
}

/// A pill chip with a trailing ✕. Tap the X to remove from selection.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onRemove,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // These chips render under the picker trigger inside the form's
    // GlassPanel, so the 10% wash composites over `card`.
    final colors = AppColors.of(context);
    final labelInk = skillPreviewInk(accent, colors.card, colors.ink);
    final removeInk = skillPreviewRemoveInk(accent, colors.card, colors.ink);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: _kPreviewWash),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: labelInk),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: labelInk,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 14, color: removeInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom-sheet body that lets the volunteer search + toggle skills.
/// Keeps a local mirror of the parent's selection so search filtering
/// stays fast; every toggle bubbles up via `onChanged` so the parent
/// (and inline preview chips) stay in sync live — closing the sheet
/// doesn't "save" anything that wasn't already committed.
class _SkillPickerSheet extends StatefulWidget {
  const _SkillPickerSheet({required this.initial, required this.onChanged});

  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends State<_SkillPickerSheet> {
  late final Set<String> _local = Set<String>.from(widget.initial);
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _resolveLocale() {
    final code = Get.locale?.languageCode ?? 'en';
    final script = Get.locale?.scriptCode;
    if (script == 'Arab') return 'ckb';
    if (script == 'Latn' && code == 'ku') return 'kmr';
    return code;
  }

  bool _matchesQuery(SkillEntry s) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    // Match across all 4 languages + key so the volunteer can search in
    // their preferred script and still find a chip.
    return s.en.toLowerCase().contains(q) ||
        s.ar.toLowerCase().contains(q) ||
        s.ckb.toLowerCase().contains(q) ||
        s.kmr.toLowerCase().contains(q) ||
        s.key.toLowerCase().contains(q);
  }

  void _toggle(String key) {
    setState(() {
      if (_local.contains(key)) {
        _local.remove(key);
      } else {
        _local.add(key);
      }
    });
    widget.onChanged(_local);
  }

  void _clearAll() {
    setState(() => _local.clear());
    widget.onChanged(_local);
  }

  @override
  Widget build(BuildContext context) {
    final locale = _resolveLocale();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final mediaQ = MediaQuery.of(context);

    final visibleByCategory = <String, List<SkillEntry>>{};
    int totalVisible = 0;
    for (final cat in kSkillCategories) {
      final m = cat.skills.where(_matchesQuery).toList(growable: false);
      visibleByCategory[cat.key] = m;
      totalVisible += m.length;
    }

    return Padding(
      // Lift the sheet above the on-screen keyboard when search is focused.
      padding: EdgeInsets.only(bottom: mediaQ.viewInsets.bottom),
      child: Container(
        height: mediaQ.size.height * 0.85,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pick your skills'.tr,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Done'.tr),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search skills (try "driver" or "nurse")'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Category list — or empty state when search hits nothing
            Expanded(
              child: totalVisible == 0
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 40,
                              color: theme.disabledColor,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No skills match "@q"'.trParams({'q': _query}),
                              style: TextStyle(color: theme.disabledColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: kSkillCategories
                          .where(
                            (c) => (visibleByCategory[c.key] ?? const [])
                                .isNotEmpty,
                          )
                          .map(
                            (cat) => _SheetCategoryBlock(
                              category: cat,
                              skills: visibleByCategory[cat.key] ?? const [],
                              locale: locale,
                              selectedKeys: _local,
                              onToggle: _toggle,
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
            // Sticky footer with count + clear-all
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                10 + mediaQ.padding.bottom,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: primary, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '@n selected'.trParams({'n': '${_local.length}'}),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  const Spacer(),
                  if (_local.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: Text('Clear all'.tr),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One category block inside the bottom sheet. Same shape as
/// _CategoryCard but takes a pre-filtered `skills` list (from the
/// search query) and an `onToggle(key)` callback instead of the
/// onChanged-with-set pattern.
class _SheetCategoryBlock extends StatelessWidget {
  const _SheetCategoryBlock({
    required this.category,
    required this.skills,
    required this.locale,
    required this.selectedKeys,
    required this.onToggle,
  });

  final SkillCategory category;
  final List<SkillEntry> skills;
  final String locale;
  final Set<String> selectedKeys;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final style =
        _categoryStyle[category.key] ??
        _CategoryStyle(
          icon: Icons.work_outline_rounded,
          color: Theme.of(context).colorScheme.primary,
        );
    final accent = style.color;
    // The sheet paints `theme.scaffoldBackgroundColor` (= ground) behind these
    // blocks, so that — not the page card — is what the 6% wash sits on.
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final surface = theme.scaffoldBackgroundColor;
    final headingInk = skillCategoryInk(accent, surface, colors.ink);
    final iconInk = skillCategoryIconInk(accent, surface, colors.ink);
    final pickedCount = skills
        .where((s) => selectedKeys.contains(s.key))
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: _kCategoryWash),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: _kIconTileWash),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 18, color: iconInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.labelFor(locale),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: headingInk,
                  ),
                ),
              ),
              if (pickedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$pickedCount',
                    style: TextStyle(
                      color: skillSelectedInk(accent),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills
                .map((skill) {
                  final isSelected = selectedKeys.contains(skill.key);
                  final icon =
                      _skillIcons[skill.key] ?? Icons.work_outline_rounded;
                  return _SkillPill(
                    label: skill.labelFor(locale),
                    icon: icon,
                    accent: accent,
                    ink: headingInk,
                    selected: isSelected,
                    onTap: () => onToggle(skill.key),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}
