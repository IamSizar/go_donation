// K7 — "per-type notification control" on the Settings screen.
//
// WHAT WAS HERE BEFORE
// One switch. `users.notifications_enabled` was a single SMALLINT and the only
// notification preference in the system: all alerts, or none.
//
// WHAT THIS SCREEN TALKS TO
// Backend 159a3b2 + migration 108 added a switch per CATEGORY of alert and
// enforced it inside `notify.Send` — so switching one off stops the push being
// composed at all, rather than hiding it after the phone has already lit up.
// A filter living in the app could never have done that, which is why this
// screen is a thin renderer over two endpoints and holds no policy of its own:
//
//   GET  /api/profile/notification-categories → items[] {category, label_key,
//        display_order, enabled}, with this user's answers already applied.
//   POST /api/profile/notification-categories ← {"disabled": [...]}, the WHOLE
//        set every time, echoing back what was actually stored.
//
// CATEGORY, NOT RAW TYPE
// There are 81 notification types; a screen with 81 switches is a spreadsheet.
// The server derives a category from every type (`resolveCategory`) and the
// Alerts tab already groups by those same six, so this is the unit the user
// has been looking at all along.
//
// THE MASTER SWITCH IS ON THIS SCREEN DELIBERATELY
// `users.notifications_enabled` still wins over every category server-side
// (pinned by a Go test). A screen showing six switches while that one is off
// would be showing six controls that govern nothing, so the master switch is
// here — the existing NotificationsRow, which owns the value, not a second
// copy of it — and the note below it says what its position means.
//
// GROUPED INTO COLLAPSIBLE SECTIONS (owner request, chunk 2)
// Six switches in one flat column read as a spreadsheet, same complaint the
// migration-108 comment above already made about 81 raw types. The six
// categories collapse into three PRIORITY TIERS — `_tierOf` mirrors
// `defaultPriority` in backend/internal/notify/notify.go (urgent=80,
// payment=60 → high; campaign=35, system=20 → medium; reminder=15, normal=0
// → low) — a boundary that already exists for another reason (send
// priority), not one invented for this screen. Groups start EXPANDED so the
// existing pinned widget test (notification_categories_test.dart, which taps
// `notif_cat_urgent` without expanding anything first) keeps working; a user
// who collapses a group still sees "N of M on" in its header, so they never
// have to open a group just to check whether anything inside it is live.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:get/get.dart';

/// The three priority tiers a category collapses into, in display order.
/// Kept as an ordered list (not a Set) so the sections always render in the
/// same high → medium → low sequence regardless of item order.
const _kTierOrder = ['high', 'medium', 'low'];

/// Section header label keys, one per tier — see `_tierOf` for the mapping
/// and `app_translations.dart` for `en`/`ar` (Kurdish inherits `en` via the
/// documented `{..._en, ..._sorani}` merge).
const _kTierLabelKeys = {
  'high': 'notif_cat_tier_high',
  'medium': 'notif_cat_tier_medium',
  'low': 'notif_cat_tier_low',
};

/// Maps a server category to the priority tier its section belongs to.
/// Mirrors `defaultPriority` in backend/internal/notify/notify.go — see the
/// file header for why this boundary rather than an invented one.
String _tierOf(String category) {
  switch (category) {
    case 'urgent':
    case 'payment':
      return 'high';
    case 'campaign':
    case 'system':
      return 'medium';
    default: // reminder, normal, and any future category default to 'low'.
      return 'low';
  }
}

/// Placeholder bones shaped like one category row — a label line, a state
/// line, and the block the switch occupies — so the controls fill in rather
/// than pop in over a spinner.
class _CategoryRowBones extends StatelessWidget {
  const _CategoryRowBones();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSkeleton.bone(height: 12, widthFactor: 0.42),
                AppSkeleton.bone(height: 9, widthFactor: 0.6),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 44, child: AppSkeleton.bone(height: 22)),
        ],
      ),
    );
  }
}

/// The per-category notification switches.
class NotificationCategoriesScreen extends StatefulWidget {
  const NotificationCategoriesScreen({super.key});

  @override
  State<NotificationCategoriesScreen> createState() =>
      _NotificationCategoriesScreenState();
}

