import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/modules/auth/screens/control_settings_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/receipts/screens/aid_receipts_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/task_verification_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// Client note — "Settings and Profile Interface": opens as a side drawer
/// when the user taps their profile picture (previously a bottom-sheet
/// quick-menu leading to a separate full-page settings screen). Piece 1 of
/// that note: the drawer shell itself, account info up top, Language and
/// Dark Mode as direct rows, and everything already working (About/Contact/
/// Terms, Clear Cache, Logout, plus Field privacy/Search/Receipts/Share/
/// Services — kept here so nothing already reachable from the old profile
/// page becomes a dead end).
///
/// Not in this piece yet — coming as their own pieces per the note: the
/// nested "Control Settings and Preferences" sub-page (Payment Methods,
/// Privacy & Security), and the still-missing items (Task Verification,
/// Our Humanitarian Work, a distinct Supporting Organizations list).
const Color _drawerPrimary = Color(0xFF0F766E);
const Color _drawerPrimaryDark = Color(0xFF115E59);
const Color _drawerDanger = Color(0xFFEF4444);

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();
    return Drawer(
      backgroundColor: AppThemeConfig.backgroundTop(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _AccountHeader(guest: guest),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // Guests have no phone/wallet/field-privacy to manage —
                  // matches the old flow, which hid Edit profile for guests
                  // the same way.
                  if (!guest)
                    _DrawerTile(
                      icon: Icons.tune_rounded,
                      label: 'Control Settings and Preferences',
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.to(() => const ControlSettingsScreen());
                      },
                    ),
                  const _LanguageRow(),
                  const _DarkModeRow(),
                  const _DrawerDivider(),
                  // Both volunteer rows are kept role-segmented, matching how
                  // the rest of the app keeps each role's own dashboard/tools
                  // separate rather than surfacing them to every role.
                  if (sharedPreferences.getString('role_id') == '3') ...[
                    _DrawerTile(
                      icon: Icons.volunteer_activism_rounded,
                      label: 'Volunteer With Us',
                      color: Colors.deepOrange,
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.to(() => const SupportSection());
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.fact_check_rounded,
                      label: 'Volunteer Attendance and Absence System',
                      color: Colors.deepOrange,
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.to(() => const SupportSection());
                      },
                    ),
                  ],
                  _DrawerTile(
                    icon: Icons.checklist_rounded,
                    label: 'Task Verification',
                    color: Colors.deepOrange,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(() => const TaskVerificationScreen());
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.handshake_rounded,
                    label: 'Our Partners',
                    color: Colors.deepOrange,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(() => const PartnersScreen());
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.diversity_3_rounded,
                    label: 'Supporting Organizations',
                    color: Colors.deepOrange,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(() => const PartnersScreen(onlySupporting: true));
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.receipt_long_rounded,
                    label: 'receipts_title',
                    color: Colors.teal,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(() => const AidReceiptsScreen());
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.apps_rounded,
                    label: 'Services',
                    color: Colors.deepPurple,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(() => const ProposalServicesSection());
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.ios_share_rounded,
                    label: 'share_app',
                    color: Colors.green,
                    onTap: () {
                      Navigator.of(context).pop();
                      shareApp();
                    },
                  ),
                  const _DrawerDivider(),
                  _DrawerTile(
                    icon: Icons.description_rounded,
                    label: 'Terms & Conditions',
                    color: Colors.blueGrey,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(() => const TermsScreen());
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.info_outline_rounded,
                    label: 'About Us',
                    color: Colors.teal,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(
                        () => const ContentPageScreen(
                          slug: 'about',
                          titleKey: 'About Us',
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.volunteer_activism_outlined,
                    label: 'Our Humanitarian Work',
                    color: Colors.teal,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(
                        () => const ContentPageScreen(
                          slug: 'humanitarian-work',
                          titleKey: 'Our Humanitarian Work',
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.mail_outline_rounded,
                    label: 'Contact Us',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.to(
                        () => const ContentPageScreen(
                          slug: 'contact',
                          titleKey: 'Contact Us',
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.cleaning_services_rounded,
                    label: 'clear_cache',
                    color: Colors.brown,
                    onTap: () => _clearCache(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: guest
                  ? _DrawerTile(
                      icon: Icons.login_rounded,
                      label: 'Sign in',
                      color: _drawerPrimary,
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.offAllNamed('/login');
                      },
                    )
                  : _DrawerTile(
                      icon: Icons.logout_rounded,
                      label: 'Log out',
                      color: _drawerDanger,
                      onTap: () => _confirmLogout(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context) async {
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
              style: TextButton.styleFrom(foregroundColor: _drawerDanger),
              child: Text('Log out'.tr),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed) return;
  if (context.mounted) Navigator.of(context).pop();
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
        } catch (_) {}
      }
    }
    Get.snackbar('clear_cache'.tr, 'cache_cleared'.tr);
  } catch (_) {
    Get.snackbar('clear_cache'.tr, 'cache_clear_failed'.tr);
  }
}

/// Account Information — profile picture, name, international phone number
/// (guests show their username instead, since they have no phone), plus an
/// edit affordance. Shown directly, no arrow — per spec this is information,
/// not a navigable option.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.guest});

  final bool guest;

  String? _localImagePath() {
    final path = sharedPreferences.getString('profile_image_path');
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  String? _remoteImageUrl() =>
      normalizeProfilePictureUrl(sharedPreferences.getString('profile_picture_url'));

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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_drawerPrimary, _drawerPrimaryDark],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: CachedProfileAvatar(
              localPath: _localImagePath(),
              imageUrl: _remoteImageUrl(),
              radius: 26,
              backgroundColor: _drawerPrimaryDark,
              placeholder: const Icon(
                Icons.person,
                color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      guest ? Icons.alternate_email_rounded : Icons.phone_rounded,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.85),
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
                            color: Colors.white.withValues(alpha: 0.85),
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
              color: Colors.white.withValues(alpha: 0.16),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  Navigator.of(context).pop();
                  await Get.to<bool>(() => const EditProfilePage());
                },
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
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

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

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
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = _drawerPrimary,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color color;
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
                  color: color.withValues(alpha: 0.12),
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
                    Icons.arrow_forward_ios_rounded,
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
class _LanguageRow extends StatelessWidget {
  const _LanguageRow();

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
    final tag = AppLocaleService.localeTag(Get.locale ?? AppLocaleService.english);
    return _options.firstWhere(
      (o) => AppLocaleService.localeTag(o.locale) == tag,
      orElse: () => _options.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current();
    return _DrawerTile(
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
            Icons.arrow_forward_ios_rounded,
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
              color: AppThemeConfig.surface(sheetContext),
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
  const _LanguageOption(this.code, this.nativeName, this.englishName, this.locale);

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
                ? _drawerPrimary.withValues(alpha: 0.08)
                : AppThemeConfig.softSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _drawerPrimary : AppThemeConfig.border(context),
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
                      ? _drawerPrimary
                      : _drawerPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  option.code,
                  style: TextStyle(
                    color: selected ? Colors.white : _drawerPrimary,
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
                    ? _drawerPrimary
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
class _DarkModeRow extends StatelessWidget {
  const _DarkModeRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.dark_mode_rounded,
                  color: Colors.indigo,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dark mode'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ),
              Switch.adaptive(
                value: isDark,
                activeThumbColor: _drawerPrimary,
                onChanged: setAppDarkMode,
              ),
            ],
          ),
        );
      },
    );
  }
}
