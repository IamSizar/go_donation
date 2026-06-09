import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';

import 'edit_profile.dart';
import '../../../localization/locale_service.dart';

const Color _profilePrimary = Color(0xFF0F766E);
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
                onPressed: () {
                  sharedPreferences.clear();

                  Navigator.of(context).pop(true);
                },

                style: TextButton.styleFrom(foregroundColor: _profileDanger),
                child: Text('Log out'.tr),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      await sharedPreferences.remove('id_user');
      await sharedPreferences.remove('email_user');
      await sharedPreferences.remove('phone_user');
      await sharedPreferences.remove('name_user');
      await sharedPreferences.remove('address_user');
      await sharedPreferences.remove('gender_user');
      await sharedPreferences.remove('profile_image_path');
      await sharedPreferences.remove('profile_picture_url');
      await clearApiSession();
      Get.offAllNamed('/login');
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
    return details.join(' - ');
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Move the IconButton next to the profile display section below,
                  // So remove it from here entirely.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile & Settings'.tr,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppThemeConfig.text(context),
                          ),
                        ),

                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                  // Removed IconButton from here
                ],
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
                      return _ProfileCard(
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: _ProfileCompletionAvatar(
                                      isComplete: isComplete,
                                      radius: 26,
                                      avatar: CachedProfileAvatar(
                                        localPath: _localProfileImagePath(),
                                        imageUrl: _remoteProfileImageUrl(),
                                        radius: 26,
                                        backgroundColor: _profilePrimary,
                                        placeholder: const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      _profileName(),
                                      style: TextStyle(
                                        color: AppThemeConfig.text(context),
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _profileSubtitle(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppThemeConfig.mutedText(
                                              context,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Builder(
                                          builder: (context) {
                                            final String? roleId =
                                                sharedPreferences.getString(
                                                  'role_id',
                                                );
                                            String? roleLabel;
                                            if (roleId == '1') {
                                              roleLabel = 'Donor';
                                            } else if (roleId == '2') {
                                              roleLabel = 'Beneficiary';
                                            } else if (roleId == '3') {
                                              roleLabel = 'Volunteer';
                                            }
                                            if (roleLabel != null) {
                                              return Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .verified_user_outlined,
                                                    size: 17,
                                                    color:
                                                        AppThemeConfig.mutedText(
                                                          context,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Flexible(
                                                    child: Text(
                                                      roleLabel.tr,
                                                      style: TextStyle(
                                                        color:
                                                            AppThemeConfig.mutedText(
                                                              context,
                                                            ),
                                                        fontSize: 14,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }
                                            return const SizedBox();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  color: AppThemeConfig.text(context),
                                  icon: const Icon(Icons.edit_rounded),
                                  onPressed: _openEditProfile,
                                ),
                              ],
                            ),
                            if (!isComplete) ...[
                              const SizedBox(height: 14),
                              _ProfileCompletionReminder(
                                missingFields: missingFields,
                                onEdit: _openEditProfile,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  const SizedBox(height: 12),

                  const _ProfileOptionTile(
                    icon: Icons.security_rounded,
                    title: "Privacy & Security",
                    subtitle:
                        'Control account access, passwords, and verification.',
                    color: Colors.deepPurple,
                  ),

                  const SizedBox(height: 12),
                  const _ProfileOptionTile(
                    icon: Icons.payment_rounded,
                    title: "Payment Methods",
                    subtitle:
                        'View cards, recurring donations, and billing details.',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  const _LanguagePreferenceCard(),
                  const SizedBox(height: 12),
                  const _ThemePreferenceCard(),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () {
                        // TODO: Implement navigation to App Settings
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blueAccent.withValues(alpha: 0.92),
                              Colors.blue[200]!,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(22),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 26,
                              child: Icon(
                                Icons.settings_rounded,
                                size: 28,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    "App Settings",
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Customize notifications, language, and preferences.',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 22,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppThemeConfig.shadow(context),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProfileCompletionAvatar extends StatelessWidget {
  const _ProfileCompletionAvatar({
    required this.isComplete,
    required this.radius,
    required this.avatar,
  });

  final bool isComplete;
  final double radius;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    final width = radius * 2 + 16;
    final shoulderHeight = radius * 0.9;
    return SizedBox(
      width: width,
      height: radius * 2 + 14,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (!isComplete)
            Positioned(
              bottom: 0,
              child: Container(
                width: width,
                height: shoulderHeight,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE39A), Color(0xFFF4B942)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(shoulderHeight),
                    bottom: const Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF4B942).withValues(alpha: 0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(top: 0, child: avatar),
          if (!isComplete)
            Positioned(
              top: -3,
              right: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title.tr,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppThemeConfig.text(context),
          ),
        ),
        subtitle: Text(
          subtitle.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            height: 1.4,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 18,
          color: AppThemeConfig.mutedText(context),
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const _LogoutTile({required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.logout_rounded, color: color),
        ),
        title: Text(
          'Log out'.tr,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            fontSize: 17,
          ),
        ),
        subtitle: Text(
          'Sign out of your account securely.'.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            height: 1.4,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded, color: color, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _LanguagePreferenceCard extends StatelessWidget {
  const _LanguagePreferenceCard();

  @override
  Widget build(BuildContext context) {
    final currentCode = AppLocaleService.localeTag(
      Get.locale ?? AppLocaleService.english,
    );

    Widget chip(String label, Locale locale) {
      final isSelected = currentCode == AppLocaleService.localeTag(locale);

      return ChoiceChip(
        label: Text(label.tr),
        selected: isSelected,
        onSelected: (_) => AppLocaleService.changeLocale(locale),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppThemeConfig.text(context),
          fontWeight: FontWeight.w700,
        ),
        selectedColor: _profilePrimary,
        backgroundColor: AppThemeConfig.softSurface(context),
        side: BorderSide(
          color: isSelected
              ? _profilePrimary
              : AppThemeConfig.mutedText(context).withValues(alpha: 0.20),
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
    }

    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Language'.tr,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppThemeConfig.text(context),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Customize notifications, language, and preferences.'.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: [
              chip('English', AppLocaleService.english),
              chip('Arabic', AppLocaleService.arabic),
              chip('Kurdish Sorani', AppLocaleService.kurdishSorani),
              chip('Kurdish Badini', AppLocaleService.kurdishBadini),
            ],
          ),
        ],
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
            activeColor: _profilePrimary,
            title: Text(
              'Dark mode'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppThemeConfig.text(context),
              ),
            ),
            subtitle: Text(
              'Use a darker appearance across the app.'.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.4,
              ),
            ),
            secondary: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
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
