import 'dart:io';

import 'package:flutter/material.dart';
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
import '../../marriage/screens/marriage_chats_screen.dart';
import '../../marriage/screens/marriage_form_screen.dart';
import '../../marriage/screens/marriage_my_profile_screen.dart';
import '../../marriage/screens/marriage_search_screen.dart';
import '../../search/screens/global_search_screen.dart';
import '../../receipts/screens/aid_receipts_screen.dart';
import '../../../localization/locale_service.dart';
import 'package:flutter_application_1/modules/legal/screens/content_page_screen.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';

const Color _profilePrimary = Color(0xFF0F766E);
const Color _profilePrimaryDark = Color(0xFF115E59);
const Color _profileDanger = Color(0xFFEF4444);

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
                style: TextButton.styleFrom(foregroundColor: _profileDanger),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeConfig.backgroundTop(context),
            AppThemeConfig.backgroundBottom(context),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Profile & Settings'.tr,
                  style: TextStyle(
                    fontSize: 26,
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
                            isComplete: isComplete,
                            onEdit: _openEditProfile,
                            avatar: CachedProfileAvatar(
                              localPath: _localProfileImagePath(),
                              imageUrl: _remoteProfileImageUrl(),
                              radius: 38,
                              backgroundColor: _profilePrimaryDark,
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
                  _ProfileOptionTile(
                    icon: Icons.security_rounded,
                    title: "Privacy & Security",
                    subtitle:
                        'Control account access, passwords, and verification.',
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 12),
                  // #32 — choose which profile fields are public/hidden.
                  _ProfileOptionTile(
                    icon: Icons.visibility_off_rounded,
                    title: 'Field privacy',
                    subtitle: 'privacy_desc',
                    color: Colors.indigo,
                    onTap: () => Get.to(() => const FieldPrivacyScreen()),
                  ),
                  const SizedBox(height: 12),
                  _ProfileOptionTile(
                    icon: Icons.payment_rounded,
                    title: "Payment Methods",
                    subtitle:
                        'View cards, recurring donations, and billing details.',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  _ProfileOptionTile(
                    icon: Icons.tune_rounded,
                    title: "App Settings",
                    subtitle:
                        'Customize notifications, language, and preferences.',
                    color: Colors.blueAccent,
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
                    color: Colors.blue,
                    onTap: () => Get.to(() => const GlobalSearchScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #50 — the user's digital aid-delivery receipts.
                  _ProfileOptionTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'receipts_title',
                    subtitle: 'receipts_subtitle',
                    color: Colors.teal,
                    onTap: () => Get.to(() => const AidReceiptsScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #49 — share the app to other apps (WhatsApp, Telegram, …).
                  _ProfileOptionTile(
                    icon: Icons.ios_share_rounded,
                    title: 'share_app',
                    subtitle: 'share_app_desc',
                    color: Colors.green,
                    onTap: shareApp,
                  ),
                  // #42 — marriage profile (eligible role only, matching backend).
                  if (sharedPreferences.getString('role_id') == '2') ...[
                    const SizedBox(height: 12),
                    _ProfileOptionTile(
                      icon: Icons.favorite_outline_rounded,
                      title: 'marriage_title',
                      subtitle: 'marriage_subtitle',
                      color: Colors.pink,
                      onTap: () => Get.to(() => const MarriageFormScreen()),
                    ),
                    const SizedBox(height: 12),
                    // #46 — search/save/request-meeting on marriage profiles.
                    _ProfileOptionTile(
                      icon: Icons.search_rounded,
                      title: 'marriage_search',
                      subtitle: 'marriage_search_desc',
                      color: Colors.pinkAccent,
                      onTap: () => Get.to(() => const MarriageSearchScreen()),
                    ),
                    const SizedBox(height: 12),
                    // Note #18 — the user's own submitted profile + status.
                    _ProfileOptionTile(
                      icon: Icons.fact_check_outlined,
                      title: 'marriage_my_profile',
                      subtitle: 'marriage_my_profile_desc',
                      color: Colors.deepOrange,
                      onTap: () => Get.to(() => const MarriageMyProfileScreen()),
                    ),
                    const SizedBox(height: 12),
                    // Note #35 — staff-mediated chat for approved meeting requests.
                    _ProfileOptionTile(
                      icon: Icons.forum_outlined,
                      title: 'marriage_chats_title',
                      subtitle: 'marriage_chats_subtitle',
                      color: Colors.purple,
                      onTap: () => Get.to(() => const MarriageChatsScreen()),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _ProfileOptionTile(
                    icon: Icons.apps_rounded,
                    title: 'Services',
                    subtitle: 'Requests, forms, partners, support, and more.',
                    color: Colors.deepPurple,
                    // #6 — Services moved off the bottom nav; open its section
                    // (index 8) which stays reachable via dashboardTabNotifier.
                    onTap: () => dashboardTabNotifier.value = 8,
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
                    color: Colors.blueGrey,
                    onTap: () => Get.to(() => const TermsScreen()),
                  ),
                  const SizedBox(height: 12),
                  // #35 — About Us + Contact (admin-editable content pages).
                  _ProfileOptionTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About Us',
                    subtitle: 'about_desc',
                    color: Colors.teal,
                    onTap: () => Get.to(() => const ContentPageScreen(
                          slug: 'about',
                          titleKey: 'About Us',
                        )),
                  ),
                  const SizedBox(height: 12),
                  _ProfileOptionTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Contact Us',
                    subtitle: 'contact_desc',
                    color: Colors.orange,
                    onTap: () => Get.to(() => const ContentPageScreen(
                          slug: 'contact',
                          titleKey: 'Contact Us',
                        )),
                  ),

                  const SizedBox(height: 24),
                  _LogoutTile(
                    color: _profileDanger,
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
    required this.isComplete,
    required this.avatar,
    required this.onEdit,
  });

  final String name;
  final String subtitle;
  final String? roleLabel;
  final bool isComplete;
  final Widget avatar;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // Ring + badge turn gold/amber when the profile is incomplete, green when
    // everything's filled in — a calm at-a-glance status.
    final ringColor = isComplete ? Colors.white : const Color(0xFFFBBF24);
    final badgeColor = isComplete
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 14, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_profilePrimary, _profilePrimaryDark],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _profilePrimary.withValues(alpha: 0.35),
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
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.edit_rounded,
                  color: _profilePrimary,
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
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF7E1),
            const Color(0xFFFFE7B7).withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF4B942).withValues(alpha: 0.6),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD166),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF9A5A00),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Complete your profile'.tr,
                  style: const TextStyle(
                    color: Color(0xFF9A5A00),
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
            style: const TextStyle(color: Color(0xFF9A5A00), height: 1.4),
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
                    style: const TextStyle(
                      color: Color(0xFF9A5A00),
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
              backgroundColor: const Color(0xFFB45309),
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
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: AppThemeConfig.mutedText(context),
          ),
        ],
      ),
    );
    return onTap == null
        ? card
        : GestureDetector(
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
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
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
                  color: _profilePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.translate_rounded,
                  color: _profilePrimary,
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
                  currentCode ==
                  AppLocaleService.localeTag(_options[i].locale),
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? _profilePrimary.withValues(alpha: 0.08)
                : AppThemeConfig.softSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _profilePrimary
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
                      ? _profilePrimary
                      : _profilePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  option.code,
                  style: TextStyle(
                    color: selected ? Colors.white : _profilePrimary,
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
                    ? _profilePrimary
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
        activeThumbColor: _profilePrimary,
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
          child: const Icon(Icons.notifications_rounded, color: Colors.teal),
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
            activeThumbColor: _profilePrimary,
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
                color: Colors.blueGrey,
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
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, mode, _) {
          final isDark = mode == ThemeMode.dark;
          return SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: isDark,
            activeThumbColor: _profilePrimary,
            title: Text(
              'Dark mode'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppThemeConfig.text(context),
              ),
            ),
            subtitle: Text(
              'Use a darker appearance across the app.'.tr,
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
                color: Colors.indigo.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.dark_mode_rounded, color: Colors.indigo),
            ),
            onChanged: setAppDarkMode,
          );
        },
      ),
    );
  }
}
