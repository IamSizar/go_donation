import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';

// Dashboard tab indices (mirror modules/dashboard/screens/dashboard_screen.dart).
const int _kProfileTab = 6;
const int _kCommunityTab = 3;
const int _kMessagesTab = 9;

const Color _brandTeal = Color(0xFF0F766E);
const Color _brandTealLight = Color(0xFF14B8A6);
const Color _avatarBg = Color(0xFF115E59);
const Color _danger = Color(0xFFEF4444);

String? _profileImagePath() => sharedPreferences.getString('profile_image_path');
String? _profileImageUrl() => sharedPreferences.getString('profile_picture_url');

String _displayName() {
  final n = (sharedPreferences.getString('name_user') ?? '').trim();
  return n.isEmpty ? 'No name'.tr : n;
}

String _roleLabel() {
  if (isGuestMode()) return 'Guest'.tr;
  switch (sharedPreferences.getString('role_id')) {
    case '1':
      return 'Donor'.tr;
    case '2':
      return 'Beneficiary'.tr;
    case '3':
      return 'Volunteer'.tr;
    default:
      return '';
  }
}

/// Top-right profile avatar button that opens a quick profile menu (task #12).
/// Shows the user's photo (or their initial / a person icon), and on tap opens
/// a role/guest-aware bottom sheet of profile shortcuts.
class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile menu'.tr,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            AppHaptics.selection();
            _showProfileMenu(context);
          },
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_brandTeal, _brandTealLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppThemeConfig.shadow(context),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CachedProfileAvatar(
              localPath: _profileImagePath(),
              imageUrl: _profileImageUrl(),
              radius: 19,
              backgroundColor: _avatarBg,
              placeholder: _AvatarInitial(size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's first initial (or a person icon when there's no name), shown when
/// no profile photo is available.
class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final name = (sharedPreferences.getString('name_user') ?? '').trim();
    if (name.isEmpty) {
      return Center(
        child: Icon(Icons.person, color: Colors.white, size: size + 4),
      );
    }
    // Center + FittedBox so the initial always sits dead-centre and never
    // overflows the circle.
    return Center(
      child: Text(
        name.substring(0, 1).toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

void _showProfileMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProfileMenuSheet(),
  );
}

class _ProfileMenuSheet extends StatelessWidget {
  const _ProfileMenuSheet();

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();
    final role = sharedPreferences.getString('role_id');
    final showMessages = !guest && (role == '1' || role == '2');
    // #13 — beneficiaries reach Community services from here (it's removed from
    // their bottom bar).
    final showCommunity = !guest && role == '2';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppThemeConfig.surface(context),
              AppThemeConfig.elevatedSurface(context),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppThemeConfig.border(context)),
          boxShadow: [
            BoxShadow(
              color: AppThemeConfig.shadow(context),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeConfig.mutedText(context).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                children: [
                  CachedProfileAvatar(
                    localPath: _profileImagePath(),
                    imageUrl: _profileImageUrl(),
                    radius: 26,
                    backgroundColor: _avatarBg,
                    placeholder: _AvatarInitial(size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppThemeConfig.text(context),
                          ),
                        ),
                        if (_roleLabel().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _roleLabel(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppThemeConfig.mutedText(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppThemeConfig.border(context)),
            _MenuTile(
              icon: Icons.person_rounded,
              label: 'Open profile',
              onTap: () {
                Navigator.of(context).pop();
                dashboardTabNotifier.value = _kProfileTab;
              },
            ),
            if (!guest)
              _MenuTile(
                icon: Icons.edit_rounded,
                label: 'Edit profile',
                onTap: () {
                  Navigator.of(context).pop();
                  Get.to<bool>(() => const EditProfilePage());
                },
              ),
            if (showCommunity)
              _MenuTile(
                icon: Icons.groups_rounded,
                label: 'Community services',
                onTap: () {
                  Navigator.of(context).pop();
                  dashboardTabNotifier.value = _kCommunityTab;
                },
              ),
            if (showMessages)
              _MenuTile(
                icon: Icons.forum_rounded,
                label: 'Messages',
                onTap: () {
                  Navigator.of(context).pop();
                  dashboardTabNotifier.value = _kMessagesTab;
                },
              ),
            _MenuTile(
              icon: Icons.description_rounded,
              label: 'Terms & Conditions',
              onTap: () {
                Navigator.of(context).pop();
                Get.to(() => const TermsScreen());
              },
            ),
            Divider(height: 1, color: AppThemeConfig.border(context)),
            guest
                ? _MenuTile(
                    icon: Icons.login_rounded,
                    label: 'Sign in',
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.offAllNamed('/login');
                    },
                  )
                : _MenuTile(
                    icon: Icons.logout_rounded,
                    label: 'Log out',
                    danger: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      _confirmLogout();
                    },
                  ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmLogout() async {
  final confirmed =
      await Get.dialog<bool>(
        AlertDialog(
          title: Text('Log out?'.tr),
          content: Text('Are you sure you want to log out?'.tr),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('Cancel'.tr),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              style: TextButton.styleFrom(foregroundColor: _danger),
              child: Text('Log out'.tr),
            ),
          ],
        ),
      ) ??
      false;
  if (confirmed) {
    // Navigate to login FIRST so the authenticated tree is torn down before the
    // session is cleared (mirrors ProfileSection._handleLogout — avoids a black
    // screen from sections rebuilding against wiped storage).
    Get.offAllNamed('/login');
    await logout();
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final textColor = danger ? _danger : AppThemeConfig.text(context);
    final iconColor = danger ? _danger : _brandTeal;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label.tr,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
