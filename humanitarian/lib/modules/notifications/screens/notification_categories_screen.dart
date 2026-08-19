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
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:get/get.dart';

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
              builder: (items) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  for (final c in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassPanel(
                        child: SwitchListTile.adaptive(
                          key: Key('notif_cat_${c.category}'),
                          contentPadding: EdgeInsets.zero,
                          value: !_disabled.contains(c.category),
                          onChanged: _saving
                              ? null
                              : (v) => _toggle(c.category, v),
                          title: Text(
                            // Server data, so localizedTag rather than `.tr`:
                            // GetX hands back the key itself when there is no
                            // entry, which is how a raw token reaches a screen.
                            localizedTag(c.labelKey),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            _disabled.contains(c.category)
                                ? 'notif_cat_off'.tr
                                : 'notif_cat_on'.tr,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
