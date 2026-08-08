import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/iraq_governorates.dart';
import 'package:flutter_application_1/data/nineveh_neighborhoods.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_my_profile_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

// Marriage Posts — resolve a stored photo path to a full URL for preview.
// Uploads are saved as relative paths (e.g. images/uploads/x.png);
// Image.network needs an absolute URL. Same pattern as aid_receipts_screen.
String _resolvePhotoUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final uri = Uri.tryParse(p);
  if (uri != null && uri.hasScheme) return p;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(p.replaceFirst(RegExp(r'^/+'), '')).toString();
}

/// #42 — Marriage/engagement profile form with a privacy (visibility) control.
/// Submits to POST /api/marriage. The backend restricts this to the eligible
/// role; the entry tile is only shown to eligible users.
///
/// Note #33 — gender/age/city/social_summary/private_notes are now
/// Field-Rules-driven (GET /api/registration/field-rules, "marriage_" keys,
/// same mechanism as the general registration form's #43): a field the admin
/// marked required is enforced before submit, and one marked hidden isn't
/// rendered at all. visibility_level stays a fixed field (admin workflow
/// setting, not applicant data).
class MarriageFormScreen extends StatefulWidget {
  const MarriageFormScreen({super.key});

  @override
  State<MarriageFormScreen> createState() => _MarriageFormScreenState();
}

class _MarriageFormScreenState extends State<MarriageFormScreen> {
  static const _fieldRulePrefix = 'marriage_';

  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _summaryController = TextEditingController();
  final _notesController = TextEditingController();
  final _religionController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  // "My Engagement" spec — "Identification Information". The identification
  // code itself is marriage_profiles.profile_code, generated server-side.
  final _nationalIdController = TextEditingController();
  final _nameFirstController = TextEditingController();
  final _nameFatherController = TextEditingController();
  final _nameGrandfatherController = TextEditingController();
  final _nameFamilyController = TextEditingController();
  final _tribeClanController = TextEditingController();
  final _titleSurnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phone1Controller = TextEditingController();
  final _phone2Controller = TextEditingController();
  // Date of birth as day/month/year dropdowns, matching the main
  // registration form (client spec asks for dropdowns, not a picker).
  int? _dobDay;
  int? _dobMonth;
  int? _dobYear;
  String? _gender; // Male | Female
  String? _maritalStatus; // single | married | widowed | divorced
  String? _employmentStatus; // employed | unemployed | self_employed | student
  // "My Engagement" spec — "Personal Information".
  String? _nationality;
  String? _residencyStatus;

  // "My Engagement" spec — "Housing Information" / "Housing Type".
  String? _governorate;
  String? _housingSide; // right | left | other — Nineveh only
  String? _neighborhoodDropdown; // Nineveh: from the side's list
  final _neighborhoodController = TextEditingController(); // other governorates
  final _nearestLandmarkController = TextEditingController();
  final _yearsCurrentController = TextEditingController();
  final _previousResidenceController = TextEditingController();
  final _yearsPreviousController = TextEditingController();
  String? _housingType;
  final _rentalAmountController = TextEditingController();
  final _housingAreaController = TextEditingController();
  String? _floorsCount;
  final _roomsCountController = TextEditingController();
  final _familiesCountController = TextEditingController();
  double? _gpsLat;
  double? _gpsLng;
  bool _gpsLoading = false;

  // "My Engagement" spec — Educational/Employment, Personal and Health,
  // Assets, Needs and Requirements, Attachments, Social Media Accounts.
  String? _educationLevel;
  final _otherCertificateController = TextEditingController();
  final _certificatesCountController = TextEditingController();
  final _occupationController = TextEditingController();
  final _previousOccupationController = TextEditingController();
  final _jobDescriptionController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _monthlyIncomeController = TextEditingController();
  String? _skinTone;
  final _familyMembersController = TextEditingController();
  final _childrenCountController = TextEditingController();
  String? _smokingStatus;
  String? _eyesightCondition;
  String? _hasDisability; // yes | no
  final _disabilityTypeController = TextEditingController();
  final _chronicIllnessesController = TextEditingController();
  final _ethnicityController = TextEditingController();
  final _skillsController = TextEditingController();
  String? _ownsCar;
  String? _ownsHouse;
  String? _ownsShop;
  String? _ownsCompany;
  String? _ownsLand;
  final _otherAssetsController = TextEditingController();
  final _partnerRequirementsController = TextEditingController();
  // Attachments — uploaded via the same /api/uploads flow as the photo.
  String? _goldenSquareUrl;
  String? _graduationCertUrl;
  String? _cvUrl;
  String? _uploadingAttachment; // rule key currently uploading
  final _socialFacebookController = TextEditingController();
  final _socialInstagramController = TextEditingController();
  final _socialTelegramController = TextEditingController();
  final _socialOtherController = TextEditingController();
  String _visibility =
      'employee_only'; // private | employee_only | matched_summary
  bool _busy = false;
  Set<String> _required = {};
  Set<String> _hidden = {};

