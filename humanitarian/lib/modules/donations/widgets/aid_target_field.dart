// M4 — the fork between مساعدات عامة and التبرع حسب مشروع محدد.
//
// WHY THIS WIDGET EXISTS
// The client asks for a donation to branch into two named paths: general aid,
// which staff distribute by priority and real need, or a gift aimed at one
// named project — with projects hideable from the dashboard while the general
// donation stays available.
//
// Both destinations already worked. Neither was ever OFFERED as a choice.
// Checkout drew a bare project dropdown, so:
//
//   • General aid had no affordance at all. It was what you got by not
//     touching the dropdown — a default, not a decision, and nothing on screen
//     said your money would be distributed by need.
//   • The dropdown had no null item, so a donor who picked a project by
//     mistake could not get back to general aid without leaving the screen.
//     That is the client's own reproduction, word for word.
//   • And the list was loaded with a `catch` that hid the section on failure,
//     which was defensible while the picker was an optional refinement and
//     stops being defensible the moment there is a tile saying "donate to a
//     specific project". Tapping that and getting nothing is the C2 mistake
//     again: a control that asserts something exists and then shows nothing.
//
// FOUR STATES
// Loading, error-with-retry, and two settled states that are NOT errors —
// projects switched off from the dashboard, and projects switched on with none
// open. Both collapse to general aid and say so, because "the general donation
// stays available" is half of what M4 asks for.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/project_categories_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// Which of the two paths the donor is on.
enum AidTarget {
  /// مساعدات عامة — no category chosen; staff distribute by need.
  general,

  /// التبرع حسب مشروع محدد — one named project.
  project,
}

/// The two-way branch, plus the project picker the second path reveals.
class AidTargetField extends StatefulWidget {
  const AidTargetField({
    super.key,
    required this.selectedProject,
    required this.accentColor,
    required this.onChanged,
  });

  /// The project the form currently holds, or null for general aid.
  final ProjectCategory? selectedProject;

  final Color accentColor;

  /// Fired with the project to send, or null when the gift is general aid.
  ///
  /// The parent stores exactly what it will submit, so there is no second
  /// place where "which path is this on" could disagree with "what is being
  /// sent".
  final ValueChanged<ProjectCategory?> onChanged;

  @override
  State<AidTargetField> createState() => _AidTargetFieldState();
}

class _AidTargetFieldState extends State<AidTargetField> {
  bool _loading = true;
  String? _error;

  /// The dashboard switch. False means project donations are turned off and
  /// only general aid is on offer — which is a configured answer, not a
  /// failure and not an empty list.
  bool _projectsVisible = true;
  List<ProjectCategory> _projects = const [];

  /// Which tile is lit. Starts on general aid: it is the client's fallback for
  /// donors who "شعر المتبرعون بالحيرة بسبب كثرة الخيارات", and starting on a
  /// project would pick one for them.
  AidTarget _target = AidTarget.general;

  @override
  void initState() {
    super.initState();
    // A project already held by the form (the donor came back to this screen)
    // means they are on the project path.
    if (widget.selectedProject != null) _target = AidTarget.project;
    _load();
  }

  Future<void> _load() async {
    if (_error != null) setState(() => _error = null);
    try {
      // getDonationOptions never throws by design — it serves feature flags,
      // not the donor's data, and falls back to "everything on" internally.
      // So the failure this catch handles is the project list itself.
      final options = await const ModuleApi().getDonationOptions();
      final projects = options.projectsVisible
          ? await fetchProjectCategories()
          : const <ProjectCategory>[];
      if (!mounted) return;
      setState(() {
        _projectsVisible = options.projectsVisible;
        _projects = projects;
        _loading = false;
      });
      // The project the form was holding is no longer on offer — staff
      // retired it, or the flag was switched off. Drop it rather than submit
      // a slug the organization has withdrawn.
      final held = widget.selectedProject;
      if (held != null && _resolve(held) == null) {
        setState(() => _target = AidTarget.general);
        widget.onChanged(null);
      }
    } catch (e) {
      debugPrint('AidTargetField: project list unavailable: $e');
      if (!mounted) return;
      setState(() {
        _error = 'We could not load the projects.';
        _loading = false;
      });
    }
  }

  /// True when there is a real fork to offer.
  bool get _canOfferProjects => _projectsVisible && _projects.isNotEmpty;

