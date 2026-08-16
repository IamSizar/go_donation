import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_mute.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/app_voice.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'edit_profile.dart';
import 'field_privacy_screen.dart';
import '../../proposal/screens/proposal_services_section.dart';
import '../../search/screens/global_search_screen.dart';
import '../../receipts/screens/aid_receipts_screen.dart';
import '../../../localization/locale_service.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/widgets/app_theme_mode_picker.dart';

class ProfileSection extends StatefulWidget {
  const ProfileSection({super.key});

  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> {
  @override
  void initState() {
    super.initState();
    _migrateStoredProfilePictureUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshProfileFromServer(),
    );
  }

  Future<void> _refreshProfileFromServer() async {
    final id = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (id == null || id <= 0 || !mounted) return;
    final account = await fetchUserAccount(id);
    if (!mounted || account == null) return;
    await applyUserAccountToSharedPreferences(account);
    if (mounted) setState(() {});
  }

  void _migrateStoredProfilePictureUrl() {
    final raw = sharedPreferences.getString('profile_picture_url');
    final fixed = normalizeProfilePictureUrl(raw);
    if (fixed != null && fixed != raw) {
      sharedPreferences.setString('profile_picture_url', fixed);
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Log out?'.tr),
            content: Text('Are you sure you want to log out?'.tr),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'.tr),
              ),
              TextButton(
                // 27.4 — DON'T clear prefs here: doing it while the dashboard
                // tree is still mounted made every section rebuild against wiped
                // storage and the app went black/frozen. Just confirm; the
                // clearing happens after we've navigated away.
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: AppThemeConfig.consequence(context),
                ),
                child: Text('Log out'.tr),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      // 27.4 — navigate to login FIRST so the authenticated dashboard tree is
      // torn down before any prefs are cleared (prevents the black screen).
      Get.offAllNamed('/login');
      // 27.5 — then revoke the token server-side and clear local session +
      // identity + guest flag, so the session is truly invalidated and can't
      // auto re-login on next launch.
      await logout();
    }
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

  Future<void> _openEditProfile() async {
    final result = await Get.to<bool>(() => const EditProfilePage());
    if (result == true && mounted) {
      setState(() {});
    }
  }

  String? _localProfileImagePath() {
    final imagePath = sharedPreferences.getString('profile_image_path');
    if (imagePath == null || imagePath.isEmpty) return null;
    final imageFile = File(imagePath);
    return imageFile.existsSync() ? imagePath : null;
  }

  String? _remoteProfileImageUrl() {
    return normalizeProfilePictureUrl(
      sharedPreferences.getString('profile_picture_url'),
    );
  }

  String _profileName() {
    final savedName = sharedPreferences.getString('name_user')?.trim() ?? '';
    return savedName.isEmpty ? 'No name'.tr : savedName;
  }

  String _profileSubtitle() {
    final gender = sharedPreferences.getString('gender_user')?.trim() ?? '';
    final address = sharedPreferences.getString('address_user')?.trim() ?? '';
    final details = <String>[
      if (gender.isNotEmpty) gender.tr,
      if (address.isNotEmpty) address,
    ];

    if (details.isEmpty) return 'Beneficiary'.tr;
    return details.join(' · ');
  }

  String? _roleLabel() {
    switch (sharedPreferences.getString('role_id')) {
      case '1':
        return 'Donor'.tr;
      case '2':
        return 'Beneficiary'.tr;
      case '3':
        return 'Volunteer';
      default:
        return null;
    }
  }

  List<String> _missingProfileFields() {
    return missingProfileFieldsFromPreferences();
  }

