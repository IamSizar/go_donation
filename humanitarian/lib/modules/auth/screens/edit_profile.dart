import 'dart:io';
import 'package:flutter_application_1/core/widgets/app_main_menu_button.dart';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/modules/auth/widgets/gender_choice_chip.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];

  bool _genderLocked = false;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();

  String? _selectedGender;
  String? _profileImagePath;
  String? _remoteProfilePictureUrl;
  bool _removeProfilePicture = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = sharedPreferences.getString('name_user') ?? '';
    _addressController.text = sharedPreferences.getString('address_user') ?? '';
    _nameController.addListener(_refreshDraftState);
    _addressController.addListener(_refreshDraftState);
    _selectedGender = sharedPreferences.getString('gender_user');
    // Gender is chosen once, at sign-up. If one is already stored the chips
    // render as a read-only summary — the backend ignores a change anyway
    // (profile.Set only writes gender when the stored value is blank), so
    // letting the UI offer it would be a control that silently does nothing.
    _genderLocked = (_selectedGender ?? '').trim().isNotEmpty;
    _profileImagePath = sharedPreferences.getString('profile_image_path');
    final rawUrl = sharedPreferences.getString('profile_picture_url');
    final fixedUrl = normalizeProfilePictureUrl(rawUrl);
    if (fixedUrl != null && fixedUrl != rawUrl) {
      sharedPreferences.setString('profile_picture_url', fixedUrl);
    }
    _remoteProfilePictureUrl = fixedUrl;
    // Self-heal a stale local cache: older app versions (and a bug in the
    // registration flow, since fixed) could leave fields like gender saved
    // on the server but never mirrored into local prefs, so this screen
    // would wrongly nag the user to re-enter something they already set.
    // Only refetch when the local copy actually looks incomplete, so this
    // doesn't clobber an in-progress edit or add a network call for
    // everyone on every open.
    if (_selectedGender == null || _selectedGender!.trim().isEmpty) {
      _refreshFromServer();
    }
  }

  Future<void> _refreshFromServer() async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) return;
    final account = await fetchUserAccount(userId);
    if (account == null || !mounted) return;
    await applyUserAccountToSharedPreferences(account, includeRoleId: false);
    if (!mounted) return;
    setState(() {
      _selectedGender ??= sharedPreferences.getString('gender_user');
      if (_nameController.text.isEmpty) {
        _nameController.text = sharedPreferences.getString('name_user') ?? '';
      }
      if (_addressController.text.isEmpty) {
        _addressController.text =
            sharedPreferences.getString('address_user') ?? '';
      }
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_refreshDraftState);
    _addressController.removeListener(_refreshDraftState);
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _refreshDraftState() {
    if (mounted) setState(() {});
  }

  Future<void> _pickProfileImage() async {
    // Locked to a square: the avatar is drawn in a circle everywhere it
    // appears, so any other shape would just be cropped again at display time.
    final path = await pickCroppedImage(context, lockRatio: PhotoShape.square);

    if (path == null || !mounted) return;

    setState(() {
      _profileImagePath = path;
      _removeProfilePicture = false;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedGender == null) {
      Get.snackbar(
        'Gender required'.tr,
        'Please choose a gender.'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) {
      Get.snackbar(
        'Error'.tr,
        'No user ID found. Please sign in again.'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() => _isSaving = true);

    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final gender = _selectedGender!;
    final localPath = _profileImagePath;
    final hasLocalFile =
        localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();

    final result = await updateUserProfile(
      userId: userId,
      fullName: name,
      address: address,
      gender: gender,
      localImagePath: hasLocalFile ? localPath : null,
      removeProfilePicture: _removeProfilePicture && !hasLocalFile,
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() => _isSaving = false);
      AppHaptics.error();
      Get.snackbar(
        'Could not save'.tr,
        result.errorMessage ?? 'Unknown error'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await sharedPreferences.setString('name_user', result.fullName ?? name);
    await sharedPreferences.setString(
      'address_user',
      result.address ?? address,
    );
    await sharedPreferences.setString('gender_user', result.gender ?? gender);

    if (result.profilePictureUrl != null &&
        result.profilePictureUrl!.isNotEmpty) {
      await sharedPreferences.setString(
        'profile_picture_url',
        result.profilePictureUrl!,
      );
      await sharedPreferences.remove('profile_image_path');
      setState(() {
        _remoteProfilePictureUrl = result.profilePictureUrl;
        _profileImagePath = null;
        _removeProfilePicture = false;
      });
    } else if (_removeProfilePicture) {
      await sharedPreferences.remove('profile_picture_url');
      await sharedPreferences.remove('profile_image_path');
      setState(() {
        _remoteProfilePictureUrl = null;
        _profileImagePath = null;
        _removeProfilePicture = false;
      });
    } else {
      // E17 — do NOT cache the picked file when the photo is awaiting review.
      // The server deliberately returns the LIVE picture (the old one, or
      // none), so caching the local path here would show the user their
      // unapproved photo everywhere in the app while staff still see the
      // pending request. A second, quieter version of the same lie the
      // snackbar was telling.
      if (hasLocalFile && !result.isPicturePending) {
        await sharedPreferences.setString('profile_image_path', localPath);
      } else if ((localPath ?? '').isEmpty || result.isPicturePending) {
        await sharedPreferences.remove('profile_image_path');
        if (result.isPicturePending) {
          setState(() => _profileImagePath = null);
        }
      }
    }

    await syncProfileCompletionPreference(
      missingFields: _draftMissingProfileFields,
    );

    setState(() => _isSaving = false);
    AppHaptics.success();
    Get.back(result: true);
    // E17 — the message used to be the same sentence whatever happened, so a
    // user whose name went to the review queue was told it had been saved. The
    // server has always said which fields it queued; nothing read it until now.
    // The branch itself lives in profile_api.dart so it can be tested.
    final message = profileSaveMessage(result);
    Get.snackbar(
      message.title.tr,
      message.body.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  String? get _effectiveLocalImagePath {
    final path = _profileImagePath;
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  bool get _hasProfileImage {
    if (_effectiveLocalImagePath != null) return true;
    final url = _remoteProfilePictureUrl;
    return url != null && url.isNotEmpty;
  }

  List<String> get _draftMissingProfileFields {
    final missing = <String>[];
    if (_nameController.text.trim().isEmpty) {
      missing.add('Full name');
    }
    if (_addressController.text.trim().isEmpty) {
      missing.add('Address');
    }
    if ((_selectedGender ?? '').trim().isEmpty) {
      missing.add('Gender');
    }
    if (!_hasProfileImage) {
      missing.add('Profile picture');
    }
    return missing;
  }

  bool get _isDraftProfileComplete => _draftMissingProfileFields.isEmpty;

  // #39 — the signed-in user's phone, normalized for display. Stored
  // canonically as "<dial code><national number>" with no leading "+"
  // (e.g. "9647508582031"); we prefix a "+" so it reads as a proper E.164
  // phone. Range matches the backend's NormalizePhone sanity check (7-15
  // digits total).
  String _displayPhone() {
    final raw = (sharedPreferences.getString('phone_user') ?? '').trim();
    if (raw.isEmpty) return '—';
    if (raw.startsWith('+')) return raw;
    final digitsOnly = RegExp(r'^\d{7,15}$').hasMatch(raw);
    return digitsOnly ? '+$raw' : raw;
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label.tr,
      prefixIcon: Icon(icon, color: AppThemeConfig.mutedText(context)),
      filled: true,
      fillColor: AppThemeConfig.softSurface(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppThemeConfig.border(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppThemeConfig.border(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(
          color: AppThemeConfig.accent(context),
          width: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit profile'.tr),
        actions: const [AppMainMenuButton()],
      ),
      body: Container(
        decoration: BoxDecoration(color: AppThemeConfig.backgroundTop(context)),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                _SectionCard(
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: AlignmentDirectional.bottomEnd,
                        children: [
                          _ProfileCompletionAvatar(
                            isComplete: _isDraftProfileComplete,
                            radius: 48,
                            avatar: CachedProfileAvatar(
                              localPath: _effectiveLocalImagePath,
                              imageUrl: _remoteProfilePictureUrl,
                              radius: 48,
                              backgroundColor: AppThemeConfig.accent(context),
                              placeholder: const Icon(
                                Icons.person,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: _pickProfileImage,
                              icon: const Icon(Icons.photo_camera_outlined),
                              color: AppThemeConfig.accent(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Profile picture'.tr,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      if (!_isDraftProfileComplete) ...[
                        const SizedBox(height: 14),
                        _ProfileCompletionBanner(
                          isComplete: _isDraftProfileComplete,
                          missingFields: _draftMissingProfileFields,
                        ),
                      ],
                      // Note: the camera icon on the avatar above is the only
                      // way to pick a photo now — it used to be duplicated by
                      // a "Choose image" button here that did the exact same
                      // thing.
                      if (_hasProfileImage) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _profileImagePath = null;
                              _remoteProfilePictureUrl = null;
                              _removeProfilePicture = true;
                            });
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text('Remove image'.tr),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  child: Column(
                    children: [
                      // Read-only phone number — this is the OTP-verified
                      // login identity, so it cannot be edited from the
                      // profile form at all; changing it means re-verifying a
                      // new number, which is a different flow.
                      //
                      // It used to be a `readOnly: true` TextFormField sitting
                      // in a column of editable ones, which made it look like
                      // every other input on the screen: users tapped it and
                      // got nothing back. It is now a labelled value row, so
                      // there is no input affordance to fight with, and the
                      // helper line says why rather than just restating what
                      // the value is.
                      _LockedPhoneRow(phone: _displayPhone()),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          context,
                          label: 'Full name'.tr,
                          icon: Icons.person_outline_rounded,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name.'.tr;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        decoration: _inputDecoration(
                          context,
                          label: 'Address'.tr,
                          icon: Icons.home_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your address.'.tr;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gender'.tr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _genderLocked
                            ? 'Gender cannot be changed after sign-up.'.tr
                            : 'Select the option that best describes you.'.tr,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _genderOptions.map((option) {
                          return GenderChoiceChip(
                            label: option.tr,
                            selected: option == _selectedGender,
                            locked: _genderLocked,
                            onSelected: () =>
                                setState(() => _selectedGender = option),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppThemeConfig.accent(context),
                    // NOT Colors.white: the dark accent is a light mint, so white
                    // text on it measures 2.19:1. onAccent is the contrast
                    // partner that flips with the theme.
                    foregroundColor: AppThemeConfig.onAccent(context),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _isSaving ? 'Saving...'.tr : 'Save profile'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The account's verified phone number, presented as a locked value row.
///
/// WHY NOT A TEXT FIELD
/// The number is the OTP-verified login identity; the profile form cannot
/// change it. A `readOnly` TextFormField would still look identical to the
/// editable name and address fields beneath it, so the false affordance stays
/// and the user learns nothing from tapping it. A label + value + padlock, and
/// a line saying why it is locked, removes the affordance at the source.
class _LockedPhoneRow extends StatelessWidget {
  const _LockedPhoneRow({required this.phone});

  /// Already formatted for display; '—' when nothing is on file.
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppThemeConfig.softSurface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppThemeConfig.border(context)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.phone_outlined,
                color: AppThemeConfig.mutedText(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phone number'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // #39 — forced LTR so the digit grouping doesn't mirror
                    // under an RTL (Arabic/Kurdish) locale.
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          phone,
                          style: TextStyle(
                            color: AppThemeConfig.text(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppThemeConfig.mutedText(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(
            'This is the verified number you sign in with, so it cannot be '
                    'edited here.'
                .tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

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
    final width = radius * 2 + 24;
    final shoulderHeight = radius * 0.9;
    return SizedBox(
      width: width,
      height: radius * 2 + 18,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (!isComplete)
            Positioned(
              bottom: 2,
              child: Container(
                width: width,
                height: shoulderHeight,
                decoration: BoxDecoration(
                  color: AppThemeConfig.pending(context),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(shoulderHeight),
                    bottom: const Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppThemeConfig.pending(
                        context,
                      ).withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(top: 0, child: avatar),
          if (!isComplete)
            Positioned(
              top: -2,
              right: 4,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppThemeConfig.pending(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppThemeConfig.pending(
                        context,
                      ).withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.priority_high_rounded,
                  color: AppThemeConfig.onAccent(context),
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileCompletionBanner extends StatelessWidget {
  const _ProfileCompletionBanner({
    required this.isComplete,
    required this.missingFields,
  });

  final bool isComplete;
  final List<String> missingFields;

  @override
  Widget build(BuildContext context) {
    // Once the profile is complete there's nothing left to prompt the user
    // about — don't show a "you're done" banner at all, just show nothing.
    if (isComplete) return const SizedBox.shrink();

    // The same incomplete-profile prompt as profile.dart, on the same token.
    final background = AppThemeConfig.pending(context).withValues(alpha: 0.10);
    final foreground = AppThemeConfig.pending(context);
    const title = 'Complete your profile';
    const subtitle =
        'Add the missing details so your account looks trusted and ready to use.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.check_circle_rounded : Icons.auto_awesome,
                color: foreground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.tr,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle.tr,
            style: TextStyle(color: foreground.withValues(alpha: 0.92)),
          ),
          if (!isComplete && missingFields.isNotEmpty) ...[
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
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      field.tr,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