  /// The instance IN [_projects] that stands for [held], matched by slug.
  ///
  /// Matching by slug rather than by object is load-bearing, and a widget test
  /// caught it: `ProjectCategory` has no `==`, so the instance the form is
  /// holding is never identical to a freshly fetched one. `DropdownButton`
  /// asserts that exactly one of its items equals its value, so handing it the
  /// held instance after any reload — a retry, or simply returning to this
  /// screen with a project already chosen — threw and took the whole checkout
  /// screen down with it.
  ///
  /// Returns null when the held project is no longer offered at all, which is
  /// a real case: staff can retire a project between two screens.
  ProjectCategory? _resolve(ProjectCategory held) {
    for (final p in _projects) {
      if (p.slug == held.slug) return p;
    }
    return null;
  }

  void _select(AidTarget target) {
    if (_target == target) return;
    AppHaptics.selection();
    setState(() => _target = target);
    // Leaving the project path drops the project immediately, so the form
    // never holds a project it is no longer sending.
    if (target == AidTarget.general) widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _AidTargetSkeleton();
    // Error before empty: a failed read must not be shown as "no projects".
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (!_canOfferProjects) {
      return _GeneralAidOnlyNote(
        // The two reasons read differently to a donor: one is a decision the
        // organization made, the other is simply nothing open today.
        message: _projectsVisible
            ? 'No project is open for donation right now, so your gift goes to general aid.'
            : 'Project donations are switched off right now, so your gift goes to general aid.',
        accentColor: widget.accentColor,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AidTargetTile(
          title: 'General aid',
          subtitle: 'Our team distributes it by priority and real need.',
          icon: Icons.groups_rounded,
          selected: _target == AidTarget.general,
          accentColor: widget.accentColor,
          onTap: () => _select(AidTarget.general),
        ),
        const SizedBox(height: AppSpace.sm),
        _AidTargetTile(
          title: 'Donate to a specific project',
          subtitle: "Choose one of the organization's open projects.",
          icon: Icons.flag_rounded,
          selected: _target == AidTarget.project,
          accentColor: widget.accentColor,
          onTap: () => _select(AidTarget.project),
        ),
        // AnimatedSize rather than a bare `if`: the picker appearing is a
        // consequence of the tap above it, and an abrupt jump reads as the
        // screen changing under you rather than as your own choice opening it.
        AnimatedSize(
          duration: AppMotion.resolve(context, AppMotion.snapDuration),
          alignment: Alignment.topCenter,
          child: _target == AidTarget.project
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpace.sm),
                  child: DropdownButtonFormField<ProjectCategory>(
                    // Never the held instance — see [_resolve].
                    initialValue: widget.selectedProject == null
                        ? null
                        : _resolve(widget.selectedProject!),
                    isExpanded: true,
                    hint: Text('Select a project'.tr),
                    items: [
                      for (final p in _projects)
                        DropdownMenuItem(
                          value: p,
                          child: Text(p.localizedName),
                        ),
                    ],
                    onChanged: (p) {
                      AppHaptics.selection();
                      widget.onChanged(p);
                    },
                    // Validated client-side because the alternative is worse
                    // than an error: submitting with no project chosen would
                    // quietly file the gift as general aid, which is the
                    // opposite of what the donor just asked for. The server
                    // remains the authority on whether the slug is real.
                    validator: (p) => p == null
                        ? 'Choose a project, or go back to general aid.'.tr
                        : null,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// One of the two paths, as a selectable card.
class _AidTargetTile extends StatelessWidget {
  const _AidTargetTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.snapDuration),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.12)
                : AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accentColor : AppThemeConfig.border(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? accentColor
                    : AppThemeConfig.mutedText(context),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the donor sees when there is no fork to offer.
///
/// Deliberately NOT an empty state and NOT an error: general aid is a real,
/// working destination, so this says where the money is going rather than
/// apologising for a missing list.
class _GeneralAidOnlyNote extends StatelessWidget {
  const _GeneralAidOnlyNote({required this.message, required this.accentColor});

  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          TileIcon(icon: Icons.groups_rounded, color: accentColor),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'General aid'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.tr,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shaped like the two cards it replaces.
class _AidTargetSkeleton extends StatelessWidget {
  const _AidTargetSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
              child: Container(
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.of(context).groundSunken,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
