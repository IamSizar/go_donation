import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/control_settings_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/receipts/screens/aid_receipts_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/task_verification_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_application_1/core/widgets/app_theme_mode_picker.dart';

/// Client note — "Settings and Profile Interface": its own bottom-nav tab
/// (previously a side drawer opened by tapping the profile avatar).
///
/// Per the client's later split, the account and public-facing items
/// (profile header, Language, Dark Mode, Our Work, Services, About/Contact/
/// Terms, Log out) now live in ProfileMenuScreen, reached from the top-right
/// avatar. What remains here is the operational content: preferences,
/// volunteer tools, Task Verification, partners, receipts, share and cache.
const Color drawerPrimaryDark = Color(0xFF115E59);
const Color drawerDanger = Color(0xFFEF4444);

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();
    return SectionScaffold(
      title: '',
      subtitle: '',
      child: ListView(
        // Scaffold already reserves space above the bottom nav bar — this
        // only needs a small resting margin, not extra clearance for it.
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          // Guests have no phone/wallet/field-privacy to manage — matches
          // the old flow, which hid Edit profile for guests the same way.
          if (!guest)
            DrawerTile(
              icon: Icons.tune_rounded,
              label: 'Control Settings and Preferences',
              color: AppThemeConfig.accent(context),
              onTap: () => Get.to(() => const ControlSettingsScreen()),
            ),
          const DrawerDivider(),
          // Volunteer entry, kept role-segmented, matching how the rest of the
          // app keeps each role's own dashboard/tools separate rather than
          // surfacing them to every role.
          //
          // Redesign de-duplication — this used to be TWO rows ("Volunteer
          // With Us" and "Volunteer Attendance and Absence System") pushing
          // the identical `SupportSection()` with no argument to tell them
          // apart, so the second row was a pure duplicate. Attendance is not
          // a separate destination: SupportSection's mission cards are where
          // check-in / check-out is recorded, so one row reaches all of it.
          if (sharedPreferences.getString('role_id') == '3')
            DrawerTile(
              icon: Icons.volunteer_activism_rounded,
              label: 'Volunteer With Us',
              color: AppThemeConfig.pending(context),
              onTap: () => Get.to(() => const SupportSection()),
            ),
          DrawerTile(
            icon: Icons.checklist_rounded,
            label: 'Task Verification',
            color: AppThemeConfig.pending(context),
            onTap: () => Get.to(() => const TaskVerificationScreen()),
          ),
          // Redesign de-duplication — "Supporting Organizations" was a second
          // row onto the same PartnersScreen, differing only by
          // `onlySupporting: true`, which client-side-filters the very same
          // list by keywords in the free-text `partner_type` field. That is a
          // *view* of one list, not a second destination, so it belongs as a
          // control inside the screen rather than as its own menu entry.
          // Nothing is hidden by collapsing the pair: the unfiltered list is a
          // superset that already contains every supporting organization.
          DrawerTile(
            icon: Icons.handshake_rounded,
            label: 'Our Partners',
            color: AppThemeConfig.pending(context),
            onTap: () => Get.to(() => const PartnersScreen()),
          ),
          DrawerTile(
            icon: Icons.receipt_long_rounded,
            label: 'receipts_title',
            color: AppThemeConfig.accent(context),
            onTap: () => Get.to(() => const AidReceiptsScreen()),
          ),
          DrawerTile(
            icon: Icons.ios_share_rounded,
            label: 'share_app',
            color: AppThemeConfig.accent(context),
            onTap: shareApp,
          ),
          const DrawerDivider(),
          DrawerTile(
            icon: Icons.volunteer_activism_outlined,
            label: 'Our Humanitarian Work',
            color: AppThemeConfig.accent(context),
            onTap: () => Get.to(
              () => const ContentPageScreen(
                slug: 'humanitarian-work',
                titleKey: 'Our Humanitarian Work',
              ),
            ),
          ),
          DrawerTile(
            icon: Icons.cleaning_services_rounded,
            label: 'clear_cache',
            color: Colors.brown,
            onTap: () => _clearCache(context),
          ),
        ],
      ),
    );
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Log out?'.tr),
          content: Text('Are you sure you want to log out?'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: drawerDanger),
              child: Text('Log out'.tr),
            ),
          ],
        ),
      ) ??
      false;
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
Future<void> _clearCache(BuildContext context) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('clear_cache'.tr),
          content: Text('cache_clear_confirm'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('clear_cache'.tr),
            ),
          ],
        ),
      ) ??
      false;
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
class NotificationsRow extends StatefulWidget {
  const NotificationsRow({super.key});

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
    }
  }

  Future<void> _toggle(bool next) async {
    final previous = _enabled;
    setState(() => _enabled = next);
    try {
      final applied = await const ModuleApi().setNotificationSetting(next);
      if (mounted) setState(() => _enabled = applied);
    } catch (e) {
      // The rollback keeps the switch TRUTHFUL — it reads as unchanged, which
      // it is. But truthful is not the same as understood: a switch that flips
      // back on its own reads as a broken control, not as a save that failed.
      // One line distinguishes the two, and it is information rather than
      // noise because it changes what the user does next (try again later
      // versus assume the app is broken).
      if (mounted) setState(() => _enabled = previous);
      debugPrint('setNotificationSetting failed: $e');
      Get.snackbar(
        'Settings'.tr,
        'Could not save that preference. Please try again.'.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
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