  /// K21 — this account's own identity code (GR-/ER-/VL-), or null.
  ///
  /// The registration form promises the code is generated automatically and
  /// nothing ever showed it to the person it belongs to, so they could not
  /// quote it on a receipt or look their own record up by it. Null for staff,
  /// guests, and any account the server reports no code for — the card then
  /// shows nothing rather than an empty row.
  String? _identityCode() {
    final code = sharedPreferences.getString('identity_code')?.trim() ?? '';
    return code.isEmpty ? null : code;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppThemeConfig.backgroundTop(context)),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Profile & Settings'.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                children: [
                  Builder(
                    builder: (context) {
                      final missingFields = _missingProfileFields();
                      final isComplete = missingFields.isEmpty;
                      return Column(
                        children: [
                          _ProfileHero(
                            name: _profileName(),
                            subtitle: _profileSubtitle(),
                            roleLabel: _roleLabel(),
                            identityCode: _identityCode(),
                            isComplete: isComplete,
                            onEdit: _openEditProfile,
                            avatar: CachedProfileAvatar(
                              localPath: _localProfileImagePath(),
                              imageUrl: _remoteProfileImageUrl(),
                              radius: 38,
                              backgroundColor: AppThemeConfig.accent(context),
                              placeholder: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                          if (!isComplete) ...[
                            const SizedBox(height: 12),
                            _ProfileCompletionReminder(
                              missingFields: missingFields,
                              onEdit: _openEditProfile,
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 22),
                  _SectionLabel('Account'.tr),
                  const SizedBox(height: 10),
                  // Redesign de-duplication — three tiles used to sit in this
                  // section with no `onTap` at all ("Privacy & Security",
                  // "Payment Methods", "App Settings"). They looked tappable,
                  // did nothing, and each duplicated something that already
                  // works elsewhere, so the app effectively advertised two
                  // settings hubs. They were removed rather than wired up,
                  // because every destination they promised already has a
                  // live route in:
                  //  - Privacy & Security → the "Field privacy" tile directly
                  //    below is the only privacy capability that actually
                  //    exists (see PrivacySecurityScreen's own note), and the
                  //    full screen is reachable from the Settings tab via
                  //    Control Settings and Preferences.
                  //  - Payment Methods → PaymentMethodsScreen is reached from
                  //    the same Control Settings screen; adding a second door
                  //    here is exactly the duplication being removed.
                  //  - App Settings → the "Preferences" section further down
                  //    THIS screen already owns language, theme, notifications
                  //    and mute, so the tile promised a screen that is really
                  //    just a scroll away.
                  // #32 — choose which profile fields are public/hidden.
                  _ProfileOptionTile(
                    icon: Icons.visibility_off_rounded,
                    title: 'Field privacy',
                    subtitle: 'privacy_desc',
                    color: AppThemeConfig.accent(context),
                    onTap: () => Get.to(() => const FieldPrivacyScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #34 — clear cached data (images / temp files).
                  _ProfileOptionTile(
                    icon: Icons.cleaning_services_rounded,
                    title: 'clear_cache',
                    subtitle: 'clear_cache_desc',
                    color: Colors.brown,
                    onTap: () => _clearCache(context),
                  ),

                  const SizedBox(height: 22),
                  _SectionLabel('Services'.tr),
                  const SizedBox(height: 10),
                  // #33 — global search across the whole app.
                  _ProfileOptionTile(
                    icon: Icons.search_rounded,
                    title: 'search_title',
                    subtitle: 'search_subtitle',
                    color: AppThemeConfig.accent(context),
                    onTap: () => Get.to(() => const GlobalSearchScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #50 — the user's digital aid-delivery receipts.
                  _ProfileOptionTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'receipts_title',
                    subtitle: 'receipts_subtitle',
                    color: AppThemeConfig.accent(context),
                    onTap: () => Get.to(() => const AidReceiptsScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #49 — share the app to other apps (WhatsApp, Telegram, …).
                  _ProfileOptionTile(
                    icon: Icons.ios_share_rounded,
                    title: 'share_app',
                    subtitle: 'share_app_desc',
                    color: AppThemeConfig.accent(context),
                    // Anchors the iOS share popover — see [shareAnchor].
                    onTap: () => shareApp(context),
                  ),
                  // Note #41 — Marriage moved to its own bottom-nav tab
                  // (browse/my-profile/chats all live there now), so the 4
                  // profile-menu tiles that used to duplicate it here were
                  // removed to avoid a second, confusing entry point.
                  const SizedBox(height: 12),
                  _ProfileOptionTile(
                    icon: Icons.apps_rounded,
                    title: 'Services',
                    subtitle: 'Requests, forms, partners, support, and more.',
                    color: AppThemeConfig.accent(context),
                    // Note #41 — Services isn't a bottom tab; push it directly.
                    onTap: () => Get.to(() => const ProposalServicesSection()),
                  ),

                  const SizedBox(height: 22),
                  _SectionLabel('Preferences'.tr),
                  const SizedBox(height: 10),
                  const _LanguagePreferenceCard(),
                  const SizedBox(height: 12),
                  const _ThemePreferenceCard(),
                  const SizedBox(height: 12),
                  const _NotificationPreferenceCard(),
                  const SizedBox(height: 12),
                  const _MutePreferenceCard(),

                  const SizedBox(height: 22),
                  _SectionLabel('Legal'.tr),
                  const SizedBox(height: 10),
                  _ProfileOptionTile(
                    icon: Icons.description_rounded,
                    title: 'Terms & Conditions',
                    subtitle: 'Read the terms that apply to using the app.',
                    color: AppThemeConfig.subtleText(context),
                    onTap: () => Get.to(() => const TermsScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #35 — About Us + Contact (admin-editable content pages).
                  _ProfileOptionTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About Us',
                    subtitle: 'about_desc',
                    color: AppThemeConfig.accent(context),
                    onTap: () => Get.to(
                      () => const ContentPageScreen(
                        slug: 'about',
                        titleKey: 'About Us',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProfileOptionTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Contact Us',
                    subtitle: 'contact_desc',
                    color: AppThemeConfig.pending(context),
                    onTap: () => Get.to(
                      () => const ContentPageScreen(
                        slug: 'contact',
                        titleKey: 'Contact Us',
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  _LogoutTile(
                    color: AppThemeConfig.consequence(context),
                    onTap: () => _handleLogout(context),
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

/// The redesigned profile header: a gradient identity card with a large ringed
/// avatar, a completion badge, the name, a role pill and a quick subtitle, plus
/// a prominent Edit action.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.subtitle,
    required this.roleLabel,
    required this.identityCode,
    required this.isComplete,
    required this.avatar,
    required this.onEdit,
  });

  final String name;
  final String subtitle;
  final String? roleLabel;

  /// K21 — the account's own GR-/ER-/VL- code, or null when it has none.
  final String? identityCode;

  final bool isComplete;
  final Widget avatar;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // Ring + badge turn gold/amber when the profile is incomplete, green when
    // everything's filled in — a calm at-a-glance status.
    // Complete = settled (accent); incomplete = still in flight (pending).
    // These carry state, so they use the semantic tokens rather than a hue
    // picked by eye.
    final ringColor = isComplete
        ? Colors.white
        : AppThemeConfig.pending(context);
    final badgeColor = isComplete
        ? AppThemeConfig.accent(context)
        : AppThemeConfig.pending(context);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 20, 14, 20),
      decoration: BoxDecoration(
        color: AppThemeConfig.accent(context),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.accent(context).withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ringed avatar + completion badge.
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor, width: 3),
                  ),
                  child: avatar,
                ),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      isComplete
                          ? Icons.check_rounded
                          : Icons.priority_high_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (roleLabel != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_user_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          roleLabel!.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (identityCode != null) ...[
                  const SizedBox(height: 8),
                  _IdentityCodeChip(code: identityCode!),
                ],
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Edit button — white pill so it reads as the primary action.
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onEdit,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.edit_rounded,
                  color: AppThemeConfig.accent(context),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// K21 — the account's own identity code, on the identity card, copyable.
///
/// WHY IT IS COPYABLE RATHER THAN JUST PRINTED
/// The code exists to be QUOTED — on a receipt, to a staff member, into the
/// history lookup. A code you can only read off a screen has to be transcribed
/// by hand, and `ER-000123` / `ER-000128` are one keystroke apart. Copying is
/// the action this label is for, so it is the action it offers.
class _IdentityCodeChip extends StatelessWidget {
  const _IdentityCodeChip({required this.code});

  final String code;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: code));
    // 'Copied' and 'reg_volunteer_code' are existing keys; nothing new was
    // invented for this chip.
    Get.snackbar('reg_volunteer_code'.tr, 'Copied'.tr);
  }

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      key: const Key('identity_code_chip'),
      onTap: _copy,
      // A copy is a completed action rather than a selection, so it gets the
      // firmer tap — matching how the rest of the app grades its haptics.
      haptic: AppPressHaptic.success,
      semanticLabel: '${'reg_volunteer_code'.tr}: $code',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.badge_outlined, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              // 'reg_volunteer_code' is "Identification code" in all four
              // locales already. A synonym would be new vocabulary for no gain.
              '${'reg_volunteer_code'.tr}:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              code,
              // The code is a machine value in Latin letters and digits, so it
              // keeps its own direction inside an Arabic card rather than being
              // mirrored into something that cannot be read back.
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.copy_rounded,
              size: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small muted section header used to group the settings list.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppThemeConfig.mutedText(context),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.shadow(context),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProfileCompletionReminder extends StatelessWidget {
  const _ProfileCompletionReminder({
    required this.missingFields,
    required this.onEdit,
  });

  final List<String> missingFields;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeConfig.pending(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppThemeConfig.pending(context).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppThemeConfig.pending(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: AppThemeConfig.pending(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Complete your profile'.tr,
                  style: TextStyle(
                    color: AppThemeConfig.pending(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Add the missing details so your account looks trusted and ready to use.'
                .tr,
            style: TextStyle(
              color: AppThemeConfig.pending(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final field in missingFields)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    field.tr,
                    style: TextStyle(
                      color: AppThemeConfig.pending(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onEdit,
            style: FilledButton.styleFrom(
              backgroundColor: AppThemeConfig.pending(context),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.edit_rounded),
            label: Text('Finish now'.tr),
          ),
        ],
      ),
    );
  }
}

class _ProfileOptionTile extends StatelessWidget {
  const _ProfileOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget card = _ProfileCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle.tr,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            AppIcons.forward(context),
            size: 16,
            color: AppThemeConfig.mutedText(context),
          ),
        ],
      ),
    );
    return onTap == null
        ? card
        : AppPressable(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: card,
          );
  }
}

class _LogoutTile extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const _LogoutTile({required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: _ProfileCard(
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.logout_rounded, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Log out'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sign out of your account securely.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(AppIcons.forward(context), color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable language: a script badge, the name in its OWN script, an
/// English descriptor, and the locale to switch to.
class _LanguageOption {
  const _LanguageOption(
    this.code,
    this.nativeName,
    this.englishName,
    this.locale,
  );

  final String code; // short badge glyph, e.g. "EN", "ع", "سۆ", "با"
  final String nativeName; // shown in the language's own script
  final String englishName; // descriptor, localized
  final Locale locale;
}

class _LanguagePreferenceCard extends StatelessWidget {
  const _LanguagePreferenceCard();

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

  @override
  Widget build(BuildContext context) {
    final currentCode = AppLocaleService.localeTag(
      Get.locale ?? AppLocaleService.english,
    );

    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppThemeConfig.accent(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.translate_rounded,
                  color: AppThemeConfig.accent(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Language'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppThemeConfig.text(context),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Choose your preferred language.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _LanguageOptionRow(
              option: _options[i],
              selected:
                  currentCode == AppLocaleService.localeTag(_options[i].locale),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageOptionRow extends StatelessWidget {
  const _LanguageOptionRow({required this.option, required this.selected});

  final _LanguageOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => AppLocaleService.changeLocale(option.locale),
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.snapDuration),
          curve: AppMotion.resolveCurve(context, Curves.easeOut),
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
              // Script badge.
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppThemeConfig.accent(context)
                      : AppThemeConfig.accent(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  option.code,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppThemeConfig.accent(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
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
                        fontSize: 14.5,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      option.englishName.tr,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppThemeConfig.accent(context)
                    : AppThemeConfig.mutedText(context).withValues(alpha: 0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// #31 — notification on/off switch, persisted server-side. When off, the
// backend skips this user's in-app + push notifications.
class _NotificationPreferenceCard extends StatefulWidget {
  const _NotificationPreferenceCard();

  @override
  State<_NotificationPreferenceCard> createState() =>
      _NotificationPreferenceCardState();
}

class _NotificationPreferenceCardState
    extends State<_NotificationPreferenceCard> {
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;

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
      // Keep the optimistic default (on) if the fetch fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool next) async {
    setState(() {
      _enabled = next;
      _saving = true;
    });
    try {
      await const ModuleApi().setNotificationSetting(next);
    } catch (_) {
      if (mounted) setState(() => _enabled = !next); // revert on failure
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _enabled,
        activeThumbColor: AppThemeConfig.accent(context),
        onChanged: (_loading || _saving) ? null : _toggle,
        title: Text(
          'Notifications'.tr,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppThemeConfig.text(context),
          ),
        ),
        subtitle: Text(
          'Receive updates and alerts from the app.'.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            height: 1.35,
            fontSize: 13,
          ),
        ),
        secondary: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.notifications_rounded,
            color: AppThemeConfig.accent(context),
          ),
        ),
      ),
    );
  }
}

// #37 — mute switch: silences sounds, haptics, and spoken summaries.
class _MutePreferenceCard extends StatelessWidget {
  const _MutePreferenceCard();

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      child: ValueListenableBuilder<bool>(
        valueListenable: AppMute.muted,
        builder: (context, muted, _) {
          return SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: muted,
            activeThumbColor: AppThemeConfig.accent(context),
            onChanged: (v) {
              AppMute.set(v);
              if (v) AppVoice.stop();
            },
            title: Text(
              'mute_all'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppThemeConfig.text(context),
              ),
            ),
            subtitle: Text(
              'mute_all_desc'.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.35,
                fontSize: 13,
              ),
            ),
            secondary: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: AppThemeConfig.subtleText(context),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThemePreferenceCard extends StatelessWidget {
  const _ThemePreferenceCard();

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppThemeConfig.accent(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.contrast_rounded,
                  color: AppThemeConfig.accent(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dark mode'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Use a darker appearance across the app.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const AppThemeModePicker(),
        ],
      ),
    );
  }
}
