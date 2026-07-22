import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const Color _primary = Color(0xFF0F766E);
  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

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
    _profileImagePath = sharedPreferences.getString('profile_image_path');
    final rawUrl = sharedPreferences.getString('profile_picture_url');
    final fixedUrl = normalizeProfilePictureUrl(rawUrl);
    if (fixedUrl != null && fixedUrl != rawUrl) {
      sharedPreferences.setString('profile_picture_url', fixedUrl);
    }
    _remoteProfilePictureUrl = fixedUrl;
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
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image == null || !mounted) return;

    setState(() {
      _profileImagePath = image.path;
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
      if (hasLocalFile) {
        await sharedPreferences.setString('profile_image_path', localPath);
      } else if ((localPath ?? '').isEmpty) {
        await sharedPreferences.remove('profile_image_path');
      }
    }

    await syncProfileCompletionPreference(
      missingFields: _draftMissingProfileFields,
    );

    setState(() => _isSaving = false);
    AppHaptics.success();
    Get.back(result: true);
    Get.snackbar(
      'Profile updated'.tr,
      'Your profile details have been saved.'.tr,
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
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: _primary, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit profile'.tr)),
      body: Container(
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
                        alignment: Alignment.bottomRight,
                        children: [
                          _ProfileCompletionAvatar(
                            isComplete: _isDraftProfileComplete,
                            radius: 48,
                            avatar: CachedProfileAvatar(
                              localPath: _effectiveLocalImagePath,
                              imageUrl: _remoteProfilePictureUrl,
                              radius: 48,
                              backgroundColor: _primary,
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
                              color: _primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _ProfileCompletionBanner(
                        isComplete: _isDraftProfileComplete,
                        missingFields: _draftMissingProfileFields,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Profile picture'.tr,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose a photo from your gallery to personalize your account.'
                            .tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _pickProfileImage,
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text('Choose image'.tr),
                          ),
                          if (_hasProfileImage)
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
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  child: Column(
                    children: [
                      // Read-only phone number — this is the OTP-verified
                      // login identity, so it's shown but not editable here.
                      // #39 — forced LTR so the digit grouping doesn't
                      // mirror under an RTL (Arabic/Kurdish) locale.
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: TextFormField(
                          readOnly: true,
                          initialValue: _displayPhone(),
                          decoration: _inputDecoration(
                            context,
                            label: 'Phone number',
                            icon: Icons.phone_outlined,
                          ).copyWith(
                            suffixIcon: Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppThemeConfig.mutedText(context),
                            ),
                            helperText: 'Your verified number'.tr,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          context,
                          label: 'Full name',
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
                          label: 'Address',
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
                        'Select the option that best describes you.'.tr,
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
                          final isSelected = option == _selectedGender;
                          return ChoiceChip(
                            label: Text(option.tr),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() => _selectedGender = option);
                            },
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppThemeConfig.text(context),
                              fontWeight: FontWeight.w700,
                            ),
                            selectedColor: _primary,
                            backgroundColor: AppThemeConfig.softSurface(
                              context,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? _primary
                                  : AppThemeConfig.border(context),
                            ),
                            showCheckmark: false,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
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
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD166), Color(0xFFF59E0B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(shoulderHeight),
                    bottom: const Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.24),
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
                  color: const Color(0xFFF97316),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97316).withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: Colors.white,
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
    final background = isComplete
        ? const Color(0xFFD1FAE5)
        : const Color(0xFFFFF4D8);
    final foreground = isComplete
        ? const Color(0xFF047857)
        : const Color(0xFFB45309);
    final title = isComplete ? 'Profile complete' : 'Complete your profile';
    final subtitle = isComplete
        ? 'Your account card is now fully set up.'
        : 'Add the missing details so your account looks trusted and ready to use.';

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
