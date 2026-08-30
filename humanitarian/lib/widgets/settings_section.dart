import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_application_1/core/widgets/app_theme_mode_picker.dart';

/// Shared account/settings widgets used by ProfileMenuScreen.
///
/// Previously this file also defined `SettingsSection`, its own bottom-nav
/// tab (before that, a side drawer opened by tapping the profile avatar).
/// The owner asked to remove the Settings tab and fold everything it offered
/// into Profile — see profile_menu_screen.dart, which now owns every
/// destination that used to live in that tab's ListView (Control Settings
/// and Preferences, Volunteer With Us, Task Verification, Our Partners,
/// receipts, share, Our Humanitarian Work, clear cache) alongside the
/// account items it already had. What remains in this file is the widget
/// toolkit both screens draw from: DrawerTile/DrawerDivider, AccountHeader,
/// LanguageRow, DarkModeRow, NotificationsRow, confirmLogout and
/// clearCache.
const Color drawerPrimaryDark = Color(0xFF115E59);
const Color drawerDanger = Color(0xFFEF4444);

Future<void> confirmLogout(BuildContext context) async {
  final confirmed = await showAdaptiveConfirm(
    context,
    title: 'Log out?'.tr,
    message: 'Are you sure you want to log out?'.tr,
    confirmLabel: 'Log out'.tr,
    cancelLabel: 'Cancel'.tr,
    isDestructive: true,
    destructiveColor: drawerDanger,
  );
  if (!confirmed) return;
  // Navigate to login FIRST so the authenticated tree is torn down before the
  // session is cleared (mirrors the old flow — avoids a black screen from
  // sections rebuilding against wiped storage).
  Get.offAllNamed('/login');
  await logout();
}

// #34 — clear cached data: the in-memory image cache + the temp directory
// (where cached_network_image stores its disk cache). Deliberately does NOT
// touch SharedPreferences, so the session/login stays intact.
//
// Public (not `_clearCache`) because the "clear_cache" DrawerTile that used
// to call this from the Settings tab now lives in profile_menu_screen.dart,
// a different file — see this file's header.
Future<void> clearCache(BuildContext context) async {
  // Not destructive in the dangerous sense — the cache refills itself and the
  // session is untouched — so the affirmative action is the default one rather
  // than a red warning.
  final confirmed = await showAdaptiveConfirm(
    context,
    title: 'clear_cache'.tr,
    message: 'cache_clear_confirm'.tr,
    confirmLabel: 'clear_cache'.tr,
    cancelLabel: 'Cancel'.tr,
  );
  if (!confirmed) return;
  try {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final tmp = await getTemporaryDirectory();
    if (tmp.existsSync()) {
      for (final e in tmp.listSync()) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {
          // Deliberate: one locked temp entry (a file still open) must not
          // abort the sweep — the remaining entries are still worth clearing.
        }
      }
    }
    Get.snackbar('clear_cache'.tr, 'cache_cleared'.tr);
  } catch (_) {
    // Not silent: the failure is reported to the user by this snackbar.
    Get.snackbar('clear_cache'.tr, 'cache_clear_failed'.tr);
  }
}

/// Account Information — profile picture, name, international phone number
/// (guests show their username instead, since they have no phone), plus an
/// edit affordance. Shown directly, no arrow — per spec this is information,
/// not a navigable option.
class AccountHeader extends StatelessWidget {
  const AccountHeader({super.key, required this.guest});

  final bool guest;