class _NotificationCategoriesScreenState
    extends State<NotificationCategoriesScreen> {
  /// The catalogue with this user's answers, or null before the first load.
  ///
  /// Null rather than `const []` on purpose: AppAsync treats an empty non-null
  /// list as a finished empty result, so starting empty would render "no
  /// categories" before the first request had even answered.
  List<NotificationCategoryPref>? _items;

  /// Which categories are currently switched OFF. Held separately from
  /// [_items] because a toggle changes this and the catalogue stays as the
  /// server described it.
  final _disabled = <String>{};

  bool _loading = true;
  bool _saving = false;

  /// A user-facing reason the list is not on screen, or null.
  ///
  /// FAILING CLOSED IS THE POINT. Every switch draws from the loaded state, so
  /// a screen that fell back to "all on" after a failed fetch would tell a
  /// user they still receive categories they had switched off — and the next
  /// tap would POST that fiction back as the truth, since the write replaces
  /// the whole set. No list until we know what the user actually chose.
  String? _error;

  /// The master switch's position, reported by [NotificationsRow].
  ///
  /// Starts true so the "everything is off" note is never shown on a guess;
  /// the row corrects it as soon as it knows.
  bool _masterEnabled = true;

  /// Tiers currently collapsed. Empty by default — every section starts
  /// expanded (see the file header for why).
  final _collapsedTiers = <String>{};

  /// Flips one section's expanded/collapsed state.
  void _toggleTier(String tier) {
    AppHaptics.selection();
    setState(() {
      if (!_collapsedTiers.add(tier)) _collapsedTiers.remove(tier);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Cleared before the attempt so a successful retry cannot leave the old
    // failure gating a list that has since loaded.
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final items = await const ModuleApi().getNotificationCategories();
      if (!mounted) return;
      setState(() {
        _items = items;
        _disabled
          ..clear()
          ..addAll(items.where((c) => !c.enabled).map((c) => c.category));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your notification settings.');
      debugPrint('getNotificationCategories failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Switches one category on or off.
  ///
  /// Optimistic, then corrected by what the server says it stored — and rolled
  /// back on failure with a line explaining why, because a switch that flips
  /// back on its own reads as a broken control rather than as a save that
  /// failed.
  Future<void> _toggle(String category, bool receive) async {
    AppHaptics.selection();
    final previous = Set<String>.from(_disabled);
    setState(() {
      if (receive) {
        _disabled.remove(category);
      } else {
        _disabled.add(category);
      }
      _saving = true;
    });
    try {
      // The WHOLE set, never a delta: SetNotificationCategories rewrites every
      // catalogue row from this list, so posting only the category just tapped
      // would switch every other one back on.
      final saved = await const ModuleApi().setNotificationCategories(
        _disabled.toList(),
      );
      if (!mounted) return;
      setState(() {
        _disabled
          ..clear()
          ..addAll(saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _disabled
          ..clear()
          ..addAll(previous);
      });
      debugPrint('setNotificationCategories failed: $e');
      Get.snackbar(
        'Settings'.tr,
        'Could not save that preference. Please try again.'.tr,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Alert categories',
      subtitle: 'notif_cat_desc',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NotificationsRow(
                    onEnabledChanged: (v) {
                      if (mounted && v != _masterEnabled) {
                        setState(() => _masterEnabled = v);
                      }
                    },
                  ),
                  // 5.9 — guidance where the control is, not in a manual. The
                  // categories below still SAVE while this is off, they just
                  // cannot deliver anything, and saying so is what keeps them
                  // from reading as broken.
                  if (!_masterEnabled) ...[
                    const SizedBox(height: 6),
                    Text(
                      'notif_cat_master_off'.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: AppAsync<List<NotificationCategoryPref>>(
              // The gutter lives inside this screen's own list, so the skeleton
              // and the error banner would otherwise sit edge-to-edge while the
              // content that replaces them sits in a 20pt margin.
              gutter: const EdgeInsets.symmetric(horizontal: 20),
              loading: _loading,
              error: _error,
              onRetry: _load,
              data: _items,
              isEmpty: (items) => items.isEmpty,
              skeleton: const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: AppSkeleton(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CategoryRowBones(),
                      _CategoryRowBones(),
                      _CategoryRowBones(),
                      _CategoryRowBones(),
                    ],
                  ),
                ),
              ),
              // Reachable: staff can retire every row of the catalogue. It is
              // not an error and not a failure of the user's, so it says what
              // it means for them — their alerts keep arriving.
              empty: AppEmpty(
                title: 'notif_cat_empty'.tr,
                message: 'notif_cat_empty_desc'.tr,
                icon: Icons.notifications_off_outlined,
              ),
              builder: (items) {
                // Bucket the catalogue into its three tiers, preserving the
                // server's display_order within each bucket.
                final byTier = <String, List<NotificationCategoryPref>>{
                  for (final tier in _kTierOrder) tier: [],
                };
                for (final c in items) {
                  byTier[_tierOf(c.category)]!.add(c);
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  children: [
                    for (final tier in _kTierOrder)
                      if (byTier[tier]!.isNotEmpty)
                        _CategoryTierSection(
                          tier: tier,
                          items: byTier[tier]!,
                          collapsed: _collapsedTiers.contains(tier),
                          disabled: _disabled,
                          saving: _saving,
                          onToggleSection: () => _toggleTier(tier),
                          onToggleCategory: _toggle,
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One collapsible priority-tier section: a tappable header (title + an
/// "N of M on" summary that stays correct whether the section is open or
/// closed) over an [AnimatedSize]-wrapped column of that tier's switches.
///
/// `AnimatedSize` is the same primitive `aid_target_field.dart` uses for its
/// conditional picker (rule 5.4: appear/disappear must animate, never jump) —
/// reused rather than a second collapsible pattern invented for this screen.
class _CategoryTierSection extends StatelessWidget {
  const _CategoryTierSection({
    required this.tier,
    required this.items,
    required this.collapsed,
    required this.disabled,
    required this.saving,
    required this.onToggleSection,
    required this.onToggleCategory,
  });

  final String tier;
  final List<NotificationCategoryPref> items;

  /// Whether THIS section is currently collapsed.
  final bool collapsed;

  /// Categories the user has switched off, read from the parent so a toggle
  /// inside this section is reflected everywhere without this widget owning
  /// any state of its own.
  final Set<String> disabled;
  final bool saving;
  final VoidCallback onToggleSection;
  final void Function(String category, bool receive) onToggleCategory;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final onCount = items.where((i) => !disabled.contains(i.category)).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPressable(
              haptic: AppPressHaptic.none, // onToggleSection fires its own.
              onTap: onToggleSection,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kTierLabelKeys[tier]!.tr,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppThemeConfig.text(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Visible with the section collapsed OR expanded, so
                        // closing a section never hides whether anything
                        // inside it is switched on.
                        Text(
                          'notif_cat_group_summary'.trParams({
                            'on': '$onCount',
                            'total': '${items.length}',
                          }),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.inkTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: AppMotion.resolve(
                      context,
                      AppMotion.snapDuration,
                    ),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: colors.inkTertiary,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: AppMotion.resolve(context, AppMotion.settleDuration),
              alignment: Alignment.topCenter,
              child: collapsed
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in items)
                            SwitchListTile.adaptive(
                              key: Key('notif_cat_${item.category}'),
                              contentPadding: EdgeInsets.zero,
                              value: !disabled.contains(item.category),
                              // `Switch.adaptive` (which this tile wraps on
                              // iOS) falls back to the stock iOS system green
                              // (#34C759) unless an active colour is set
                              // explicitly. The master "الإشعارات" toggle
                              // above (NotificationsRow in settings_section
                              // .dart) already sets `activeThumbColor` to the
                              // brand accent inline — matching that mechanism
                              // here, rather than introducing a screen-level
                              // or theme-level override, keeps every switch
                              // on this screen the same green.
                              activeThumbColor: AppThemeConfig.accent(context),
                              onChanged: saving
                                  ? null
                                  : (v) => onToggleCategory(item.category, v),
                              title: Text(
                                // Server data, so localizedTag rather than
                                // `.tr`: GetX hands back the key itself when
                                // there is no entry, which is how a raw
                                // token would otherwise reach the screen.
                                localizedTag(item.labelKey),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                disabled.contains(item.category)
                                    ? 'notif_cat_off'.tr
                                    : 'notif_cat_on'.tr,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