  // Marriage Posts — an optional photo shown on the profile's feed card.
  String? _photoUrl;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    fetchFieldRuleSets().then((rules) {
      if (!mounted) return;
      setState(() {
        _required = rules.required
            .where((k) => k.startsWith(_fieldRulePrefix))
            .map((k) => k.substring(_fieldRulePrefix.length))
            .toSet();
        _hidden = rules.hidden
            .where((k) => k.startsWith(_fieldRulePrefix))
            .map((k) => k.substring(_fieldRulePrefix.length))
            .toSet();
      });
    });
  }

  @override
  void dispose() {
    for (final c in [
      _ageController,
      _cityController,
      _summaryController,
      _notesController,
      _religionController,
      _weightController,
      _heightController,
      _nationalIdController,
      _nameFirstController,
      _nameFatherController,
      _nameGrandfatherController,
      _nameFamilyController,
      _tribeClanController,
      _titleSurnameController,
      _emailController,
      _phone1Controller,
      _phone2Controller,
      _neighborhoodController,
      _nearestLandmarkController,
      _yearsCurrentController,
      _previousResidenceController,
      _yearsPreviousController,
      _rentalAmountController,
      _housingAreaController,
      _roomsCountController,
      _familiesCountController,
      _otherCertificateController,
      _certificatesCountController,
      _occupationController,
      _previousOccupationController,
      _jobDescriptionController,
      _workingHoursController,
      _monthlyIncomeController,
      _familyMembersController,
      _childrenCountController,
      _disabilityTypeController,
      _chronicIllnessesController,
      _ethnicityController,
      _skillsController,
      _otherAssetsController,
      _partnerRequirementsController,
      _socialFacebookController,
      _socialInstagramController,
      _socialTelegramController,
      _socialOtherController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Captures the device's current position for the "Geographic location —
  /// GPS" field. Mirrors the registration form's capture flow.
  Future<void> _captureGpsLocation() async {
    setState(() => _gpsLoading = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Get.snackbar('Error'.tr, 'location_permission_required'.tr);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        Get.snackbar('Error'.tr, 'location_services_disabled'.tr);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _gpsLat = position.latitude;
        _gpsLng = position.longitude;
      });
    } catch (e) {
      Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  /// The date-of-birth dropdowns as "YYYY-MM-DD", or "" when incomplete.
  /// The day is clamped to the chosen month's length so an impossible date
  /// (e.g. 31 February) can never be submitted.
  String _dobIso() {
    final y = _dobYear, m = _dobMonth, d = _dobDay;
    if (y == null || m == null || d == null) return '';
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = d > lastDay ? lastDay : d;
    return '${y.toString().padLeft(4, '0')}-'
        '${m.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  // Note #33 — returns the label key of the first admin-required-but-empty
  // field, or null. Hidden fields are skipped (a hidden field can't be
  // required — the admin isn't shown the checkbox for it either).
  String? _firstMissingRequired() {
    bool blank(String v) => v.trim().isEmpty;
    final checks = <String, bool>{
      'gender': _gender != null,
      'age': !blank(_ageController.text),
      'city': !blank(_cityController.text),
      'social_summary': !blank(_summaryController.text),
      'private_notes': !blank(_notesController.text),
      'marital_status': _maritalStatus != null,
      'religion': !blank(_religionController.text),
      'employment_status': _employmentStatus != null,
      'weight': !blank(_weightController.text),
      'height': !blank(_heightController.text),
      // "Identification Information" section.
      'national_id': !blank(_nationalIdController.text),
      'name_parts':
          !blank(_nameFirstController.text) &&
          !blank(_nameFatherController.text) &&
          !blank(_nameGrandfatherController.text) &&
          !blank(_nameFamilyController.text),
      'tribe_clan': !blank(_tribeClanController.text),
      'title_surname': !blank(_titleSurnameController.text),
      'date_of_birth': _dobDay != null && _dobMonth != null && _dobYear != null,
      'email': !blank(_emailController.text),
      'phone1': !blank(_phone1Controller.text),
      'phone2': !blank(_phone2Controller.text),
      // "Personal Information" section.
      'nationality': _nationality != null,
      'residency_status': _residencyStatus != null,
      // "Housing Information" / "Housing Type" sections.
      'governorate': _governorate != null,
      'housing_side': _housingSide != null,
      'neighborhood': _governorate == 'Nineveh'
          ? _neighborhoodDropdown != null
          : !blank(_neighborhoodController.text),
      'nearest_landmark': !blank(_nearestLandmarkController.text),
      'gps_location': _gpsLat != null,
      'years_current_residence': !blank(_yearsCurrentController.text),
      'previous_residence': !blank(_previousResidenceController.text),
      'years_previous_residence': !blank(_yearsPreviousController.text),
      'housing_type': _housingType != null,
      'rental_amount': !blank(_rentalAmountController.text),
      'housing_area': !blank(_housingAreaController.text),
      'floors_count': _floorsCount != null,
      'rooms_count': !blank(_roomsCountController.text),
      'families_count': !blank(_familiesCountController.text),
      // Educational/Employment, Personal and Health, Assets, Needs,
      // Attachments and Social Media sections.
      'education_level': _educationLevel != null,
      'other_certificate': !blank(_otherCertificateController.text),
      'certificates_count': !blank(_certificatesCountController.text),
      'occupation': !blank(_occupationController.text),
      'previous_occupation': !blank(_previousOccupationController.text),
      'job_description': !blank(_jobDescriptionController.text),
      'working_hours': !blank(_workingHoursController.text),
      'monthly_income': !blank(_monthlyIncomeController.text),
      'skin_tone': _skinTone != null,
      'family_members': !blank(_familyMembersController.text),
      'children_count': !blank(_childrenCountController.text),
      'smoking_status': _smokingStatus != null,
      'eyesight_condition': _eyesightCondition != null,
      'has_disability': _hasDisability != null,
      'disability_type': !blank(_disabilityTypeController.text),
      'chronic_illnesses': !blank(_chronicIllnessesController.text),
      'ethnicity': !blank(_ethnicityController.text),
      'skills': !blank(_skillsController.text),
      'owns_car': _ownsCar != null,
      'owns_house': _ownsHouse != null,
      'owns_shop': _ownsShop != null,
      'owns_company': _ownsCompany != null,
      'owns_land': _ownsLand != null,
      'other_assets': !blank(_otherAssetsController.text),
      'partner_requirements': !blank(_partnerRequirementsController.text),
      'personal_photo': _photoUrl != null && _photoUrl!.isNotEmpty,
      'golden_square': _goldenSquareUrl != null,
      'graduation_cert': _graduationCertUrl != null,
      'cv': _cvUrl != null,
      'social_facebook': !blank(_socialFacebookController.text),
      'social_instagram': !blank(_socialInstagramController.text),
      'social_telegram': !blank(_socialTelegramController.text),
      'social_other': !blank(_socialOtherController.text),
    };
    const labelKeys = <String, String>{
      'gender': 'marriage_gender',
      'age': 'marriage_age',
      'city': 'marriage_city',
      'social_summary': 'marriage_summary',
      'private_notes': 'marriage_private_notes',
      'marital_status': 'marriage_marital_status',
      'religion': 'marriage_religion',
      'employment_status': 'marriage_employment_status',
      'weight': 'marriage_weight',
      'height': 'marriage_height',
      'national_id': 'marriage_national_id',
      'name_parts': 'marriage_name_parts',
      'tribe_clan': 'marriage_tribe_clan',
      'title_surname': 'marriage_title_surname',
      'date_of_birth': 'marriage_date_of_birth',
      'email': 'marriage_email',
      'phone1': 'marriage_phone1',
      'phone2': 'marriage_phone2',
      'nationality': 'marriage_nationality',
      'residency_status': 'marriage_residency_status',
      'governorate': 'reg_grantor_governorate',
      'housing_side': 'reg_recipient_housing_side',
      'neighborhood': 'reg_recipient_neighborhood',
      'nearest_landmark': 'reg_recipient_nearest_landmark',
      'gps_location': 'reg_grantor_gps_location',
      'years_current_residence': 'marriage_years_current_residence',
      'previous_residence': 'marriage_previous_residence',
      'years_previous_residence': 'marriage_years_previous_residence',
      'housing_type': 'reg_recipient_housing_type',
      'rental_amount': 'reg_recipient_rental_amount',
      'housing_area': 'reg_recipient_housing_area',
      'floors_count': 'reg_recipient_floors_count',
      'rooms_count': 'reg_recipient_rooms_count',
      'families_count': 'reg_recipient_families_count',
      'education_level': 'reg_grantor_education_level',
      'other_certificate': 'reg_recipient_other_certificate',
      'certificates_count': 'reg_recipient_certificates_count',
      'occupation': 'reg_occupation',
      'previous_occupation': 'reg_recipient_previous_occupation',
      'job_description': 'reg_recipient_job_description',
      'working_hours': 'reg_recipient_working_hours',
      'monthly_income': 'reg_income',
      'skin_tone': 'marriage_skin_tone',
      'family_members': 'reg_family_size',
      'children_count': 'marriage_children_count',
      'smoking_status': 'reg_recipient_smoking_status',
      'eyesight_condition': 'reg_recipient_eyesight_condition',
      'has_disability': 'reg_recipient_has_disability',
      'disability_type': 'reg_recipient_disability_type',
      'chronic_illnesses': 'reg_recipient_chronic_illnesses',
      'ethnicity': 'marriage_ethnicity',
      'skills': 'reg_skills',
      'owns_car': 'marriage_owns_car',
      'owns_house': 'marriage_owns_house',
      'owns_shop': 'marriage_owns_shop',
      'owns_company': 'marriage_owns_company',
      'owns_land': 'marriage_owns_land',
      'other_assets': 'marriage_other_assets',
      'partner_requirements': 'marriage_partner_requirements',
      'personal_photo': 'marriage_photo',
      'golden_square': 'marriage_golden_square',
      'graduation_cert': 'marriage_graduation_cert',
      'cv': 'marriage_cv',
      'social_facebook': 'reg_recipient_social_facebook',
      'social_instagram': 'reg_recipient_social_instagram',
      'social_telegram': 'reg_recipient_social_telegram',
      'social_other': 'marriage_social_other',
    };
    for (final key in _required) {
      if (_hidden.contains(key)) continue;
      final filled = checks[key];
      if (filled == false) return labelKeys[key];
    }
    return null;
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final path = await const ModuleApi().uploadPhoto(File(picked.path));
      if (mounted) setState(() => _photoUrl = path);
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// Uploads one attachment via the same /api/uploads flow as the profile
  /// photo and hands the returned path to [assign]. [ruleKey] drives the
  /// per-tile spinner so two uploads can't be confused for each other.
  Future<void> _pickAttachment(
    String ruleKey,
    void Function(String url) assign,
  ) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingAttachment = ruleKey);
    try {
      final path = await const ModuleApi().uploadPhoto(File(picked.path));
      if (mounted) setState(() => assign(path));
    } catch (e) {
      if (mounted) Get.snackbar('Error'.tr, e.toString());
    } finally {
      if (mounted) setState(() => _uploadingAttachment = null);
    }
  }

  /// One attachment row: label + upload button showing its current state.
  Widget _attachmentTile(
    String ruleKey,
    String labelKey,
    String? url,
    void Function(String) assign,
  ) {
    final busy = _uploadingAttachment == ruleKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(labelKey),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _pickAttachment(ruleKey, assign),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    url == null || url.isEmpty
                        ? Icons.upload_file_outlined
                        : Icons.check_circle_outline,
                  ),
            label: Text(
              (url == null || url.isEmpty)
                  ? 'marriage_attachment_upload'.tr
                  : 'marriage_attachment_uploaded'.tr,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final missing = _firstMissingRequired();
    if (missing != null) {
      Get.snackbar(
        'marriage_title'.tr,
        '${missing.tr}: ${'reg_required_missing'.tr}',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = int.tryParse(sharedPreferences.getString('id_user') ?? '');
      await const ModuleApi().submitMarriage({
        'user_id': uid,
        'gender': _hidden.contains('gender') ? '' : (_gender ?? ''),
        'age': _hidden.contains('age')
            ? 0
            : (int.tryParse(_ageController.text.trim()) ?? 0),
        'city': _hidden.contains('city') ? '' : _cityController.text.trim(),
        'social_summary': _hidden.contains('social_summary')
            ? ''
            : _summaryController.text.trim(),
        'private_notes': _hidden.contains('private_notes')
            ? ''
            : _notesController.text.trim(),
        'marital_status': _hidden.contains('marital_status')
            ? ''
            : (_maritalStatus ?? ''),
        'religion': _hidden.contains('religion')
            ? ''
            : _religionController.text.trim(),
        'employment_status': _hidden.contains('employment_status')
            ? ''
            : (_employmentStatus ?? ''),
        'weight_kg': _hidden.contains('weight')
            ? 0
            : (int.tryParse(_weightController.text.trim()) ?? 0),
        'height_cm': _hidden.contains('height')
            ? 0
            : (int.tryParse(_heightController.text.trim()) ?? 0),
        'visibility_level': _visibility,
        'photo_url': _photoUrl ?? '',
        // "Identification Information" — hidden fields submit empty, same
        // convention as the fields above.
        'national_id': _hidden.contains('national_id')
            ? ''
            : _nationalIdController.text.trim(),
        'name_first': _hidden.contains('name_parts')
            ? ''
            : _nameFirstController.text.trim(),
        'name_father': _hidden.contains('name_parts')
            ? ''
            : _nameFatherController.text.trim(),
        'name_grandfather': _hidden.contains('name_parts')
            ? ''
            : _nameGrandfatherController.text.trim(),
        'name_family': _hidden.contains('name_parts')
            ? ''
            : _nameFamilyController.text.trim(),
        'tribe_clan': _hidden.contains('tribe_clan')
            ? ''
            : _tribeClanController.text.trim(),
        'title_surname': _hidden.contains('title_surname')
            ? ''
            : _titleSurnameController.text.trim(),
        'date_of_birth': _hidden.contains('date_of_birth') ? '' : _dobIso(),
        'email': _hidden.contains('email') ? '' : _emailController.text.trim(),
        'phone1': _hidden.contains('phone1')
            ? ''
            : _phone1Controller.text.trim(),
        'phone2': _hidden.contains('phone2')
            ? ''
            : _phone2Controller.text.trim(),
        'nationality': _hidden.contains('nationality')
            ? ''
            : (_nationality ?? ''),
        'residency_status': _hidden.contains('residency_status')
            ? ''
            : (_residencyStatus ?? ''),
        // "Housing Information" / "Housing Type".
        'governorate': _hidden.contains('governorate')
            ? ''
            : (_governorate ?? ''),
        'housing_side': _hidden.contains('housing_side')
            ? ''
            : (_housingSide ?? ''),
        'neighborhood': _hidden.contains('neighborhood')
            ? ''
            : (_governorate == 'Nineveh'
                  ? (_neighborhoodDropdown ?? '')
                  : _neighborhoodController.text.trim()),
        'nearest_landmark': _hidden.contains('nearest_landmark')
            ? ''
            : _nearestLandmarkController.text.trim(),
        if (!_hidden.contains('gps_location') && _gpsLat != null)
          'gps_lat': _gpsLat,
        if (!_hidden.contains('gps_location') && _gpsLng != null)
          'gps_lng': _gpsLng,
        'years_current_residence': _hidden.contains('years_current_residence')
            ? ''
            : _yearsCurrentController.text.trim(),
        'previous_residence': _hidden.contains('previous_residence')
            ? ''
            : _previousResidenceController.text.trim(),
        'years_previous_residence': _hidden.contains('years_previous_residence')
            ? ''
            : _yearsPreviousController.text.trim(),
        'housing_type': _hidden.contains('housing_type')
            ? ''
            : (_housingType ?? ''),
        // Rental amount only applies when the housing type is Rented.
        'rental_amount':
            (_hidden.contains('rental_amount') || _housingType != 'rented')
            ? ''
            : _rentalAmountController.text.trim(),
        'housing_area': _hidden.contains('housing_area')
            ? ''
            : _housingAreaController.text.trim(),
        'floors_count': _hidden.contains('floors_count')
            ? ''
            : (_floorsCount ?? ''),
        'rooms_count': _hidden.contains('rooms_count')
            ? ''
            : _roomsCountController.text.trim(),
        'families_count': _hidden.contains('families_count')
            ? ''
            : _familiesCountController.text.trim(),
        // Educational/Employment, Personal and Health, Assets, Needs,
        // Attachments and Social Media sections.
        'education_level': _hidden.contains('education_level')
            ? ''
            : (_educationLevel ?? ''),
        'other_certificate': _hidden.contains('other_certificate')
            ? ''
            : _otherCertificateController.text.trim(),
        'certificates_count': _hidden.contains('certificates_count')
            ? ''
            : _certificatesCountController.text.trim(),
        'occupation': _hidden.contains('occupation')
            ? ''
            : _occupationController.text.trim(),
        'previous_occupation': _hidden.contains('previous_occupation')
            ? ''
            : _previousOccupationController.text.trim(),
        'job_description': _hidden.contains('job_description')
            ? ''
            : _jobDescriptionController.text.trim(),
        'working_hours': _hidden.contains('working_hours')
            ? ''
            : _workingHoursController.text.trim(),
        'monthly_income': _hidden.contains('monthly_income')
            ? ''
            : _monthlyIncomeController.text.trim(),
        'skin_tone': _hidden.contains('skin_tone') ? '' : (_skinTone ?? ''),
        'family_members_count': _hidden.contains('family_members')
            ? ''
            : _familyMembersController.text.trim(),
        'children_count': _hidden.contains('children_count')
            ? ''
            : _childrenCountController.text.trim(),
        'smoking_status': _hidden.contains('smoking_status')
            ? ''
            : (_smokingStatus ?? ''),
        'eyesight_condition': _hidden.contains('eyesight_condition')
            ? ''
            : (_eyesightCondition ?? ''),
        'has_disability': _hidden.contains('has_disability')
            ? ''
            : (_hasDisability ?? ''),
        // Type of disability only applies when there is one.
        'disability_type':
            (_hidden.contains('disability_type') || _hasDisability != 'yes')
            ? ''
            : _disabilityTypeController.text.trim(),
        'chronic_illnesses': _hidden.contains('chronic_illnesses')
            ? ''
            : _chronicIllnessesController.text.trim(),
        'ethnicity': _hidden.contains('ethnicity')
            ? ''
            : _ethnicityController.text.trim(),
        'skills': _hidden.contains('skills')
            ? ''
            : _skillsController.text.trim(),
        'owns_car': _hidden.contains('owns_car') ? '' : (_ownsCar ?? ''),
        'owns_house': _hidden.contains('owns_house') ? '' : (_ownsHouse ?? ''),
        'owns_shop': _hidden.contains('owns_shop') ? '' : (_ownsShop ?? ''),
        'owns_company': _hidden.contains('owns_company')
            ? ''
            : (_ownsCompany ?? ''),
        'owns_land': _hidden.contains('owns_land') ? '' : (_ownsLand ?? ''),
        'other_assets': _hidden.contains('other_assets')
            ? ''
            : _otherAssetsController.text.trim(),
        'partner_requirements': _hidden.contains('partner_requirements')
            ? ''
            : _partnerRequirementsController.text.trim(),
        'golden_square_url': _hidden.contains('golden_square')
            ? ''
            : (_goldenSquareUrl ?? ''),
        'graduation_cert_url': _hidden.contains('graduation_cert')
            ? ''
            : (_graduationCertUrl ?? ''),
        'cv_url': _hidden.contains('cv') ? '' : (_cvUrl ?? ''),
        'social_facebook': _hidden.contains('social_facebook')
            ? ''
            : _socialFacebookController.text.trim(),
        'social_instagram': _hidden.contains('social_instagram')
            ? ''
            : _socialInstagramController.text.trim(),
        'social_telegram': _hidden.contains('social_telegram')
            ? ''
            : _socialTelegramController.text.trim(),
        'social_other': _hidden.contains('social_other')
            ? ''
            : _socialOtherController.text.trim(),
      });
      if (!mounted) return;
      // Note #18 — was Get.back() (just returns to Profile with a toast, no
      // way to check status afterward). Now replaces this screen with the
      // status screen so the user immediately sees "Submitted" and can come
      // back to check it later without re-finding this tile.
      Get.off(() => const MarriageMyProfileScreen());
      Get.snackbar('marriage_title'.tr, 'marriage_submitted'.tr);
    } catch (_) {
      if (mounted) {
        Get.snackbar('marriage_title'.tr, 'marriage_submit_failed'.tr);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_title'.tr,
      subtitle: 'marriage_subtitle'.tr,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          if (!_hidden.contains('personal_photo')) ...[
            _label('marriage_photo'),
            Center(
              child: GestureDetector(
                onTap: _uploadingPhoto ? null : _pickPhoto,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppThemeConfig.softSurface(context),
                      backgroundImage:
                          (_photoUrl != null && _photoUrl!.isNotEmpty)
                          ? NetworkImage(_resolvePhotoUrl(_photoUrl!))
                          : null,
                      child: (_photoUrl == null || _photoUrl!.isEmpty)
                          ? Icon(
                              Icons.add_a_photo_outlined,
                              size: 28,
                              color: AppThemeConfig.mutedText(context),
                            )
                          : null,
                    ),
                    if (_uploadingPhoto)
                      const CircularProgressIndicator(strokeWidth: 2),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // "My Engagement" spec — "Identification Information".
          _label('marriage_identification_section'),
          _label('marriage_profile_code'),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'marriage_profile_code_auto'.tr,
              style: TextStyle(
                fontSize: 12.5,
                color: AppThemeConfig.mutedText(context),
              ),
            ),
          ),
          if (!_hidden.contains('national_id'))
            _text(
              _nationalIdController,
              'marriage_national_id',
              Icons.badge_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('name_parts')) ...[
            _label('marriage_name_parts'),
            _text(
              _nameFirstController,
              'reg_grantor_name_first_hint',
              Icons.person_outline,
            ),
            _text(
              _nameFatherController,
              'reg_grantor_name_father_hint',
              Icons.person_outline,
            ),
            _text(
              _nameGrandfatherController,
              'reg_grantor_name_grandfather_hint',
              Icons.person_outline,
            ),
            _text(
              _nameFamilyController,
              'reg_grantor_name_family_hint',
              Icons.person_outline,
            ),
          ],
          if (!_hidden.contains('tribe_clan'))
            _text(
              _tribeClanController,
              'marriage_tribe_clan',
              Icons.groups_outlined,
            ),
          if (!_hidden.contains('title_surname'))
            _text(
              _titleSurnameController,
              'marriage_title_surname',
              Icons.title_outlined,
            ),
          if (!_hidden.contains('date_of_birth')) ...[
            _label('marriage_date_of_birth'),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _dobDay,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 16,
                        ),
                      ),
                      hint: Text('reg_dob_day'.tr),
                      items: [
                        for (var d = 1; d <= 31; d++)
                          DropdownMenuItem(value: d, child: Text('$d')),
                      ],
                      onChanged: (v) => setState(() => _dobDay = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _dobMonth,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 16,
                        ),
                      ),
                      hint: Text('reg_dob_month'.tr),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(value: m, child: Text('$m')),
                      ],
                      onChanged: (v) => setState(() => _dobMonth = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _dobYear,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 16,
                        ),
                      ),
                      hint: Text('reg_dob_year'.tr),
                      items: [
                        for (var y = DateTime.now().year; y >= 1900; y--)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setState(() => _dobYear = v),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_hidden.contains('email'))
            _text(
              _emailController,
              'marriage_email',
              Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
            ),
          if (!_hidden.contains('phone1'))
            _text(
              _phone1Controller,
              'marriage_phone1',
              Icons.phone_outlined,
              keyboard: TextInputType.phone,
            ),
          if (!_hidden.contains('phone2'))
            _text(
              _phone2Controller,
              'marriage_phone2',
              Icons.phone_android_outlined,
              keyboard: TextInputType.phone,
            ),
          const SizedBox(height: 8),
          // "My Engagement" spec — "Personal Information". Gender and marital
          // status already exist further down and are not repeated here.
          _label('marriage_personal_section'),
          if (!_hidden.contains('nationality')) ...[
            _label('marriage_nationality'),
            DropdownButtonFormField<String>(
              initialValue: _nationality,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              hint: Text('marriage_nationality_hint'.tr),
              items: [
                for (final n in const [
                  'iraqi',
                  'syrian',
                  'egyptian',
                  'gulf',
                  'other',
                ])
                  DropdownMenuItem(value: n, child: Text('nationality_$n'.tr)),
              ],
              onChanged: (v) => setState(() => _nationality = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('residency_status')) ...[
            _label('marriage_residency_status'),
            DropdownButtonFormField<String>(
              initialValue: _residencyStatus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.assignment_ind_outlined),
              ),
              hint: Text('marriage_residency_status_hint'.tr),
              items: [
                for (final r in const [
                  'local',
                  'returnee',
                  'displaced',
                  'refugee',
                  'other',
                ])
                  DropdownMenuItem(value: r, child: Text('residency_$r'.tr)),
              ],
              onChanged: (v) => setState(() => _residencyStatus = v),
            ),
            const SizedBox(height: 14),
          ],
          // "My Engagement" spec — "Housing Information" / "Housing Type".
          _label('marriage_housing_section'),
          if (!_hidden.contains('governorate')) ...[
            _label('reg_grantor_governorate'),
            DropdownButtonFormField<String>(
              initialValue: _governorate,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.map_outlined),
              ),
              hint: Text('reg_grantor_governorate_hint'.tr),
              items: [
                for (final g in iraqGovernorates)
                  DropdownMenuItem(value: g, child: Text(g.tr)),
              ],
              onChanged: (v) => setState(() {
                _governorate = v;
                // Switching governorate invalidates the Nineveh-only
                // side/neighborhood selection.
                _housingSide = null;
                _neighborhoodDropdown = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          if (_governorate == 'Nineveh') ...[
            if (!_hidden.contains('housing_side')) ...[
              _label('reg_recipient_housing_side'),
              DropdownButtonFormField<String>(
                initialValue: _housingSide,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.swap_horiz_rounded),
                ),
                hint: Text('reg_recipient_housing_side_hint'.tr),
                items: [
                  for (final sd in const ['right', 'left', 'other'])
                    DropdownMenuItem(
                      value: sd,
                      child: Text('housing_side_$sd'.tr),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _housingSide = v;
                  _neighborhoodDropdown = null;
                }),
              ),
              const SizedBox(height: 14),
            ],
            if (!_hidden.contains('neighborhood')) ...[
              _label('reg_recipient_neighborhood'),
              DropdownButtonFormField<String>(
                initialValue: _neighborhoodDropdown,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                hint: Text('reg_recipient_neighborhood_hint'.tr),
                items: [
                  for (final n
                      in _housingSide == 'left'
                          ? ninevehLeftSideNeighborhoods
                          : ninevehRightSideNeighborhoods)
                    DropdownMenuItem(value: n, child: Text(n)),
                ],
                onChanged: (v) => setState(() => _neighborhoodDropdown = v),
              ),
              const SizedBox(height: 14),
            ],
          ] else if (!_hidden.contains('neighborhood'))
            _text(
              _neighborhoodController,
              'reg_recipient_neighborhood',
              Icons.location_city_outlined,
            ),
          if (!_hidden.contains('nearest_landmark'))
            _text(
              _nearestLandmarkController,
              'reg_recipient_nearest_landmark',
              Icons.place_outlined,
            ),
          if (!_hidden.contains('gps_location')) ...[
            _label('reg_grantor_gps_location'),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OutlinedButton.icon(
                onPressed: _gpsLoading ? null : _captureGpsLocation,
                icon: _gpsLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  _gpsLat == null
                      ? 'reg_grantor_gps_capture'.tr
                      : '${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)}',
                ),
              ),
            ),
          ],
          if (!_hidden.contains('years_current_residence'))
            _text(
              _yearsCurrentController,
              'marriage_years_current_residence',
              Icons.timelapse_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('previous_residence'))
            _text(
              _previousResidenceController,
              'marriage_previous_residence',
              Icons.history_outlined,
            ),
          if (!_hidden.contains('years_previous_residence'))
            _text(
              _yearsPreviousController,
              'marriage_years_previous_residence',
              Icons.timelapse_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('housing_type')) ...[
            _label('reg_recipient_housing_type'),
            DropdownButtonFormField<String>(
              initialValue: _housingType,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.house_outlined),
              ),
              hint: Text('reg_recipient_housing_type_hint'.tr),
              items: [
                // Spec lists: owned, rented, shared, inherited, other.
                for (final h in const [
                  'owned',
                  'rented',
                  'shared',
                  'inherited',
                  'other',
                ])
                  DropdownMenuItem(value: h, child: Text('housing_type_$h'.tr)),
              ],
              onChanged: (v) => setState(() => _housingType = v),
            ),
            const SizedBox(height: 14),
          ],
          if (_housingType == 'rented' && !_hidden.contains('rental_amount'))
            _text(
              _rentalAmountController,
              'reg_recipient_rental_amount',
              Icons.payments_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('housing_area'))
            _text(
              _housingAreaController,
              'reg_recipient_housing_area',
              Icons.square_foot_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('floors_count')) ...[
            _label('reg_recipient_floors_count'),
            DropdownButtonFormField<String>(
              initialValue: _floorsCount,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.stairs_outlined),
              ),
              hint: Text('reg_recipient_floors_count_hint'.tr),
              items: [
                for (final f in const ['one', 'one_half', 'two', 'three_plus'])
                  DropdownMenuItem(value: f, child: Text('floors_$f'.tr)),
              ],
              onChanged: (v) => setState(() => _floorsCount = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('rooms_count'))
            _text(
              _roomsCountController,
              'reg_recipient_rooms_count',
              Icons.door_front_door_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('families_count'))
            _text(
              _familiesCountController,
              'reg_recipient_families_count',
              Icons.groups_2_outlined,
              keyboard: TextInputType.number,
            ),
          // "My Engagement" spec — "Educational and Employment Information".
          _label('marriage_education_section'),
          if (!_hidden.contains('education_level')) ...[
            _label('reg_grantor_education_level'),
            DropdownButtonFormField<String>(
              initialValue: _educationLevel,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.school_outlined),
              ),
              hint: Text('reg_grantor_education_level_hint'.tr),
              items: [
                for (final o in const [
                  'none',
                  'primary',
                  'secondary',
                  'diploma',
                  'bachelor',
                  'master',
                  'phd',
                ])
                  DropdownMenuItem(value: o, child: Text('education_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _educationLevel = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('other_certificate'))
            _text(
              _otherCertificateController,
              'reg_recipient_other_certificate',
              Icons.workspace_premium_outlined,
            ),
          if (!_hidden.contains('certificates_count'))
            _text(
              _certificatesCountController,
              'reg_recipient_certificates_count',
              Icons.numbers_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('occupation'))
            _text(_occupationController, 'reg_occupation', Icons.work_outline),
          if (!_hidden.contains('previous_occupation'))
            _text(
              _previousOccupationController,
              'reg_recipient_previous_occupation',
              Icons.history_outlined,
            ),
          if (!_hidden.contains('job_description'))
            _text(
              _jobDescriptionController,
              'reg_recipient_job_description',
              Icons.description_outlined,
              lines: 3,
            ),
          if (!_hidden.contains('working_hours'))
            _text(
              _workingHoursController,
              'reg_recipient_working_hours',
              Icons.schedule_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('monthly_income'))
            _text(
              _monthlyIncomeController,
              'reg_income',
              Icons.payments_outlined,
            ),
          // "Personal and Health Information". Height, weight and religion
          // already exist further down and are not repeated here.
          _label('marriage_health_section'),
          if (!_hidden.contains('skin_tone')) ...[
            _label('marriage_skin_tone'),
            DropdownButtonFormField<String>(
              initialValue: _skinTone,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.palette_outlined),
              ),
              hint: Text('marriage_skin_tone_hint'.tr),
              items: [
                for (final o in const [
                  'fair',
                  'medium',
                  'olive',
                  'brown',
                  'dark',
                ])
                  DropdownMenuItem(value: o, child: Text('skin_tone_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _skinTone = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('family_members'))
            _text(
              _familyMembersController,
              'reg_family_size',
              Icons.group_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('children_count'))
            _text(
              _childrenCountController,
              'marriage_children_count',
              Icons.child_care_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('smoking_status')) ...[
            _label('reg_recipient_smoking_status'),
            DropdownButtonFormField<String>(
              initialValue: _smokingStatus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.smoking_rooms_outlined),
              ),
              hint: Text('reg_recipient_smoking_status_hint'.tr),
              items: [
                for (final o in const ['non_smoker', 'smoker', 'former'])
                  DropdownMenuItem(value: o, child: Text('smoking_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _smokingStatus = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('eyesight_condition')) ...[
            _label('reg_recipient_eyesight_condition'),
            DropdownButtonFormField<String>(
              initialValue: _eyesightCondition,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.visibility_outlined),
              ),
              hint: Text('reg_recipient_eyesight_condition_hint'.tr),
              items: [
                for (final o in const ['normal', 'glasses', 'weak', 'blind'])
                  DropdownMenuItem(value: o, child: Text('eyesight_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _eyesightCondition = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('has_disability')) ...[
            _label('reg_recipient_has_disability'),
            DropdownButtonFormField<String>(
              initialValue: _hasDisability,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.accessible_outlined),
              ),
              hint: Text('reg_recipient_has_disability_hint'.tr),
              items: [
                for (final o in const ['yes', 'no'])
                  DropdownMenuItem(value: o, child: Text('yesno_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _hasDisability = v),
            ),
            const SizedBox(height: 14),
          ],
          if (_hasDisability == 'yes' && !_hidden.contains('disability_type'))
            _text(
              _disabilityTypeController,
              'reg_recipient_disability_type',
              Icons.info_outline,
            ),
          if (!_hidden.contains('chronic_illnesses'))
            _text(
              _chronicIllnessesController,
              'reg_recipient_chronic_illnesses',
              Icons.medical_information_outlined,
              lines: 2,
            ),
          if (!_hidden.contains('ethnicity'))
            _text(
              _ethnicityController,
              'marriage_ethnicity',
              Icons.public_outlined,
            ),
          if (!_hidden.contains('skills'))
            _text(
              _skillsController,
              'reg_skills',
              Icons.star_outline,
              lines: 3,
            ),
          // "Assets".
          _label('marriage_assets_section'),
          if (!_hidden.contains('owns_car')) ...[
            _label('marriage_owns_car'),
            DropdownButtonFormField<String>(
              initialValue: _ownsCar,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
              hint: Text('reg_recipient_owns_car_hint'.tr),
              items: [
                for (final o in const ['yes', 'no'])
                  DropdownMenuItem(value: o, child: Text('yesno_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _ownsCar = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('owns_house')) ...[
            _label('marriage_owns_house'),
            DropdownButtonFormField<String>(
              initialValue: _ownsHouse,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
              hint: Text('reg_recipient_owns_car_hint'.tr),
              items: [
                for (final o in const ['yes', 'no'])
                  DropdownMenuItem(value: o, child: Text('yesno_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _ownsHouse = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('owns_shop')) ...[
            _label('marriage_owns_shop'),
            DropdownButtonFormField<String>(
              initialValue: _ownsShop,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
              hint: Text('reg_recipient_owns_car_hint'.tr),
              items: [
                for (final o in const ['yes', 'no'])
                  DropdownMenuItem(value: o, child: Text('yesno_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _ownsShop = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('owns_company')) ...[
            _label('marriage_owns_company'),
            DropdownButtonFormField<String>(
              initialValue: _ownsCompany,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
              hint: Text('reg_recipient_owns_car_hint'.tr),
              items: [
                for (final o in const ['yes', 'no'])
                  DropdownMenuItem(value: o, child: Text('yesno_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _ownsCompany = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('owns_land')) ...[
            _label('marriage_owns_land'),
            DropdownButtonFormField<String>(
              initialValue: _ownsLand,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
              hint: Text('reg_recipient_owns_car_hint'.tr),
              items: [
                for (final o in const ['yes', 'no'])
                  DropdownMenuItem(value: o, child: Text('yesno_$o'.tr)),
              ],
              onChanged: (v) => setState(() => _ownsLand = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('other_assets'))
            _text(
              _otherAssetsController,
              'marriage_other_assets',
              Icons.chair_alt_outlined,
              lines: 2,
            ),
          // "Needs and Requirements".
          _label('marriage_needs_section'),
          if (!_hidden.contains('partner_requirements'))
            _text(
              _partnerRequirementsController,
              'marriage_partner_requirements',
              Icons.favorite_outline,
              lines: 4,
            ),
          // "Attachments". The personal photo is the picker at the top of
          // this form and is not repeated here.
          _label('marriage_attachments_section'),
          if (!_hidden.contains('golden_square'))
            _attachmentTile(
              'golden_square',
              'marriage_golden_square',
              _goldenSquareUrl,
              (u) => _goldenSquareUrl = u,
            ),
          if (!_hidden.contains('graduation_cert'))
            _attachmentTile(
              'graduation_cert',
              'marriage_graduation_cert',
              _graduationCertUrl,
              (u) => _graduationCertUrl = u,
            ),
          if (!_hidden.contains('cv'))
            _attachmentTile('cv', 'marriage_cv', _cvUrl, (u) => _cvUrl = u),
          // "Social Media Accounts".
          _label('marriage_social_accounts_section'),
          if (!_hidden.contains('social_facebook'))
            _text(
              _socialFacebookController,
              'reg_recipient_social_facebook',
              Icons.facebook_outlined,
              keyboard: TextInputType.url,
            ),
          if (!_hidden.contains('social_instagram'))
            _text(
              _socialInstagramController,
              'reg_recipient_social_instagram',
              Icons.camera_alt_outlined,
              keyboard: TextInputType.url,
            ),
          if (!_hidden.contains('social_telegram'))
            _text(
              _socialTelegramController,
              'reg_recipient_social_telegram',
              Icons.send_outlined,
              keyboard: TextInputType.url,
            ),
          if (!_hidden.contains('social_other'))
            _text(
              _socialOtherController,
              'marriage_social_other',
              Icons.link_outlined,
              keyboard: TextInputType.url,
            ),
          const SizedBox(height: 8),
          if (!_hidden.contains('gender')) ...[
            _label('marriage_gender'),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.wc_outlined),
              ),
              hint: Text('marriage_gender_hint'.tr),
              items: [
                for (final g in const ['Male', 'Female'])
                  DropdownMenuItem(value: g, child: Text(g.tr)),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('age'))
            _text(
              _ageController,
              'marriage_age',
              Icons.cake_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('city'))
            _text(
              _cityController,
              'marriage_city',
              Icons.location_city_outlined,
            ),
          if (!_hidden.contains('social_summary'))
            _text(
              _summaryController,
              'marriage_summary',
              Icons.notes_outlined,
              lines: 3,
            ),
          if (!_hidden.contains('private_notes'))
            _text(
              _notesController,
              'marriage_private_notes',
              Icons.lock_outline,
              lines: 2,
            ),
          if (!_hidden.contains('marital_status')) ...[
            _label('marriage_marital_status'),
            DropdownButtonFormField<String>(
              initialValue: _maritalStatus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.people_outline),
              ),
              hint: Text('marriage_marital_status_hint'.tr),
              items: [
                // "My Engagement" spec lists 8 marital-status options.
                for (final v in const [
                  'single',
                  'engaged',
                  'married',
                  'separated',
                  'widowed',
                  'divorced',
                  'separated_never_married',
                  'other',
                ])
                  DropdownMenuItem(
                    value: v,
                    child: Text('marital_status_$v'.tr),
                  ),
              ],
              onChanged: (v) => setState(() => _maritalStatus = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('religion'))
            _text(
              _religionController,
              'marriage_religion',
              Icons.church_outlined,
            ),
          if (!_hidden.contains('employment_status')) ...[
            _label('marriage_employment_status'),
            DropdownButtonFormField<String>(
              initialValue: _employmentStatus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.work_outline),
              ),
              hint: Text('marriage_employment_status_hint'.tr),
              items: [
                for (final v in const [
                  'employed',
                  'unemployed',
                  'self_employed',
                  'student',
                ])
                  DropdownMenuItem(
                    value: v,
                    child: Text('employment_status_$v'.tr),
                  ),
              ],
              onChanged: (v) => setState(() => _employmentStatus = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('weight'))
            _text(
              _weightController,
              'marriage_weight',
              Icons.monitor_weight_outlined,
              keyboard: TextInputType.number,
            ),
          if (!_hidden.contains('height'))
            _text(
              _heightController,
              'marriage_height',
              Icons.height_rounded,
              keyboard: TextInputType.number,
            ),
          _label('marriage_privacy'),
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.visibility_outlined),
            ),
            items: [
              for (final v in const [
                'private',
                'employee_only',
                'matched_summary',
              ])
                DropdownMenuItem(value: v, child: Text('vis_$v'.tr)),
            ],
            onChanged: (v) =>
                setState(() => _visibility = v ?? 'employee_only'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy ? 'activity_submitting'.tr : 'marriage_submit'.tr,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(key.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _text(
    TextEditingController c,
    String labelKey,
    IconData icon, {
    int lines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: labelKey.tr,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
