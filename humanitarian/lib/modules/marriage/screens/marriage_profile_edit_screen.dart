// K14 — the owner's edit of their own خطوبتي profile.
//
// WHY THIS SCREEN DID NOT EXIST UNTIL NOW
// `POST /api/marriage` INSERTS a row with a freshly generated profile_code —
// it is a second submission, not an update — and there was no owner-scoped
// write of any kind. marriage_my_profile_screen.dart carried that in writing:
// its button deliberately said "submit a new profile" because "calling it
// 'edit' … promised something the app cannot do". Commit 9f6ec79 added
// PATCH /api/marriage/:id, so the promise can now be kept.
//
// WHAT THIS SCREEN DELIBERATELY DOES NOT OFFER
// Exactly the eleven fields `marriage.OwnerProfilePatch` declares, and nothing
// else. The deeper registration sections — identification, housing, assets,
// health, attachments — are not on that endpoint and still change through
// staff. Rendering an input the server would ignore is worse than not
// rendering it: the user would type, save, see "Saved", and find the value
// unchanged. A caption says which half is which, so the absence reads as a
// rule rather than as a missing feature.
//
// WHERE THE CONTROLS THEMSELVES LIVE
// widgets/marriage_edit_fields.dart. This file owns the state, the validation
// and the save; that one owns how one input looks. The split is what keeps
// both under the 500-line ceiling without either becoming a grab bag.
//
// WHY THE OPTION LISTS ARE COPIED FROM THE SUBMISSION FORM
// gender / marital_status / employment_status / visibility_level use the same
// value sets marriage_form_screen.dart submits and marriage_search_screen.dart
// filters on. A different vocabulary here would store values the Search screen
// cannot find.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/modules/marriage/controllers/marriage_my_profile_controller.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_edit_fields.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// The option sets, shared with the submission form so both write the same
/// vocabulary. `const` lists rather than a lookup: they are the endpoint's
/// contract, not data.
const _genders = ['Male', 'Female'];
const _maritalStatuses = [
  'single',
  'engaged',
  'married',
  'separated',
  'widowed',
  'divorced',
  'separated_never_married',
  'other',
];
const _employmentStatuses = [
  'employed',
  'unemployed',
  'self_employed',
  'student',
];
const _visibilityLevels = ['private', 'employee_only', 'matched_summary'];

/// Resolves a stored photo path against the public host.
///
/// Same rule as marriage_form_screen.dart's copy: an absolute URL is returned
/// untouched, a stored relative path is joined to [publicBaseUrl].
String _resolvePhotoUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final uri = Uri.tryParse(p);
  if (uri != null && uri.hasScheme) return p;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(p.replaceFirst(RegExp(r'^/+'), '')).toString();
}

/// Reads one value out of the profile row, as a trimmed string.
///
/// The server sends these as nullable columns, so `null` is the normal shape
/// of "not answered" and must become an empty field rather than the literal
/// text "null".
String _fieldOf(Map<String, dynamic> profile, String key) =>
    (profile[key] ?? '').toString().trim();

/// Reads a value that must be one of [allowed], or null.
///
/// A stored value outside the list (an older row, or one staff typed by hand)
/// would make DropdownButtonFormField throw on build, so it degrades to "not
/// selected" instead — the user picks again, and nothing is silently rewritten
/// until they do.
String? _optionOf(
  Map<String, dynamic> profile,
  String key,
  List<String> allowed,
) {
  final value = _fieldOf(profile, key);
  return allowed.contains(value) ? value : null;
}

class MarriageProfileEditScreen extends StatefulWidget {
  const MarriageProfileEditScreen({
    super.key,
    required this.profileId,
    required this.profile,
  });

  /// `marriage_profiles.id`. It goes in the PATCH path, where ownership is
  /// checked inside the UPDATE.
  final int profileId;

  /// The row this screen edits, straight from the same GET /api/marriage/mine
  /// response that drew the card it opened from — so there is no second fetch
  /// to fail and no moment where the form is empty while it loads.
  final Map<String, dynamic> profile;

  @override
  State<MarriageProfileEditScreen> createState() =>
      _MarriageProfileEditScreenState();
}

