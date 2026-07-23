import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';

// Client note — "Settings and Profile Interface" opens as a side drawer on
// tap (see widgets/settings_drawer.dart, attached to the dashboard Scaffold
// in dashboard_screen.dart). This button just opens it.

const Color _brandTeal = Color(0xFF0F766E);
const Color _brandTealLight = Color(0xFF14B8A6);
const Color _avatarBg = Color(0xFF115E59);
const Color _danger = Color(0xFFEF4444);

String? _profileImagePath() => sharedPreferences.getString('profile_image_path');
String? _profileImageUrl() => sharedPreferences.getString('profile_picture_url');

/// Top-right profile avatar button that opens the Settings/Profile drawer.
/// Shows the user's photo (or their initial / a person icon).
///
/// Note #41 — now shown in the persistent top bar on every tab (previously
/// only on Home). [showIndicatorDot] surfaces the "profile incomplete" nudge
/// that used to live on the Profile bottom-nav icon, now that Profile isn't
/// a tab anymore.
class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({super.key, this.showIndicatorDot = false});

  final bool showIndicatorDot;

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
            Scaffold.of(context).openDrawer();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
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
              if (showIndicatorDot)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _danger,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppThemeConfig.navBarSurface(context),
                        width: 2,
                      ),
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