  String? _localImagePath() {
    final path = sharedPreferences.getString('profile_image_path');
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  String? _remoteImageUrl() => normalizeProfilePictureUrl(
    sharedPreferences.getString('profile_picture_url'),
  );

  String _name() {
    final n = (sharedPreferences.getString('name_user') ?? '').trim();
    return n.isEmpty ? 'No name'.tr : n;
  }

  // #39 — phone stored canonically as "<dial code><national number>" with
  // no leading "+"; prefix one so it reads as a proper E.164 number.
  String _displayPhone() {
    final raw = (sharedPreferences.getString('phone_user') ?? '').trim();
    if (raw.isEmpty) return '—';
    if (raw.startsWith('+')) return raw;
    return RegExp(r'^\d{7,15}$').hasMatch(raw) ? '+$raw' : raw;
  }

  String _guestUsername() {
    final u = (sharedPreferences.getString('username') ?? '').trim();
    return u.isEmpty ? 'Guest'.tr : '@$u';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: AppThemeConfig.onAccent(context), width: 2),
              ),
            ),
            child: CachedProfileAvatar(
              localPath: _localImagePath(),
              imageUrl: _remoteImageUrl(),
              radius: 26,
              backgroundColor: drawerPrimaryDark,
              placeholder: Icon(
                Icons.person,
                color: AppThemeConfig.onAccent(context),
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  guest ? 'Guest'.tr : _name(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppThemeConfig.onAccent(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      guest
                          ? Icons.alternate_email_rounded
                          : Icons.phone_rounded,
                      size: 12,
                      color: AppThemeConfig.onAccent(
                        context,
                      ).withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          guest ? _guestUsername() : _displayPhone(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppThemeConfig.onAccent(
                              context,
                            ).withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!guest)
            Material(
              color: AppThemeConfig.onAccent(context).withValues(alpha: 0.16),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  await Get.to<bool>(() => const EditProfilePage());
                },
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.edit_rounded,
                    color: AppThemeConfig.onAccent(context),
                    size: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DrawerDivider extends StatelessWidget {
  const DrawerDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(height: 1, color: AppThemeConfig.border(context)),
    );
  }
}

/// One vertically-arranged option row: icon, label, trailing content (an
/// arrow by default — tapping it opens the related page).
class DrawerTile extends StatelessWidget {
  const DrawerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;

  /// Null resolves to the theme accent at build time — a token call
  /// cannot be a const default.
  final Color? color;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (color ?? AppThemeConfig.accent(context)).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              trailing ??
                  Icon(
                    AppIcons.forward(context),
                    size: 14,
                    color: AppThemeConfig.mutedText(context),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Language — per spec: tapping the arrow opens a picker with exactly the
/// 4 supported languages.
class LanguageRow extends StatelessWidget {
  const LanguageRow({super.key});

  static const List<_LanguageOption> _options = [
    _LanguageOption('EN', 'English', 'English', AppLocaleService.english),
    _LanguageOption('ع', 'العربية', 'Arabic', AppLocaleService.arabic),
    _LanguageOption(
      'سۆ',
      'کوردیی سۆرانی',
      'Kurdish Sorani',
      AppLocaleService.kurdishSorani,
    ),
    _LanguageOption(
      'با',
      'کوردیی بادینی',
      'Kurdish Badini',
      AppLocaleService.kurdishBadini,
    ),
  ];

  _LanguageOption _current() {
    final tag = AppLocaleService.localeTag(
      Get.locale ?? AppLocaleService.english,
    );
    return _options.firstWhere(
      (o) => AppLocaleService.localeTag(o.locale) == tag,
      orElse: () => _options.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current();
    return DrawerTile(
      icon: Icons.translate_rounded,
      label: 'Language',
      onTap: () => _showLanguagePicker(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            current.code,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: AppThemeConfig.mutedText(context),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            AppIcons.forward(context),
            size: 14,
            color: AppThemeConfig.mutedText(context),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final currentTag = AppLocaleService.localeTag(
          Get.locale ?? AppLocaleService.english,
        );
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppThemeConfig.elevatedSurface(sheetContext),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppThemeConfig.border(sheetContext)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppThemeConfig.mutedText(
                      sheetContext,
                    ).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                for (final option in _options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LanguageOptionRow(
                      option: option,
                      selected:
                          AppLocaleService.localeTag(option.locale) ==
                          currentTag,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        AppLocaleService.changeLocale(option.locale);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageOption {
  const _LanguageOption(
    this.code,
    this.nativeName,
    this.englishName,
    this.locale,
  );

  final String code;
  final String nativeName;
  final String englishName;
  final Locale locale;
}

class _LanguageOptionRow extends StatelessWidget {
  const _LanguageOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _LanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppThemeConfig.accent(context).withValues(alpha: 0.08)
                : AppThemeConfig.softSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppThemeConfig.accent(context)
                  : AppThemeConfig.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppThemeConfig.accent(context)
                      : AppThemeConfig.accent(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  option.code,
                  style: TextStyle(
                    color: selected
                        ? AppThemeConfig.onAccent(context)
                        : AppThemeConfig.accent(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.nativeName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    Text(
                      option.englishName.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppThemeConfig.accent(context)
                    : AppThemeConfig.mutedText(context).withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark Mode — per spec: a direct toggle, no sub-page.
/// The appearance row in Settings.
///
/// Was a two-state Switch bound to setAppDarkMode; it is now the shared
/// tri-state picker, so System is reachable. The heading stays because the
/// segments alone do not say what they control.
class DarkModeRow extends StatelessWidget {
  const DarkModeRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.contrast_rounded,
                color: AppThemeConfig.accent(context),
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                'Dark mode'.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const AppThemeModePicker(),
        ],
      ),
    );
  }
}

/// Client spec "Twelfth: General Settings" — enable/disable notifications.
///
/// The switch has always existed end-to-end (users.notifications_enabled,
/// GET/POST /api/profile/notifications, and ModuleApi.get/setNotificationSetting)
/// but its only UI lived on ProfilePage, which nothing navigates to any more —
/// so in practice the setting was unreachable. This row restores it next to
/// Dark mode.
///
/// Optimistic: the switch flips immediately and reverts if the write fails, so
/// a slow network never makes the toggle feel stuck.
///
/// J6 — the row is also a DOOR. The client listed الاشعارات among the eleven
/// profile-menu ENTRIES, i.e. somewhere you go; what was here was a switch
/// alone, so tapping the word "Notifications" changed a preference and never
/// showed a single notification. [onOpenList] is what the label now leads to.
/// It stays optional because the switch is still legitimate on its own in any
/// settings surface that has no list to open.
class NotificationsRow extends StatefulWidget {
  const NotificationsRow({super.key, this.onOpenList, this.onEnabledChanged});

  /// Where tapping the label goes. Null leaves the row switch-only.
  final VoidCallback? onOpenList;

  /// K7 — reports the master switch's value to a host that has to react to
  /// it, called once the setting is known and after every change (including a
  /// failed write's rollback, so the listener never keeps a value the row
  /// itself has abandoned).
  ///
  /// It exists so NotificationCategoriesScreen can say that its per-category
  /// switches are moot while this one is off — the server lets the master
  /// override every category, and six switches that quietly govern nothing is
  /// exactly what that screen must not become. The row stays the single owner
  /// of the value; this reports it, it does not share it.
  final ValueChanged<bool>? onEnabledChanged;

  @override
  State<NotificationsRow> createState() => _NotificationsRowState();
}

class _NotificationsRowState extends State<NotificationsRow> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await const ModuleApi().getNotificationSetting();
      if (mounted) setState(() => _enabled = v);
    } catch (_) {
      // Leave the optimistic default (on) — a read failure must not look
      // like the user has notifications switched off.
    } finally {
      if (mounted) setState(() => _loading = false);
      widget.onEnabledChanged?.call(_enabled);
    }
  }

  Future<void> _toggle(bool next) async {
    // One event, one haptic: the switch is a selection, like every other
    // preference control in this file.
    AppHaptics.selection();
    final previous = _enabled;
    setState(() => _enabled = next);
    try {
      final applied = await const ModuleApi().setNotificationSetting(next);
      if (mounted) setState(() => _enabled = applied);
      widget.onEnabledChanged?.call(applied);
    } catch (e) {
      // The rollback keeps the switch TRUTHFUL — it reads as unchanged, which
      // it is. But truthful is not the same as understood: a switch that flips
      // back on its own reads as a broken control, not as a save that failed.
      // One line distinguishes the two, and it is information rather than
      // noise because it changes what the user does next (try again later
      // versus assume the app is broken).
      if (mounted) setState(() => _enabled = previous);
      // Told AFTER the rollback, so a listener can never be left holding a
      // value this row has already abandoned.
      widget.onEnabledChanged?.call(previous);
      debugPrint('setNotificationSetting failed: $e');
      Get.snackbar(
        'Settings'.tr,
        'Could not save that preference. Please try again.'.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Icon + label + chevron: the part that navigates. Kept separate from the
    // switch so the two affordances never fight — a finger on the label opens
    // the list, a finger on the switch changes the preference, and neither
    // triggers the other.
    final Widget label = Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.notifications_active_rounded,
            color: AppThemeConfig.pending(context),
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Notifications'.tr,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: AppThemeConfig.text(context),
            ),
          ),
        ),
        if (widget.onOpenList != null) ...[
          const SizedBox(width: 6),
          // The same chevron DrawerTile draws, and directional, so it points
          // the right way in Arabic and Kurdish.
          Icon(
            AppIcons.forward(context),
            size: 14,
            color: AppThemeConfig.mutedText(context),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: widget.onOpenList == null
                ? label
                : Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        AppHaptics.selection();
                        widget.onOpenList!();
                      },
                      // Vertical padding restores the 44pt touch target the
                      // 36pt icon alone would fall short of.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: label,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          if (_loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch.adaptive(
              value: _enabled,
              activeThumbColor: AppThemeConfig.accent(context),
              onChanged: _toggle,
            ),
        ],
      ),
    );
  }
}
