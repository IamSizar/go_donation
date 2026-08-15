// The donor's giving TYPE — General / Zakat / Sadaqah, and whatever staff add
// after them — as a field that asks the server what the choices are.
//
// WHY THIS WIDGET EXISTS
// Migration 103 turned this taxonomy into rows behind `GET /api/donation-types`
// specifically so a fourth type would not need a code change and a redeploy.
// The app then kept its own hardcoded copy: `_DonationTypeSelector` in
// continue_donation_screen.dart listed general / zakat / sadaqah as three
// `const` entries. A type added from the dashboard was accepted by the server,
// stored correctly, and never offered to a donor — the same defect the
// migration removed, one layer up.
//
// FOUR STATES, AND WHY THE ERROR ONE DOES NOT BLOCK CHECKOUT
// This is a field inside a form, not a page. A failure here must be visible
// and recoverable, but it must not stop someone giving money: the server
// resolves an unknown or absent type to `general` itself
// (donations.normalizeDonationType), so a donation submitted while this field
// is in its error state is still filed correctly. The banner therefore sits in
// the field's own space with a retry, and the form stays submittable.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/donation_types_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

/// A chip row of the donation types the organization currently offers.
class DonationTypeField extends StatefulWidget {
  const DonationTypeField({
    super.key,
    required this.selectedSlug,
    required this.accentColor,
    required this.onSelected,
  });

  /// The slug currently chosen, as held by the checkout form.
  final String selectedSlug;

  final Color accentColor;

  /// Fired on a tap, and once after the first successful load when the held
  /// slug is not among the offered types — so the form never submits a type
  /// the organization has retired.
  final ValueChanged<String> onSelected;

  @override
  State<DonationTypeField> createState() => _DonationTypeFieldState();
}

class _DonationTypeFieldState extends State<DonationTypeField> {
  bool _loading = true;
  String? _error;
  List<DonationType> _types = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_error != null) setState(() => _error = null);
    try {
      final types = await fetchDonationTypes();
      if (!mounted) return;
      setState(() {
        _types = types;
        _loading = false;
      });
      // Re-point the form at something that exists. Staff can deactivate a
      // type, and a donation carrying a retired slug would be filed under the
      // server's fallback without the donor ever being told.
      if (types.isNotEmpty &&
          !types.any((t) => t.slug == widget.selectedSlug)) {
        widget.onSelected(types.first.slug);
      }
    } catch (e) {
      debugPrint('DonationTypeField: donation types unavailable: $e');
      if (!mounted) return;
      setState(() {
        _error = 'We could not load the donation types.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _TypeChipsSkeleton();
    // Error before empty: a failed read must not be shown as "no types exist".
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (_types.isEmpty) return const _NoTypesNote();

    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final type in _types)
          _DonationTypeChip(
            type: type,
            selected: type.slug == widget.selectedSlug,
            accentColor: widget.accentColor,
            onTap: () {
              AppHaptics.selection();
              widget.onSelected(type.slug);
            },
          ),
      ],
    );
  }
}

/// One selectable type.
class _DonationTypeChip extends StatelessWidget {
  const _DonationTypeChip({
    required this.type,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final DonationType type;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  /// The three shipped types keep the glyphs they have always had; anything
  /// staff add later gets the neutral giving mark.
  ///
  /// This is presentation only — the LIST comes from the server. An icon is
  /// the one thing a database row cannot carry, and leaving new types
  /// unillustrated would make them look like second-class entries beside the
  /// three seeded ones.
  IconData get _icon => switch (type.slug) {
    'zakat' => Icons.mosque,
    'sadaqah' => Icons.favorite_rounded,
    _ => Icons.volunteer_activism_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.snapDuration),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.14)
                : AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accentColor : AppThemeConfig.border(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                size: 20,
                color: selected
                    ? accentColor
                    : AppThemeConfig.mutedText(context),
              ),
              const SizedBox(width: AppSpace.xs),
              Text(
                // The name is server content in four languages, not a
                // translation key — `.tr` would return the key unchanged.
                type.localizedName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: selected
                      ? AppThemeConfig.text(context)
                      : AppThemeConfig.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The empty state: the catalogue answered, and it is empty.
///
/// Reachable — staff can deactivate every type — and honest about the
/// consequence: the donation still goes through, filed under the general fund
/// by the server, so this explains rather than alarms.
class _NoTypesNote extends StatelessWidget {
  const _NoTypesNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No donation type has been published yet, so this gift will be recorded as a general donation.'
          .tr,
      style: TextStyle(
        fontSize: AppType.dense,
        height: AppType.leadBody,
        color: AppThemeConfig.mutedText(context),
      ),
    );
  }
}

/// Placeholder shaped like the chip row it replaces.
class _TypeChipsSkeleton extends StatelessWidget {
  const _TypeChipsSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          // Three bones, matching the three types every install starts with.
          for (final width in <double>[104, 92, 108])
            Container(
              width: width,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.of(context).groundSunken,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}