class _MarriageProfileEditScreenState extends State<MarriageProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _age;
  late final TextEditingController _city;
  late final TextEditingController _summary;
  late final TextEditingController _religion;
  late final TextEditingController _weight;
  late final TextEditingController _height;

  String? _gender;
  String? _maritalStatus;
  String? _employmentStatus;
  late String _visibility;
  String _photoUrl = '';

  bool _uploadingPhoto = false;
  bool _saving = false;

  /// The failure of the LAST save, already localized, or null.
  ///
  /// Rendered in the form rather than as a snackbar: a snackbar over a form
  /// the user is still holding disappears before they have re-read the field
  /// it was about.
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _age = TextEditingController(text: _fieldOf(p, 'age'));
    _city = TextEditingController(text: _fieldOf(p, 'city'));
    _summary = TextEditingController(text: _fieldOf(p, 'social_summary'));
    _religion = TextEditingController(text: _fieldOf(p, 'religion'));
    _weight = TextEditingController(text: _fieldOf(p, 'weight_kg'));
    _height = TextEditingController(text: _fieldOf(p, 'height_cm'));
    _gender = _optionOf(p, 'gender', _genders);
    _maritalStatus = _optionOf(p, 'marital_status', _maritalStatuses);
    _employmentStatus = _optionOf(p, 'employment_status', _employmentStatuses);
    // The column is NOT NULL server-side, but a row predating the current set
    // could still hold something else; falling back to the submission form's
    // own default keeps the dropdown from throwing.
    _visibility =
        _optionOf(p, 'visibility_level', _visibilityLevels) ?? 'employee_only';
    _photoUrl = _fieldOf(p, 'photo_url');
  }

  @override
  void dispose() {
    _age.dispose();
    _city.dispose();
    _summary.dispose();
    _religion.dispose();
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  // ─── Validation ─────────────────────────────────────────────────────────

  /// Validates one optional whole-number field.
  ///
  /// Empty is valid and means "clear this": the server writes NULL for a
  /// non-positive number, which is what every unanswered field already looks
  /// like in this table. [min]/[max] are sanity bounds, not policy — they only
  /// exist to catch a typo (an age of 5, a height in metres) before it becomes
  /// a search filter nobody matches.
  String? _validateOptionalNumber(
    String? raw, {
    required int min,
    required int max,
  }) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null) return 'marriage_owner_number_invalid'.tr;
    if (value < min || value > max) {
      return 'marriage_owner_number_range'.trParams({
        // Each bound is wrapped in a Unicode LTR isolate (U+2066 LRI …
        // U+2069 PDI) before it is dropped into an Arabic sentence, the same
        // way phone numbers and funding amounts are. Written as escapes, not
        // as literal marks — the analyzer flags those as
        // text_direction_code_point_in_literal and it is right to.
        'min': '\u2066$min\u2069',
        'max': '\u2066$max\u2069',
      });
    }
    return null;
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    // Square, because the profile photo is drawn as a circular avatar in
    // search results and on the profile card.
    final picked = await pickCroppedImage(
      context,
      lockRatio: PhotoShape.square,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final path = await const ModuleApi().uploadPhoto(File(picked));
      if (mounted) setState(() => _photoUrl = path);
    } catch (e) {
      if (!mounted) return;
      // The upload's own error is a raw exception string, so it is logged and
      // the user gets the form's localized failure line instead.
      debugPrint('marriage owner photo upload failed: $e');
      AppHaptics.error();
      setState(() => _saveError = 'marriage_owner_photo_failed'.tr);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// Builds the patch body.
  ///
  /// EVERY editable field is sent, including the empty ones. That is what makes
  /// "clear this" possible: the server distinguishes an ABSENT key (leave the
  /// column alone) from a present-but-empty one (write NULL), so omitting a
  /// field the user just emptied would silently keep the old value.
  Map<String, dynamic> _patch() => {
    'gender': _gender ?? '',
    'age': int.tryParse(_age.text.trim()) ?? 0,
    'city': _city.text.trim(),
    'social_summary': _summary.text.trim(),
    'marital_status': _maritalStatus ?? '',
    'religion': _religion.text.trim(),
    'employment_status': _employmentStatus ?? '',
    'weight_kg': int.tryParse(_weight.text.trim()) ?? 0,
    'height_cm': int.tryParse(_height.text.trim()) ?? 0,
    'photo_url': _photoUrl,
    'visibility_level': _visibility,
  };

  Future<void> _save() async {
    // The keyboard goes first: without this it stays up over the screen the
    // pop returns to.
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppHaptics.error();
      return;
    }
    AppHaptics.selection();
    setState(() {
      _saving = true;
      _saveError = null;
    });

    final controller = Get.isRegistered<MarriageMyProfileController>()
        ? Get.find<MarriageMyProfileController>()
        : Get.put(MarriageMyProfileController());
    final failure = await controller.updateProfile(widget.profileId, _patch());

    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      setState(() => _saveError = failure);
      return;
    }
    // The controller already refreshed the list and played the success haptic,
    // so the card behind this screen is up to date before it is uncovered.
    Get.back<bool>(result: true);
    Get.snackbar('marriage_my_profile'.tr, 'Saved'.tr);
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_owner_edit_title'.tr,
      subtitle: 'marriage_owner_edit_subtitle'.tr,
      child: Form(
        key: _formKey,
        child: ListView(
          // Dragging the form puts the keyboard away, so it never covers the
          // field below the one being typed into.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            MarriagePhotoField(
              resolvedUrl: _resolvePhotoUrl(_photoUrl),
              uploading: _uploadingPhoto,
              onPick: _pickPhoto,
            ),
            const SizedBox(height: 20),
            const MarriageEditLabel('marriage_gender'),
            MarriageEditDropdown(
              value: _gender,
              hintKey: 'marriage_gender_hint',
              icon: Icons.wc_outlined,
              options: _genders,
              labelOf: (v) => v.tr,
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 14),
            MarriageEditTextField(
              controller: _age,
              labelKey: 'marriage_age',
              icon: Icons.cake_outlined,
              keyboard: TextInputType.number,
              validator: (v) => _validateOptionalNumber(v, min: 16, max: 99),
            ),
            MarriageEditTextField(
              controller: _city,
              labelKey: 'marriage_city',
              icon: Icons.location_city_outlined,
            ),
            MarriageEditTextField(
              controller: _summary,
              labelKey: 'marriage_summary',
              icon: Icons.notes_outlined,
              lines: 3,
            ),
            const MarriageEditLabel('marriage_marital_status'),
            MarriageEditDropdown(
              value: _maritalStatus,
              hintKey: 'marriage_marital_status_hint',
              icon: Icons.people_outline,
              options: _maritalStatuses,
              labelOf: (v) => 'marital_status_$v'.tr,
              onChanged: (v) => setState(() => _maritalStatus = v),
            ),
            const SizedBox(height: 14),
            MarriageEditTextField(
              controller: _religion,
              labelKey: 'marriage_religion',
              icon: Icons.church_outlined,
            ),
            const MarriageEditLabel('marriage_employment_status'),
            MarriageEditDropdown(
              value: _employmentStatus,
              hintKey: 'marriage_employment_status_hint',
              icon: Icons.work_outline,
              options: _employmentStatuses,
              labelOf: (v) => 'employment_status_$v'.tr,
              onChanged: (v) => setState(() => _employmentStatus = v),
            ),
            const SizedBox(height: 14),
            MarriageEditTextField(
              controller: _weight,
              labelKey: 'marriage_weight',
              icon: Icons.monitor_weight_outlined,
              keyboard: TextInputType.number,
              validator: (v) => _validateOptionalNumber(v, min: 30, max: 250),
            ),
            MarriageEditTextField(
              controller: _height,
              labelKey: 'marriage_height',
              icon: Icons.height_rounded,
              keyboard: TextInputType.number,
              validator: (v) => _validateOptionalNumber(v, min: 100, max: 250),
            ),
            const MarriageEditLabel('marriage_privacy'),
            DropdownButtonFormField<String>(
              key: const Key('marriage_owner_visibility'),
              initialValue: _visibility,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.visibility_outlined),
              ),
              items: [
                for (final v in _visibilityLevels)
                  DropdownMenuItem(value: v, child: Text('vis_$v'.tr)),
              ],
              onChanged: (v) =>
                  setState(() => _visibility = v ?? 'employee_only'),
            ),
            const SizedBox(height: 20),
            const MarriageStaffFieldsNote(),
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              MarriageSaveFailure(message: _saveError!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('marriage_owner_save'),
                // Disabled while the write is in flight AND while a photo is
                // uploading, so a save can never race ahead of the URL it is
                // supposed to carry.
                onPressed: _saving || _uploadingPhoto ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : Text('Save'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
