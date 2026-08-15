import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/auth_navigation.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/iraq_governorates.dart';
import 'package:flutter_application_1/data/nineveh_districts.dart';
import 'package:flutter_application_1/data/nineveh_neighborhoods.dart';
import 'package:flutter_application_1/modules/auth/widgets/auth_inline_error.dart';
import 'package:flutter_application_1/modules/legal/screens/terms_screen.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// New-user onboarding form. Replaces the old "Choose your role" screen:
/// collects name, date of birth, address and role, then submits the whole
/// thing to the admin for approval.
class RegistrationFormPage extends StatefulWidget {
  const RegistrationFormPage({super.key});

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _occupationController = TextEditingController();
  String? _gender; // #39 — optional: Male | Female | Other
  final _familySizeController = TextEditingController(); // #40 — eligible
  final _incomeController = TextEditingController();
  String? _housingStatus; // owned | rented | hosted | displaced
  final _skillsController = TextEditingController(); // #41 — volunteer
  final _availabilityController = TextEditingController();
  String? _experience; // none | lt1 | y1to3 | gt3
  DateTime? _dob;
  // Both the Eligible Recipient and Volunteer specs ask for date of birth as
  // day/month/year dropdowns rather than a calendar picker. These three drive
  // _dob, which stays the single source of truth for submission.
  int? _dobDay;
  int? _dobMonth;
  int? _dobYear;
  int? _roleId;
  bool _loading = false;
  String? _error;
  bool _agreeToTerms = false;
  Set<String> _required = {}; // #43 — admin-configured required optional fields
  // Note 33 / "Future Development" — fields the admin switched off entirely.
  // Hidden fields are not rendered, not validated, and never submitted.
  Set<String> _hidden = {};

  /// True when the admin hid [ruleKey] from the form (Admin Panel →
  /// registration field rules). Drives both rendering and submission.
  bool _isHidden(String ruleKey) => _hidden.contains(ruleKey);

  /// Renders [children] unless ANY of [ruleKeys] is hidden. Used for fields
  /// that live in a shared panel but also have a role-specific rule key, so
  /// the admin can switch them off either globally or for one role.
  List<Widget> _unlessHiddenAny(List<String> ruleKeys, List<Widget> children) =>
      ruleKeys.any(_hidden.contains) ? const [] : children;

  /// Renders [children] only when [ruleKey] isn't hidden. Spread into a
  /// Column's children: `..._unlessHidden('key', [...])`.
  List<Widget> _unlessHidden(String ruleKey, List<Widget> children) =>
      _hidden.contains(ruleKey) ? const [] : children;

  /// Like [_valueOf] but for shared fields carrying a role-specific rule key.
  String _valueOfAny(List<String> ruleKeys, String value) =>
      ruleKeys.any(_hidden.contains) ? '' : value;

  /// The value to submit for [ruleKey] — empty when the field is hidden, so a
  /// switched-off field never writes data.
  String _valueOf(String ruleKey, String value) =>
      _hidden.contains(ruleKey) ? '' : value;

  // Grantor registration spec — grantor-only detail fields.
  final _nationalIdController = TextEditingController();
  final _nameFirstController = TextEditingController();
  final _nameFatherController = TextEditingController();
  final _nameGrandfatherController = TextEditingController();
  final _nameFamilyController = TextEditingController();
  final _titleSurnameController = TextEditingController();
  final _phone1Controller = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _emailController = TextEditingController();
  String? _governorate;
  String? _educationLevel;
  double? _gpsLat;
  double? _gpsLng;
  bool _gpsLoading = false;
  String? _personalPhotoPath;
  String? _idPhotoPath;

  // Eligible Recipient registration spec — beneficiary-only detail fields
  // (national ID / four-part name / title-surname / phone1 / phone2 / email
  // above are shared with the grantor section and reused here as-is).
  final _tribeClanController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  String? _nationality;
  String? _maritalStatus;
  String? _residencyStatus;

  // Eligible Recipient registration spec — "Housing Information" section.
  // _governorate/_gpsLat/_gpsLng/_captureGpsLocation are shared with the
  // grantor section above and reused here as-is.
  String? _housingSide; // right | left | other — only used for Nineveh
  String? _neighborhoodDropdown; // Nineveh: picked from the side's list
  final _neighborhoodController =
      TextEditingController(); // other governorates: free text
  final _nearestLandmarkController = TextEditingController();
  String? _housingType;
  final _rentalAmountController = TextEditingController();
  final _housingAreaController = TextEditingController();
  String? _floorsCount;
  final _roomsCountController = TextEditingController();
  final _familiesCountController = TextEditingController();

  // Eligible Recipient registration spec — "Educational and Employment
  // Information" section. Date of birth (_dob), educational attainment
  // (_educationLevel) and current occupation (_occupationController) are
  // shared with the sections above and reused here as-is.
  final _otherCertificateController = TextEditingController();
  final _certificatesCountController = TextEditingController();
  final _previousOccupationController = TextEditingController();
  final _jobDescriptionController = TextEditingController();
  final _workingHoursController = TextEditingController();
  // "Employment Status" section — workplace/wage only shown when employed.
  String? _isEmployed; // yes | no
  final _workplaceController = TextEditingController();
  final _wageAmountController = TextEditingController();
  // "Social Information" section. Total family members reuses
  // _familySizeController from the eligible section below.
  String? _registeredSocialWelfare; // yes | no
  String? _registeredUnemployed; // yes | no
  final _householdEmployeesController = TextEditingController();
  final _workingMembersController = TextEditingController();
  final _menCountController = TextEditingController();
  final _womenCountController = TextEditingController();
  final _maleChildrenController = TextEditingController();
  final _femaleChildrenController = TextEditingController();
  final _age0To5Controller = TextEditingController();
  final _age5To10Controller = TextEditingController();
  final _age10To15Controller = TextEditingController();
  final _age15To25Controller = TextEditingController();
  final _age25To40Controller = TextEditingController();
  final _age40PlusController = TextEditingController();
  final _studentsCountController = TextEditingController();
  final _orphansCountController = TextEditingController();
  final _widowsCountController = TextEditingController();
  final _divorcedCountController = TextEditingController();

  // Eligible Recipient registration spec — "Health Information" section.
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String? _smokingStatus; // non_smoker | smoker | former
  String? _eyesightCondition; // normal | glasses | weak | blind
  String? _hasDisability; // yes | no
  final _disabilityTypeController = TextEditingController();
  final _householdDisabledController = TextEditingController();
  final _chronicIllnessesController = TextEditingController();
  final _medicalConditionsCountController = TextEditingController();
  final _medicalConditionsDescController = TextEditingController();
  // "Attachments" section. Personal photo and National Card photo reuse the
  // grantor pickers' _personalPhotoPath/_idPhotoPath above.
  String? _rationCardPhotoPath;
  String? _propertyProofPhotoPath;
  String? _medicalReportPhotoPath;
  String? _houseFacadePhotoPath;
  String? _houseInsidePhotoPath;
  String? _houseOutsidePhotoPath;
  // "Assets" / "Needs" sections.
  final _availableFurnitureController = TextEditingController();
  String? _ownsCar; // yes | no
  final _needsDescriptionController = TextEditingController();
  // "Social Media Accounts" section — same columns the Privacy Settings
  // screen writes, collected here at registration too.
  final _socialFacebookController = TextEditingController();
  final _socialInstagramController = TextEditingController();
  final _socialTelegramController = TextEditingController();

  // Eligible Recipient registration spec — "Privacy" consent section.
  String? _consentShowRealName; // yes | no
  String? _consentShareInfo; // yes | no

  // Volunteer/Employee registration spec — Personal / Housing / Social Media.
  final Set<String> _languages = <String>{};
  String? _district;
  final _socialOtherController = TextEditingController();
  // "Attachments" section — the formal personal photo, unified National Card
  // and Ration Card reuse the pickers above.
  String? _goldenSquarePhotoPath;
  String? _residenceCardPhotoPath;
  String? _passportPhotoPath;
  String? _graduationCertPhotoPath;
  String? _cvPhotoPath;

  @override
  void initState() {
    super.initState();
    // Prefill when editing after a rejection (or completing a grandfathered
    // account) so the user doesn't retype everything. Skip the auto-generated
    // "User 1234" login fallback (last-4-of-phone) — that's not a real name.
    final storedName = sharedPreferences.getString('name_user') ?? '';
    _nameController.text = RegExp(r'^User \d+$').hasMatch(storedName)
        ? ''
        : storedName;
    _addressController.text = sharedPreferences.getString('address_user') ?? '';
    final rid = int.tryParse(sharedPreferences.getString('role_id') ?? '');
    if (rid != null && rid >= 1 && rid <= 3) _roleId = rid;
    // #43 / Note 33 — load the admin-configured field rules: which optional
    // fields are required, and which are switched off entirely.
    fetchFieldRuleSets().then((rules) {
      if (mounted) {
        setState(() {
          _required = rules.required;
          _hidden = rules.hidden;
        });
      }
    });
  }

  // #43 — returns the label key of the first required-but-empty field, or null.
  String? _firstMissingRequired() {
    bool blank(String v) => v.trim().isEmpty;
    final checks = <String, ({bool applies, bool filled, String labelKey})>{
      'gender': (
        applies: true,
        filled: _gender != null,
        labelKey: 'reg_gender',
      ),
      'date_of_birth': (
        applies: true,
        filled: _dob != null,
        labelKey: 'Date of birth',
      ),
      'city': (
        applies: true,
        filled: !blank(_cityController.text),
        labelKey: 'reg_city',
      ),
      'occupation': (
        applies: true,
        filled: !blank(_occupationController.text),
        labelKey: 'reg_occupation',
      ),
      'family_size': (
        applies: _roleId == 2,
        filled: !blank(_familySizeController.text),
        labelKey: 'reg_family_size',
      ),
      'housing_status': (
        applies: _roleId == 2,
        filled: _housingStatus != null,
        labelKey: 'reg_housing',
      ),
      'monthly_income': (
        applies: _roleId == 2,
        filled: !blank(_incomeController.text),
        labelKey: 'reg_income',
      ),
      'skills': (
        applies: _roleId == 3,
        filled: !blank(_skillsController.text),
        labelKey: 'reg_skills',
      ),
      'availability': (
        applies: _roleId == 3,
        filled: !blank(_availabilityController.text),
        labelKey: 'reg_availability',
      ),
      'experience': (
        applies: _roleId == 3,
        filled: _experience != null,
        labelKey: 'reg_experience',
      ),
      // Grantor registration spec — required for the grantor role only.
      'grantor_name_parts': (
        applies: _roleId == 1,
        filled:
            !blank(_nameFirstController.text) &&
            !blank(_nameFatherController.text) &&
            !blank(_nameGrandfatherController.text) &&
            !blank(_nameFamilyController.text),
        labelKey: 'reg_grantor_name_parts',
      ),
      'grantor_title_surname': (
        applies: _roleId == 1,
        filled: !blank(_titleSurnameController.text),
        labelKey: 'reg_grantor_title_surname',
      ),
      'grantor_governorate': (
        applies: _roleId == 1,
        filled: _governorate != null,
        labelKey: 'reg_grantor_governorate',
      ),
      'grantor_education_level': (
        applies: _roleId == 1,
        filled: _educationLevel != null,
        labelKey: 'reg_grantor_education_level',
      ),
      // Eligible Recipient registration spec — required for the beneficiary
      // role only.
      'recipient_national_id': (
        applies: _roleId == 2,
        filled: !blank(_nationalIdController.text),
        labelKey: 'reg_recipient_national_id',
      ),
      'recipient_name_parts': (
        applies: _roleId == 2,
        filled:
            !blank(_nameFirstController.text) &&
            !blank(_nameFatherController.text) &&
            !blank(_nameGrandfatherController.text) &&
            !blank(_nameFamilyController.text),
        labelKey: 'reg_recipient_name_parts',
      ),
      'recipient_title_surname': (
        applies: _roleId == 2,
        filled: !blank(_titleSurnameController.text),
        labelKey: 'reg_recipient_title_surname',
      ),
      'recipient_email': (
        applies: _roleId == 2,
        filled: !blank(_emailController.text),
        labelKey: 'reg_recipient_email',
      ),
      'recipient_phone1': (
        applies: _roleId == 2,
        filled: !blank(_phone1Controller.text),
        labelKey: 'reg_recipient_phone1',
      ),
      'recipient_emergency_phone': (
        applies: _roleId == 2,
        filled: !blank(_emergencyPhoneController.text),
        labelKey: 'reg_recipient_emergency_phone',
      ),
      'recipient_nationality': (
        applies: _roleId == 2,
        filled: _nationality != null,
        labelKey: 'reg_recipient_nationality',
      ),
      'recipient_marital_status': (
        applies: _roleId == 2,
        filled: _maritalStatus != null,
        labelKey: 'reg_recipient_marital_status',
      ),
      'recipient_residency_status': (
        applies: _roleId == 2,
        filled: _residencyStatus != null,
        labelKey: 'reg_recipient_residency_status',
      ),
      // Eligible Recipient registration spec — "Housing Information".
      'recipient_governorate': (
        applies: _roleId == 2,
        filled: _governorate != null,
        labelKey: 'reg_grantor_governorate',
      ),
      'recipient_neighborhood': (
        applies: _roleId == 2,
        filled: _governorate == 'Nineveh'
            ? _neighborhoodDropdown != null
            : !blank(_neighborhoodController.text),
        labelKey: 'reg_recipient_neighborhood',
      ),
      'recipient_housing_type': (
        applies: _roleId == 2,
        filled: _housingType != null,
        labelKey: 'reg_recipient_housing_type',
      ),
      // Eligible Recipient spec — Educational/Employment, Employment Status,
      // Social, Health, Assets, Needs, Social Accounts, and Privacy sections.
      'recipient_education_level': (
        applies: _roleId == 2,
        filled: _educationLevel != null,
        labelKey: 'reg_grantor_education_level',
      ),
      'recipient_other_certificate': (
        applies: _roleId == 2,
        filled: !blank(_otherCertificateController.text),
        labelKey: 'reg_recipient_other_certificate',
      ),
      'recipient_certificates_count': (
        applies: _roleId == 2,
        filled: !blank(_certificatesCountController.text),
        labelKey: 'reg_recipient_certificates_count',
      ),
      'recipient_previous_occupation': (
        applies: _roleId == 2,
        filled: !blank(_previousOccupationController.text),
        labelKey: 'reg_recipient_previous_occupation',
      ),
      'recipient_job_description': (
        applies: _roleId == 2,
        filled: !blank(_jobDescriptionController.text),
        labelKey: 'reg_recipient_job_description',
      ),
      'recipient_working_hours': (
        applies: _roleId == 2,
        filled: !blank(_workingHoursController.text),
        labelKey: 'reg_recipient_working_hours',
      ),
      'recipient_is_employed': (
        applies: _roleId == 2,
        filled: _isEmployed != null,
        labelKey: 'reg_recipient_is_employed',
      ),
      'recipient_workplace': (
        applies: _roleId == 2 && _isEmployed == 'yes',
        filled: !blank(_workplaceController.text),
        labelKey: 'reg_recipient_workplace',
      ),
      'recipient_wage_amount': (
        applies: _roleId == 2 && _isEmployed == 'yes',
        filled: !blank(_wageAmountController.text),
        labelKey: 'reg_recipient_wage_amount',
      ),
      'recipient_registered_social_welfare': (
        applies: _roleId == 2,
        filled: _registeredSocialWelfare != null,
        labelKey: 'reg_recipient_registered_social_welfare',
      ),
      'recipient_registered_unemployed': (
        applies: _roleId == 2,
        filled: _registeredUnemployed != null,
        labelKey: 'reg_recipient_registered_unemployed',
      ),
      'recipient_household_employees': (
        applies: _roleId == 2,
        filled: !blank(_householdEmployeesController.text),
        labelKey: 'reg_recipient_household_employees',
      ),
      'recipient_working_members': (
        applies: _roleId == 2,
        filled: !blank(_workingMembersController.text),
        labelKey: 'reg_recipient_working_members',
      ),
      'recipient_men_count': (
        applies: _roleId == 2,
        filled: !blank(_menCountController.text),
        labelKey: 'reg_recipient_men_count',
      ),
      'recipient_women_count': (
        applies: _roleId == 2,
        filled: !blank(_womenCountController.text),
        labelKey: 'reg_recipient_women_count',
      ),
      'recipient_male_children_count': (
        applies: _roleId == 2,
        filled: !blank(_maleChildrenController.text),
        labelKey: 'reg_recipient_male_children_count',
      ),
      'recipient_female_children_count': (
        applies: _roleId == 2,
        filled: !blank(_femaleChildrenController.text),
        labelKey: 'reg_recipient_female_children_count',
      ),
      'recipient_age_0_5_count': (
        applies: _roleId == 2,
        filled: !blank(_age0To5Controller.text),
        labelKey: 'reg_recipient_age_0_5',
      ),
      'recipient_age_5_10_count': (
        applies: _roleId == 2,
        filled: !blank(_age5To10Controller.text),
        labelKey: 'reg_recipient_age_5_10',
      ),
      'recipient_age_10_15_count': (
        applies: _roleId == 2,
        filled: !blank(_age10To15Controller.text),
        labelKey: 'reg_recipient_age_10_15',
      ),
      'recipient_age_15_25_count': (
        applies: _roleId == 2,
        filled: !blank(_age15To25Controller.text),
        labelKey: 'reg_recipient_age_15_25',
      ),
      'recipient_age_25_40_count': (
        applies: _roleId == 2,
        filled: !blank(_age25To40Controller.text),
        labelKey: 'reg_recipient_age_25_40',
      ),
      'recipient_age_40_plus_count': (
        applies: _roleId == 2,
        filled: !blank(_age40PlusController.text),
        labelKey: 'reg_recipient_age_40_plus',
      ),
      'recipient_students_count': (
        applies: _roleId == 2,
        filled: !blank(_studentsCountController.text),
        labelKey: 'reg_recipient_students_count',
      ),
      'recipient_orphans_count': (
        applies: _roleId == 2,
        filled: !blank(_orphansCountController.text),
        labelKey: 'reg_recipient_orphans_count',
      ),
      'recipient_widows_count': (
        applies: _roleId == 2,
        filled: !blank(_widowsCountController.text),
        labelKey: 'reg_recipient_widows_count',
      ),
      'recipient_divorced_count': (
        applies: _roleId == 2,
        filled: !blank(_divorcedCountController.text),
        labelKey: 'reg_recipient_divorced_count',
      ),
      'recipient_height': (
        applies: _roleId == 2,
        filled: !blank(_heightController.text),
        labelKey: 'reg_recipient_height',
      ),
      'recipient_weight': (
        applies: _roleId == 2,
        filled: !blank(_weightController.text),
        labelKey: 'reg_recipient_weight',
      ),
      'recipient_smoking_status': (
        applies: _roleId == 2,
        filled: _smokingStatus != null,
        labelKey: 'reg_recipient_smoking_status',
      ),
      'recipient_eyesight_condition': (
        applies: _roleId == 2,
        filled: _eyesightCondition != null,
        labelKey: 'reg_recipient_eyesight_condition',
      ),
      'recipient_has_disability': (
        applies: _roleId == 2,
        filled: _hasDisability != null,
        labelKey: 'reg_recipient_has_disability',
      ),
      'recipient_disability_type': (
        applies: _roleId == 2 && _hasDisability == 'yes',
        filled: !blank(_disabilityTypeController.text),
        labelKey: 'reg_recipient_disability_type',
      ),
      'recipient_household_disabled': (
        applies: _roleId == 2,
        filled: !blank(_householdDisabledController.text),
        labelKey: 'reg_recipient_household_disabled',
      ),
      'recipient_chronic_illnesses': (
        applies: _roleId == 2,
        filled: !blank(_chronicIllnessesController.text),
        labelKey: 'reg_recipient_chronic_illnesses',
      ),
      'recipient_medical_conditions_count': (
        applies: _roleId == 2,
        filled: !blank(_medicalConditionsCountController.text),
        labelKey: 'reg_recipient_medical_conditions_count',
      ),
      'recipient_medical_conditions_desc': (
        applies: _roleId == 2,
        filled: !blank(_medicalConditionsDescController.text),
        labelKey: 'reg_recipient_medical_conditions_desc',
      ),
      'recipient_personal_photo': (
        applies: _roleId == 2,
        filled: _personalPhotoPath != null,
        labelKey: 'reg_recipient_personal_photo',
      ),
      'recipient_id_photo': (
        applies: _roleId == 2,
        filled: _idPhotoPath != null,
        labelKey: 'reg_recipient_id_photo',
      ),
      'recipient_ration_card_photo': (
        applies: _roleId == 2,
        filled: _rationCardPhotoPath != null,
        labelKey: 'reg_recipient_ration_card_photo',
      ),
      'recipient_property_proof_photo': (
        applies: _roleId == 2,
        filled: _propertyProofPhotoPath != null,
        labelKey: 'reg_recipient_property_proof_photo',
      ),
      'recipient_medical_report_photo': (
        applies: _roleId == 2,
        filled: _medicalReportPhotoPath != null,
        labelKey: 'reg_recipient_medical_report_photo',
      ),
      'recipient_house_facade_photo': (
        applies: _roleId == 2,
        filled: _houseFacadePhotoPath != null,
        labelKey: 'reg_recipient_house_facade_photo',
      ),
      'recipient_house_inside_photo': (
        applies: _roleId == 2,
        filled: _houseInsidePhotoPath != null,
        labelKey: 'reg_recipient_house_inside_photo',
      ),
      'recipient_house_outside_photo': (
        applies: _roleId == 2,
        filled: _houseOutsidePhotoPath != null,
        labelKey: 'reg_recipient_house_outside_photo',
      ),
      'recipient_available_furniture': (
        applies: _roleId == 2,
        filled: !blank(_availableFurnitureController.text),
        labelKey: 'reg_recipient_available_furniture',
      ),
      'recipient_owns_car': (
        applies: _roleId == 2,
        filled: _ownsCar != null,
        labelKey: 'reg_recipient_owns_car',
      ),
      'recipient_needs_description': (
        applies: _roleId == 2,
        filled: !blank(_needsDescriptionController.text),
        labelKey: 'reg_recipient_needs_description',
      ),
      'recipient_social_facebook': (
        applies: _roleId == 2,
        filled: !blank(_socialFacebookController.text),
        labelKey: 'reg_recipient_social_facebook',
      ),
      'recipient_social_instagram': (
        applies: _roleId == 2,
        filled: !blank(_socialInstagramController.text),
        labelKey: 'reg_recipient_social_instagram',
      ),
      'recipient_social_telegram': (
        applies: _roleId == 2,
        filled: !blank(_socialTelegramController.text),
        labelKey: 'reg_recipient_social_telegram',
      ),
      'recipient_consent_show_real_name': (
        applies: _roleId == 2,
        filled: _consentShowRealName != null,
        labelKey: 'reg_recipient_consent_show_real_name',
      ),
      'recipient_consent_share_info': (
        applies: _roleId == 2,
        filled: _consentShareInfo != null,
        labelKey: 'reg_recipient_consent_share_info',
      ),
      // Volunteer/Employee spec — "Identification"/"Contact Information".
      'volunteer_national_id': (
        applies: _roleId == 3,
        filled: !blank(_nationalIdController.text),
        labelKey: 'reg_volunteer_national_id',
      ),
      'volunteer_name_parts': (
        applies: _roleId == 3,
        filled:
            !blank(_nameFirstController.text) &&
            !blank(_nameFatherController.text) &&
            !blank(_nameGrandfatherController.text) &&
            !blank(_nameFamilyController.text),
        labelKey: 'reg_volunteer_name_parts',
      ),
      'volunteer_tribe_clan': (
        applies: _roleId == 3,
        filled: !blank(_tribeClanController.text),
        labelKey: 'reg_volunteer_tribe_clan',
      ),
      'volunteer_title_surname': (
        applies: _roleId == 3,
        filled: !blank(_titleSurnameController.text),
        labelKey: 'reg_volunteer_title_surname',
      ),
      'volunteer_phone1': (
        applies: _roleId == 3,
        filled: !blank(_phone1Controller.text),
        labelKey: 'reg_volunteer_phone1',
      ),
      'volunteer_phone2': (
        applies: _roleId == 3,
        filled: !blank(_phone2Controller.text),
        labelKey: 'reg_volunteer_phone2',
      ),
      'volunteer_emergency_phone': (
        applies: _roleId == 3,
        filled: !blank(_emergencyPhoneController.text),
        labelKey: 'reg_volunteer_emergency_phone',
      ),
      'volunteer_email': (
        applies: _roleId == 3,
        filled: !blank(_emailController.text),
        labelKey: 'reg_volunteer_email',
      ),
      // Volunteer/Employee spec — Personal / Housing / Social / Educational
      // / Attachments / Social Media sections.
      'volunteer_date_of_birth': (
        applies: _roleId == 3,
        filled: _dob != null,
        labelKey: 'Date of birth',
      ),
      'volunteer_gender': (
        applies: _roleId == 3,
        filled: _gender != null,
        labelKey: 'reg_gender',
      ),
      'volunteer_nationality': (
        applies: _roleId == 3,
        filled: _nationality != null,
        labelKey: 'reg_recipient_nationality',
      ),
      'volunteer_languages': (
        applies: _roleId == 3,
        filled: _languages.isNotEmpty,
        labelKey: 'reg_volunteer_languages',
      ),
      'volunteer_governorate': (
        applies: _roleId == 3,
        filled: _governorate != null,
        labelKey: 'reg_grantor_governorate',
      ),
      'volunteer_district': (
        applies: _roleId == 3 && _governorate == 'Nineveh',
        filled: _district != null,
        labelKey: 'reg_volunteer_district',
      ),
      'volunteer_housing_side': (
        applies: _roleId == 3 && _governorate == 'Nineveh',
        filled: _housingSide != null,
        labelKey: 'reg_recipient_housing_side',
      ),
      'volunteer_neighborhood': (
        applies: _roleId == 3,
        filled: _governorate == 'Nineveh'
            ? _neighborhoodDropdown != null
            : !blank(_neighborhoodController.text),
        labelKey: 'reg_recipient_neighborhood',
      ),
      'volunteer_nearest_landmark': (
        applies: _roleId == 3,
        filled: !blank(_nearestLandmarkController.text),
        labelKey: 'reg_recipient_nearest_landmark',
      ),
      'volunteer_housing_type': (
        applies: _roleId == 3,
        filled: _housingType != null,
        labelKey: 'reg_recipient_housing_type',
      ),
      'volunteer_housing_area': (
        applies: _roleId == 3,
        filled: !blank(_housingAreaController.text),
        labelKey: 'reg_recipient_housing_area',
      ),
      'volunteer_family_size': (
        applies: _roleId == 3,
        filled: !blank(_familySizeController.text),
        labelKey: 'reg_family_size',
      ),
      'volunteer_gps_location': (
        applies: _roleId == 3,
        filled: _gpsLat != null,
        labelKey: 'reg_grantor_gps_location',
      ),
      'volunteer_marital_status': (
        applies: _roleId == 3,
        filled: _maritalStatus != null,
        labelKey: 'reg_recipient_marital_status',
      ),
      'volunteer_education_level': (
        applies: _roleId == 3,
        filled: _educationLevel != null,
        labelKey: 'reg_grantor_education_level',
      ),
      'volunteer_other_certificate': (
        applies: _roleId == 3,
        filled: !blank(_otherCertificateController.text),
        labelKey: 'reg_recipient_other_certificate',
      ),
      'volunteer_occupation': (
        applies: _roleId == 3,
        filled: !blank(_occupationController.text),
        labelKey: 'reg_occupation',
      ),
      'volunteer_previous_occupation': (
        applies: _roleId == 3,
        filled: !blank(_previousOccupationController.text),
        labelKey: 'reg_recipient_previous_occupation',
      ),
      'volunteer_skills': (
        applies: _roleId == 3,
        filled: !blank(_skillsController.text),
        labelKey: 'reg_skills',
      ),
      'volunteer_experience': (
        applies: _roleId == 3,
        filled: _experience != null,
        labelKey: 'reg_experience',
      ),
      'volunteer_golden_square_photo': (
        applies: _roleId == 3,
        filled: _goldenSquarePhotoPath != null,
        labelKey: 'reg_volunteer_golden_square_photo',
      ),
      'volunteer_id_photo': (
        applies: _roleId == 3,
        filled: _idPhotoPath != null,
        labelKey: 'reg_volunteer_id_photo_doc',
      ),
      'volunteer_ration_card_photo': (
        applies: _roleId == 3,
        filled: _rationCardPhotoPath != null,
        labelKey: 'reg_volunteer_ration_card_photo',
      ),
      'volunteer_residence_card_photo': (
        applies: _roleId == 3,
        filled: _residenceCardPhotoPath != null,
        labelKey: 'reg_volunteer_residence_card_photo',
      ),
      'volunteer_passport_photo': (
        applies: _roleId == 3,
        filled: _passportPhotoPath != null,
        labelKey: 'reg_volunteer_passport_photo',
      ),
      'volunteer_personal_photo': (
        applies: _roleId == 3,
        filled: _personalPhotoPath != null,
        labelKey: 'reg_volunteer_personal_photo',
      ),
      'volunteer_graduation_cert_photo': (
        applies: _roleId == 3,
        filled: _graduationCertPhotoPath != null,
        labelKey: 'reg_volunteer_graduation_cert_photo',
      ),
      'volunteer_cv_photo': (
        applies: _roleId == 3,
        filled: _cvPhotoPath != null,
        labelKey: 'reg_volunteer_cv_photo',
      ),
      'volunteer_social_facebook': (
        applies: _roleId == 3,
        filled: !blank(_socialFacebookController.text),
        labelKey: 'reg_recipient_social_facebook',
      ),
      'volunteer_social_instagram': (
        applies: _roleId == 3,
        filled: !blank(_socialInstagramController.text),
        labelKey: 'reg_recipient_social_instagram',
      ),
      'volunteer_social_telegram': (
        applies: _roleId == 3,
        filled: !blank(_socialTelegramController.text),
        labelKey: 'reg_recipient_social_telegram',
      ),
      'volunteer_social_other': (
        applies: _roleId == 3,
        filled: !blank(_socialOtherController.text),
        labelKey: 'reg_volunteer_social_other',
      ),
    };
    // Client spec, "Future Development": every field's Required/Optional
    // state comes from the admin-configurable field rules
    // (registration_field_rules, editable from the Admin Panel) — there is
    // deliberately no hardcoded required list here, so staff can flip any
    // field either way with no code change. The migrations seed each field's
    // default state, and full name / address / role stay validated
    // separately in _submit() as the always-on baseline.
    for (final key in _required) {
      // A hidden field is never rendered, so it can't be filled in — it must
      // not block submission even if it's also flagged required.
      if (_isHidden(key)) continue;
      final c = checks[key];
      if (c != null && c.applies && !c.filled) return c.labelKey;
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _occupationController.dispose();
    _familySizeController.dispose();
    _incomeController.dispose();
    _skillsController.dispose();
    _availabilityController.dispose();
    _nationalIdController.dispose();
    _nameFirstController.dispose();
    _nameFatherController.dispose();
    _nameGrandfatherController.dispose();
    _nameFamilyController.dispose();
    _titleSurnameController.dispose();
    _phone1Controller.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _tribeClanController.dispose();
    _emergencyPhoneController.dispose();
    _neighborhoodController.dispose();
    _nearestLandmarkController.dispose();
    _rentalAmountController.dispose();
    _housingAreaController.dispose();
    _roomsCountController.dispose();
    _familiesCountController.dispose();
    _otherCertificateController.dispose();
    _certificatesCountController.dispose();
    _previousOccupationController.dispose();
    _jobDescriptionController.dispose();
    _workingHoursController.dispose();
    _workplaceController.dispose();
    _wageAmountController.dispose();
    _householdEmployeesController.dispose();
    _workingMembersController.dispose();
    _menCountController.dispose();
    _womenCountController.dispose();
    _maleChildrenController.dispose();
    _femaleChildrenController.dispose();
    _age0To5Controller.dispose();
    _age5To10Controller.dispose();
    _age10To15Controller.dispose();
    _age15To25Controller.dispose();
    _age25To40Controller.dispose();
    _age40PlusController.dispose();
    _studentsCountController.dispose();
    _orphansCountController.dispose();
    _widowsCountController.dispose();
    _divorcedCountController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _disabilityTypeController.dispose();
    _householdDisabledController.dispose();
    _chronicIllnessesController.dispose();
    _medicalConditionsCountController.dispose();
    _medicalConditionsDescController.dispose();
    _availableFurnitureController.dispose();
    _needsDescriptionController.dispose();
    _socialFacebookController.dispose();
    _socialInstagramController.dispose();
    _socialTelegramController.dispose();
    _socialOtherController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Grantor registration spec — "GPS location" (optional): captures the
  // device's current coordinates. Best-effort; a denied permission or
  // disabled location service just shows an error and leaves it unset.
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

  /// Picks one image and hands the local path to [assign], which stores it in
  /// the matching state field. Shared by every attachment picker on this form.
  Future<void> _pickPhotoInto(void Function(String path) assign) async {
    final path = await pickCroppedImage(context);
    if (path != null && mounted) {
      setState(() => assign(path));
    }
  }

  Future<void> _pickPersonalPhoto() =>
      _pickPhotoInto((p) => _personalPhotoPath = p);

  Future<void> _pickIdPhoto() => _pickPhotoInto((p) => _idPhotoPath = p);

  /// Recomposes [_dob] from the three dropdowns, clamping the day to the
  /// chosen month's length (so e.g. 31 February can't be submitted).
  void _syncDob() {
    final y = _dobYear, m = _dobMonth;
    if (y == null || m == null || _dobDay == null) {
      _dob = null;
      return;
    }
    final lastDay = DateTime(y, m + 1, 0).day;
    if (_dobDay! > lastDay) _dobDay = lastDay;
    _dob = DateTime(y, m, _dobDay!);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;
    if (_roleId == null) {
      setState(() => _error = 'Please select your role'.tr);
      return;
    }
    if (!_agreeToTerms) {
      setState(
        () => _error = 'Please accept the Terms & Conditions to continue'.tr,
      );
      return;
    }
    // #43 — enforce admin-configured required fields.
    final missing = _firstMissingRequired();
    if (missing != null) {
      setState(() => _error = '${missing.tr}: ${'reg_required_missing'.tr}');
      return;
    }
    AppHaptics.selection();
    setState(() => _loading = true);
    final res = await submitRegistration(
      fullName: _nameController.text.trim(),
      dateOfBirth: _valueOfAny([
        'date_of_birth',
        if (_roleId == 3) 'volunteer_date_of_birth',
      ], _dob == null ? '' : _fmt(_dob!)),
      address: _addressController.text.trim(),
      roleId: _roleId!,
      gender: _valueOfAny([
        'gender',
        if (_roleId == 3) 'volunteer_gender',
      ], _gender ?? ''),
      city: _cityController.text.trim(),
      occupation: _valueOfAny([
        'occupation',
        if (_roleId == 3) 'volunteer_occupation',
      ], _occupationController.text.trim()),
      familySize: (_roleId == 2 || _roleId == 3)
          ? _familySizeController.text.trim()
          : '',
      housingStatus: _roleId == 2 ? (_housingStatus ?? '') : '',
      monthlyIncome: _roleId == 2 ? _incomeController.text.trim() : '',
      skills: _valueOfAny(const [
        'skills',
        'volunteer_skills',
      ], _roleId == 3 ? _skillsController.text.trim() : ''),
      availability: _roleId == 3 ? _availabilityController.text.trim() : '',
      experience: _valueOfAny(const [
        'experience',
        'volunteer_experience',
      ], _roleId == 3 ? (_experience ?? '') : ''),
      // Identification + contact details are shared by all three roles: the
      // Grantor spec, the Eligible Recipient spec, and the Volunteer/Employee
      // spec's "Identification Information"/"Contact Information" sections.
      nationalId: _nationalIdController.text.trim(),
      nameFirst: _nameFirstController.text.trim(),
      nameFather: _nameFatherController.text.trim(),
      nameGrandfather: _nameGrandfatherController.text.trim(),
      nameFamily: _nameFamilyController.text.trim(),
      titleSurname: _titleSurnameController.text.trim(),
      phone1: _phone1Controller.text.trim(),
      phone2: _phone2Controller.text.trim(),
      email: _emailController.text.trim(),
      gpsLat: (_roleId == 1 || _roleId == 2 || _roleId == 3) ? _gpsLat : null,
      gpsLng: (_roleId == 1 || _roleId == 2 || _roleId == 3) ? _gpsLng : null,
      governorate: (_roleId == 1 || _roleId == 2 || _roleId == 3)
          ? (_governorate ?? '')
          : '',
      // Educational attainment is collected for the grantor role and, per the
      // Eligible Recipient spec's "Educational and Employment Information"
      // section, for the recipient role too.
      educationLevel: (_roleId == 1 || _roleId == 2 || _roleId == 3)
          ? (_educationLevel ?? '')
          : '',
      // Tribe/clan and the emergency contact are collected for the recipient
      // and (per its Identification/Contact sections) the volunteer role.
      tribeClan: (_roleId == 2 || _roleId == 3)
          ? _tribeClanController.text.trim()
          : '',
      emergencyPhone: (_roleId == 2 || _roleId == 3)
          ? _emergencyPhoneController.text.trim()
          : '',
      nationality: (_roleId == 2 || _roleId == 3) ? (_nationality ?? '') : '',
      maritalStatus: (_roleId == 2 || _roleId == 3)
          ? (_maritalStatus ?? '')
          : '',
      residencyStatus: _roleId == 2 ? (_residencyStatus ?? '') : '',
      housingSide: _valueOf(
        'recipient_housing_side',
        (_roleId == 2 || _roleId == 3) ? (_housingSide ?? '') : '',
      ),
      neighborhood: (_roleId == 2 || _roleId == 3)
          ? (_governorate == 'Nineveh'
                ? (_neighborhoodDropdown ?? '')
                : _neighborhoodController.text.trim())
          : '',
      nearestLandmark: _valueOf(
        'recipient_nearest_landmark',
        (_roleId == 2 || _roleId == 3)
            ? _nearestLandmarkController.text.trim()
            : '',
      ),
      housingType: _valueOf(
        'recipient_housing_type',
        (_roleId == 2 || _roleId == 3) ? (_housingType ?? '') : '',
      ),
      rentalAmount: _valueOf(
        'recipient_rental_amount',
        _roleId == 2 && _housingType == 'rented'
            ? _rentalAmountController.text.trim()
            : '',
      ),
      housingArea: _valueOf(
        'recipient_housing_area',
        (_roleId == 2 || _roleId == 3)
            ? _housingAreaController.text.trim()
            : '',
      ),
      floorsCount: _valueOf(
        'recipient_floors_count',
        _roleId == 2 ? (_floorsCount ?? '') : '',
      ),
      roomsCount: _valueOf(
        'recipient_rooms_count',
        _roleId == 2 ? _roomsCountController.text.trim() : '',
      ),
      familiesCount: _valueOf(
        'recipient_families_count',
        _roleId == 2 ? _familiesCountController.text.trim() : '',
      ),
      // Eligible Recipient spec — Educational/Employment, Employment Status
      // and Social Information sections (recipient role only).
      otherCertificate: _valueOf(
        'recipient_other_certificate',
        (_roleId == 2 || _roleId == 3)
            ? _otherCertificateController.text.trim()
            : '',
      ),
      certificatesCount: _valueOf(
        'recipient_certificates_count',
        _roleId == 2 ? _certificatesCountController.text.trim() : '',
      ),
      previousOccupation: _valueOf(
        'recipient_previous_occupation',
        (_roleId == 2 || _roleId == 3)
            ? _previousOccupationController.text.trim()
            : '',
      ),
      jobDescription: _valueOf(
        'recipient_job_description',
        _roleId == 2 ? _jobDescriptionController.text.trim() : '',
      ),
      workingHours: _valueOf(
        'recipient_working_hours',
        _roleId == 2 ? _workingHoursController.text.trim() : '',
      ),
      isEmployed: _valueOf(
        'recipient_is_employed',
        _roleId == 2 ? (_isEmployed ?? '') : '',
      ),
      // Workplace/wage only apply when the person is currently employed.
      workplace: _valueOf(
        'recipient_workplace',
        _roleId == 2 && _isEmployed == 'yes'
            ? _workplaceController.text.trim()
            : '',
      ),
      wageAmount: _valueOf(
        'recipient_wage_amount',
        _roleId == 2 && _isEmployed == 'yes'
            ? _wageAmountController.text.trim()
            : '',
      ),
      registeredSocialWelfare: _valueOf(
        'recipient_registered_social_welfare',
        _roleId == 2 ? (_registeredSocialWelfare ?? '') : '',
      ),
      registeredUnemployed: _valueOf(
        'recipient_registered_unemployed',
        _roleId == 2 ? (_registeredUnemployed ?? '') : '',
      ),
      householdEmployeesCount: _valueOf(
        'recipient_household_employees',
        _roleId == 2 ? _householdEmployeesController.text.trim() : '',
      ),
      workingMembersCount: _valueOf(
        'recipient_working_members',
        _roleId == 2 ? _workingMembersController.text.trim() : '',
      ),
      menCount: _valueOf(
        'recipient_men_count',
        _roleId == 2 ? _menCountController.text.trim() : '',
      ),
      womenCount: _valueOf(
        'recipient_women_count',
        _roleId == 2 ? _womenCountController.text.trim() : '',
      ),
      maleChildrenCount: _valueOf(
        'recipient_male_children_count',
        _roleId == 2 ? _maleChildrenController.text.trim() : '',
      ),
      femaleChildrenCount: _valueOf(
        'recipient_female_children_count',
        _roleId == 2 ? _femaleChildrenController.text.trim() : '',
      ),
      age0To5Count: _valueOf(
        'recipient_age_0_5_count',
        _roleId == 2 ? _age0To5Controller.text.trim() : '',
      ),
      age5To10Count: _valueOf(
        'recipient_age_5_10_count',
        _roleId == 2 ? _age5To10Controller.text.trim() : '',
      ),
      age10To15Count: _valueOf(
        'recipient_age_10_15_count',
        _roleId == 2 ? _age10To15Controller.text.trim() : '',
      ),
      age15To25Count: _valueOf(
        'recipient_age_15_25_count',
        _roleId == 2 ? _age15To25Controller.text.trim() : '',
      ),
      age25To40Count: _valueOf(
        'recipient_age_25_40_count',
        _roleId == 2 ? _age25To40Controller.text.trim() : '',
      ),
      age40PlusCount: _valueOf(
        'recipient_age_40_plus_count',
        _roleId == 2 ? _age40PlusController.text.trim() : '',
      ),
      studentsCount: _valueOf(
        'recipient_students_count',
        _roleId == 2 ? _studentsCountController.text.trim() : '',
      ),
      orphansCount: _valueOf(
        'recipient_orphans_count',
        _roleId == 2 ? _orphansCountController.text.trim() : '',
      ),
      widowsCount: _valueOf(
        'recipient_widows_count',
        _roleId == 2 ? _widowsCountController.text.trim() : '',
      ),
      divorcedCount: _valueOf(
        'recipient_divorced_count',
        _roleId == 2 ? _divorcedCountController.text.trim() : '',
      ),
      // Eligible Recipient spec — Health, Assets, Needs and Social Media
      // Accounts sections (recipient role only).
      height: _valueOf(
        'recipient_height',
        _roleId == 2 ? _heightController.text.trim() : '',
      ),
      weight: _valueOf(
        'recipient_weight',
        _roleId == 2 ? _weightController.text.trim() : '',
      ),
      smokingStatus: _valueOf(
        'recipient_smoking_status',
        _roleId == 2 ? (_smokingStatus ?? '') : '',
      ),
      eyesightCondition: _valueOf(
        'recipient_eyesight_condition',
        _roleId == 2 ? (_eyesightCondition ?? '') : '',
      ),
      hasDisability: _valueOf(
        'recipient_has_disability',
        _roleId == 2 ? (_hasDisability ?? '') : '',
      ),
      // Type of disability only applies when there is one.
      disabilityType: _valueOf(
        'recipient_disability_type',
        _roleId == 2 && _hasDisability == 'yes'
            ? _disabilityTypeController.text.trim()
            : '',
      ),
      householdDisabledCount: _valueOf(
        'recipient_household_disabled',
        _roleId == 2 ? _householdDisabledController.text.trim() : '',
      ),
      chronicIllnesses: _valueOf(
        'recipient_chronic_illnesses',
        _roleId == 2 ? _chronicIllnessesController.text.trim() : '',
      ),
      medicalConditionsCount: _valueOf(
        'recipient_medical_conditions_count',
        _roleId == 2 ? _medicalConditionsCountController.text.trim() : '',
      ),
      medicalConditionsDesc: _valueOf(
        'recipient_medical_conditions_desc',
        _roleId == 2 ? _medicalConditionsDescController.text.trim() : '',
      ),
      availableFurniture: _valueOf(
        'recipient_available_furniture',
        _roleId == 2 ? _availableFurnitureController.text.trim() : '',
      ),
      ownsCar: _valueOf(
        'recipient_owns_car',
        _roleId == 2 ? (_ownsCar ?? '') : '',
      ),
      needsDescription: _valueOf(
        'recipient_needs_description',
        _roleId == 2 ? _needsDescriptionController.text.trim() : '',
      ),
      socialFacebook: _valueOf(
        'recipient_social_facebook',
        (_roleId == 2 || _roleId == 3)
            ? _socialFacebookController.text.trim()
            : '',
      ),
      socialInstagram: _valueOf(
        'recipient_social_instagram',
        (_roleId == 2 || _roleId == 3)
            ? _socialInstagramController.text.trim()
            : '',
      ),
      socialTelegram: _valueOf(
        'recipient_social_telegram',
        (_roleId == 2 || _roleId == 3)
            ? _socialTelegramController.text.trim()
            : '',
      ),
      consentShowRealName: _valueOf(
        'recipient_consent_show_real_name',
        _roleId == 2 ? (_consentShowRealName ?? '') : '',
      ),
      consentShareInfo: _valueOf(
        'recipient_consent_share_info',
        _roleId == 2 ? (_consentShareInfo ?? '') : '',
      ),
      // Volunteer/Employee spec — Personal / Housing / Social Media.
      languages: _valueOf(
        'volunteer_languages',
        _roleId == 3 ? (_languages.toList()..sort()).join(',') : '',
      ),
      district: _valueOf(
        'volunteer_district',
        _roleId == 3 ? (_district ?? '') : '',
      ),
      socialOther: _valueOf(
        'volunteer_social_other',
        _roleId == 3 ? _socialOtherController.text.trim() : '',
      ),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.ok) {
      AppHaptics.success();
      // Grantor + Eligible Recipient specs — best-effort attachment upload;
      // never blocks the registration flow if it fails (all attachments are
      // optional). The grantor form collects the first two; the recipient
      // form adds the "Attachments" section's extra documents.
      if (_roleId == 1 || _roleId == 2 || _roleId == 3) {
        unawaited(
          uploadRegistrationPhotos(
            personalPhotoPath: _personalPhotoPath,
            idPhotoPath: _idPhotoPath,
            rationCardPhotoPath: _rationCardPhotoPath,
            propertyProofPhotoPath: _propertyProofPhotoPath,
            medicalReportPhotoPath: _medicalReportPhotoPath,
            houseFacadePhotoPath: _houseFacadePhotoPath,
            houseInsidePhotoPath: _houseInsidePhotoPath,
            houseOutsidePhotoPath: _houseOutsidePhotoPath,
            goldenSquarePhotoPath: _goldenSquarePhotoPath,
            residenceCardPhotoPath: _residenceCardPhotoPath,
            passportPhotoPath: _passportPhotoPath,
            graduationCertPhotoPath: _graduationCertPhotoPath,
            cvPhotoPath: _cvPhotoPath,
          ).then((uploaded) {
            // The result used to be DISCARDED. Registration succeeded and the
            // user was routed onward, so a failed document upload was silent
            // and permanent — they believed their ID and proof documents were
            // filed when nothing had arrived, which for an eligible applicant
            // is the difference between a case that can be reviewed and one
            // that cannot.
            //
            // Still unawaited, deliberately: attachments are optional and must
            // not hold up the flow. Get.snackbar is an overlay rather than
            // part of this route, so it survives the navigation below and
            // lands over whatever screen the user reaches.
            if (uploaded) return;
            Get.snackbar(
              'Registration'.tr,
              'Your registration was saved, but your documents did not upload. You can add them from your profile.'
                  .tr,
              duration: const Duration(seconds: 6),
            );
          }),
        );
      }
      // pending -> waiting screen; approved (grandfathered) -> home.
      routeByRegistrationStatus(res.status);
    } else {
      AppHaptics.error();
      setState(() {
        _error = (res.error != null && res.error!.trim().isNotEmpty)
            ? res.error
            : 'Could not submit your registration. Please try again.'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _loading,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageTopBar(
                        title: 'Complete your registration',
                        onBack: () {
                          // Reached via Get.offAllNamed right after OTP
                          // verification, so there's no previous route to
                          // pop back to — "back" here means abandoning this
                          // signup and returning to sign-in.
                          Get.offAllNamed(AppRoutes.authLogin);
                          logout();
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tell us about yourself so an admin can review your account.'
                            .tr,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                      const SizedBox(height: 18),
                      GlassPanel(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label(context, 'Your full name'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                hintText: 'Your full name'.tr,
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Please enter your name'.tr
                                  : null,
                            ),
                            // Client spec (Eligible Recipient + Volunteer):
                            // date of birth is entered as day/month/year
                            // dropdowns, not a calendar picker.
                            ..._unlessHiddenAny(
                              [
                                'date_of_birth',
                                if (_roleId == 3) 'volunteer_date_of_birth',
                              ],
                              [
                                const SizedBox(height: 16),
                                _label(context, 'Date of birth'),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: _dobDay,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 18,
                                          ),
                                        ),
                                        hint: Text('reg_dob_day'.tr),
                                        items: [
                                          for (var d = 1; d <= 31; d++)
                                            DropdownMenuItem(
                                              value: d,
                                              child: Text('$d'),
                                            ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          _dobDay = v;
                                          _syncDob();
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: _dobMonth,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 18,
                                          ),
                                        ),
                                        hint: Text('reg_dob_month'.tr),
                                        items: [
                                          for (var m = 1; m <= 12; m++)
                                            DropdownMenuItem(
                                              value: m,
                                              child: Text('$m'),
                                            ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          _dobMonth = v;
                                          _syncDob();
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: _dobYear,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 18,
                                          ),
                                        ),
                                        hint: Text('reg_dob_year'.tr),
                                        items: [
                                          for (
                                            var y = DateTime.now().year;
                                            y >= 1900;
                                            y--
                                          )
                                            DropdownMenuItem(
                                              value: y,
                                              child: Text('$y'),
                                            ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          _dobYear = v;
                                          _syncDob();
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _label(context, 'Your address'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _addressController,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                hintText: 'Your address'.tr,
                                prefixIcon: const Icon(
                                  Icons.location_on_outlined,
                                ),
                              ),
                              validator: (v) {
                                // Grantor registration spec — residential
                                // address is optional for the grantor role.
                                if (_roleId == 1) return null;
                                return (v == null || v.trim().isEmpty)
                                    ? 'Please enter your address'.tr
                                    : null;
                              },
                            ),
                            // #39 — fuller sign-up fields (all optional).
                            ..._unlessHiddenAny(
                              ['gender', if (_roleId == 3) 'volunteer_gender'],
                              [
                                const SizedBox(height: 16),
                                _label(context, 'reg_gender'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _gender,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.wc_outlined),
                                  ),
                                  hint: Text('reg_gender_hint'.tr),
                                  items: [
                                    for (final g in const [
                                      'Male',
                                      'Female',
                                      'Other',
                                    ])
                                      DropdownMenuItem(
                                        value: g,
                                        child: Text(g.tr),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() => _gender = v),
                                ),
                              ],
                            ),
                            ..._unlessHidden('city', [
                              const SizedBox(height: 16),
                              _label(context, 'reg_city'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _cityController,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: 'reg_city_hint'.tr,
                                  prefixIcon: const Icon(
                                    Icons.location_city_outlined,
                                  ),
                                ),
                              ),
                            ]),
                            ..._unlessHiddenAny(
                              [
                                'occupation',
                                if (_roleId == 3) 'volunteer_occupation',
                              ],
                              [
                                const SizedBox(height: 16),
                                _label(context, 'reg_occupation'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _occupationController,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    hintText: 'reg_occupation_hint'.tr,
                                    prefixIcon: const Icon(Icons.work_outline),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _label(context, 'Select your role'),
                      const SizedBox(height: 10),
                      _RoleTile(
                        icon: Icons.volunteer_activism_rounded,
                        color: Colors.amber,
                        label: 'Donor',
                        tagline: 'Give and support causes',
                        selected: _roleId == 1,
                        onTap: () => setState(() => _roleId = 1),
                      ),
                      const SizedBox(height: 10),
                      _RoleTile(
                        icon: Icons.family_restroom_rounded,
                        color: Colors.deepOrangeAccent,
                        label: 'Beneficiary',
                        tagline: 'Receive aid and support',
                        selected: _roleId == 2,
                        onTap: () => setState(() => _roleId = 2),
                      ),
                      const SizedBox(height: 10),
                      _RoleTile(
                        icon: Icons.handshake_rounded,
                        color: Colors.lightBlue,
                        label: 'Volunteer',
                        tagline: 'Help on the ground',
                        selected: _roleId == 3,
                        onTap: () => setState(() => _roleId = 3),
                      ),
                      // Grantor registration spec — extra fields.
                      if (_roleId == 1) ...[
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_grantor_section'),
                              ..._unlessHidden('grantor_national_id', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_grantor_national_id'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nationalIdController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_national_id_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('grantor_name_parts', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_name_parts'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nameFirstController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_name_first_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _nameFatherController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_name_father_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _nameGrandfatherController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_grantor_name_grandfather_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _nameFamilyController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_name_family_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('grantor_title_surname', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_title_surname'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _titleSurnameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_grantor_title_surname_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('grantor_phone1', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_phone1'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _phone1Controller,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_phone1_hint'.tr,
                                    prefixIcon: const Icon(Icons.call_outlined),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('grantor_phone2', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_phone2'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _phone2Controller,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_phone2_hint'.tr,
                                    prefixIcon: const Icon(Icons.call_outlined),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('grantor_email', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_email'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_email_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.email_outlined,
                                    ),
                                  ),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty) return null;
                                    final ok = RegExp(
                                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                    ).hasMatch(value);
                                    return ok
                                        ? null
                                        : 'reg_grantor_email_invalid'.tr;
                                  },
                                ),
                              ]),
                              ..._unlessHidden('grantor_governorate', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_governorate'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _governorate,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.map_outlined),
                                  ),
                                  hint: Text('reg_grantor_governorate_hint'.tr),
                                  items: [
                                    for (final g in iraqGovernorates)
                                      DropdownMenuItem(
                                        value: g,
                                        child: Text(g.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _governorate = v),
                                ),
                              ]),
                              ..._unlessHidden('grantor_education_level', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_education_level'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _educationLevel,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.school_outlined),
                                  ),
                                  hint: Text(
                                    'reg_grantor_education_level_hint'.tr,
                                  ),
                                  items: [
                                    for (final e in const [
                                      'none',
                                      'primary',
                                      'secondary',
                                      'diploma',
                                      'bachelor',
                                      'master',
                                      'phd',
                                    ])
                                      DropdownMenuItem(
                                        value: e,
                                        child: Text('education_$e'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _educationLevel = v),
                                ),
                              ]),
                              ..._unlessHidden('grantor_gps_location', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_gps_location'),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: _gpsLoading
                                      ? null
                                      : _captureGpsLocation,
                                  icon: _gpsLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location_rounded),
                                  label: Text(
                                    _gpsLat == null
                                        ? 'reg_grantor_gps_capture'.tr
                                        : '${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)}',
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('grantor_personal_photo', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_personal_photo'),
                                const SizedBox(height: 6),
                                _PhotoPickerTile(
                                  imagePath: _personalPhotoPath,
                                  placeholderIcon: Icons.person_outline,
                                  onTap: _pickPersonalPhoto,
                                ),
                              ]),
                              ..._unlessHidden('grantor_id_photo', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_id_photo'),
                                const SizedBox(height: 6),
                                _PhotoPickerTile(
                                  imagePath: _idPhotoPath,
                                  placeholderIcon: Icons.badge_outlined,
                                  onTap: _pickIdPhoto,
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                      // Eligible Recipient registration spec — Identification
                      // + Personal Information.
                      if (_roleId == 2) ...[
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_recipient_identification_section',
                              ),
                              ..._unlessHidden('recipient_national_id', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_recipient_national_id'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nationalIdController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_national_id_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_name_parts', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_name_parts'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nameFirstController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_name_first_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _nameFatherController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_name_father_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _nameGrandfatherController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_grantor_name_grandfather_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _nameFamilyController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_name_family_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_tribe_clan', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_tribe_clan'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _tribeClanController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_tribe_clan_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.groups_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_title_surname', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_title_surname'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _titleSurnameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_grantor_title_surname_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_email', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_email'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_recipient_email_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.email_outlined,
                                    ),
                                  ),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty) return null;
                                    final ok = RegExp(
                                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                    ).hasMatch(value);
                                    return ok
                                        ? null
                                        : 'reg_grantor_email_invalid'.tr;
                                  },
                                ),
                              ]),
                              ..._unlessHidden('recipient_phone1', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_phone1'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _phone1Controller,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_recipient_phone1_hint'.tr,
                                    prefixIcon: const Icon(Icons.call_outlined),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_phone2', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_phone2'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _phone2Controller,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_grantor_phone2_hint'.tr,
                                    prefixIcon: const Icon(Icons.call_outlined),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_emergency_phone', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_emergency_phone',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _emergencyPhoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_emergency_phone_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.emergency_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_personal_section'),
                              ..._unlessHidden('recipient_nationality', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_recipient_nationality'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _nationality,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.public_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_nationality_hint'.tr,
                                  ),
                                  items: [
                                    for (final n in const [
                                      'iraqi',
                                      'syrian',
                                      'egyptian',
                                      'gulf',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: n,
                                        child: Text('nationality_$n'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _nationality = v),
                                ),
                              ]),
                              ..._unlessHidden('recipient_marital_status', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_marital_status'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _maritalStatus,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.favorite_border_rounded,
                                    ),
                                  ),
                                  hint: Text(
                                    'reg_recipient_marital_status_hint'.tr,
                                  ),
                                  items: [
                                    for (final m in const [
                                      'single',
                                      'engaged',
                                      'married',
                                      'separated',
                                      'widowed',
                                      'divorced',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: m,
                                        child: Text('marital_$m'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _maritalStatus = v),
                                ),
                              ]),
                              ..._unlessHidden('recipient_residency_status', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_residency_status',
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _residencyStatus,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.home_work_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_residency_status_hint'.tr,
                                  ),
                                  items: [
                                    for (final r in const [
                                      'local',
                                      'returnee',
                                      'displaced',
                                      'refugee',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: r,
                                        child: Text('residency_$r'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _residencyStatus = v),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_housing_section'),
                              const SizedBox(height: 12),
                              _label(context, 'reg_grantor_governorate'),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _governorate,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.map_outlined),
                                ),
                                hint: Text('reg_grantor_governorate_hint'.tr),
                                items: [
                                  for (final g in iraqGovernorates)
                                    DropdownMenuItem(
                                      value: g,
                                      child: Text(g.tr),
                                    ),
                                ],
                                onChanged: (v) => setState(() {
                                  _governorate = v;
                                  // Switching governorate invalidates any
                                  // previously-picked Nineveh side/neighborhood.
                                  _housingSide = null;
                                  _neighborhoodDropdown = null;
                                }),
                              ),
                              if (_governorate == 'Nineveh') ...[
                                ..._unlessHidden('recipient_housing_side', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_housing_side'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _housingSide,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.swap_horiz_rounded,
                                      ),
                                    ),
                                    hint: Text(
                                      'reg_recipient_housing_side_hint'.tr,
                                    ),
                                    items: [
                                      for (final s in const [
                                        'right',
                                        'left',
                                        'other',
                                      ])
                                        DropdownMenuItem(
                                          value: s,
                                          child: Text('housing_side_$s'.tr),
                                        ),
                                    ],
                                    onChanged: (v) => setState(() {
                                      _housingSide = v;
                                      _neighborhoodDropdown = null;
                                    }),
                                  ),
                                ]),
                                ..._unlessHidden('recipient_neighborhood', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_neighborhood'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _neighborhoodDropdown,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.location_city_outlined,
                                      ),
                                    ),
                                    hint: Text(
                                      'reg_recipient_neighborhood_hint'.tr,
                                    ),
                                    items: [
                                      for (final n
                                          in _housingSide == 'left'
                                              ? ninevehLeftSideNeighborhoods
                                              : ninevehRightSideNeighborhoods)
                                        DropdownMenuItem(
                                          value: n,
                                          child: Text(n),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => _neighborhoodDropdown = v,
                                    ),
                                  ),
                                ]),
                              ] else ...[
                                ..._unlessHidden('recipient_neighborhood', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_neighborhood'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _neighborhoodController,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText:
                                          'reg_recipient_neighborhood_free_hint'
                                              .tr,
                                      prefixIcon: const Icon(
                                        Icons.location_city_outlined,
                                      ),
                                    ),
                                  ),
                                ]),
                              ],
                              ..._unlessHidden('recipient_nearest_landmark', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_nearest_landmark',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nearestLandmarkController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_nearest_landmark_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.place_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_gps_location', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_gps_location'),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: _gpsLoading
                                      ? null
                                      : _captureGpsLocation,
                                  icon: _gpsLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location_rounded),
                                  label: Text(
                                    _gpsLat == null
                                        ? 'reg_grantor_gps_capture'.tr
                                        : '${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)}',
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_housing_type', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_housing_type'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _housingType,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.house_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_housing_type_hint'.tr,
                                  ),
                                  items: [
                                    for (final h in const [
                                      'owned',
                                      'rented',
                                      'inherited',
                                      'shared',
                                      'usage',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: h,
                                        child: Text('housing_type_$h'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _housingType = v),
                                ),
                              ]),
                              if (_housingType == 'rented' &&
                                  !_isHidden('recipient_rental_amount')) ...[
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_rental_amount'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _rentalAmountController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_rental_amount_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.payments_outlined,
                                    ),
                                  ),
                                ),
                              ],
                              ..._unlessHidden('recipient_housing_area', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_housing_area'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _housingAreaController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_housing_area_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.square_foot_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_floors_count', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_floors_count'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _floorsCount,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.stairs_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_floors_count_hint'.tr,
                                  ),
                                  items: [
                                    for (final f in const [
                                      'one',
                                      'one_half',
                                      'two',
                                      'three_plus',
                                    ])
                                      DropdownMenuItem(
                                        value: f,
                                        child: Text('floors_$f'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _floorsCount = v),
                                ),
                              ]),
                              ..._unlessHidden('recipient_rooms_count', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_rooms_count'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _roomsCountController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_rooms_count_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.door_front_door_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_families_count', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_families_count'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _familiesCountController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_families_count_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.groups_2_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Educational and Employment
                        // Information". Date of birth and current occupation
                        // are collected in the shared section above, and
                        // monthly income in the eligible section below, so
                        // only the remaining fields appear here rather than
                        // being duplicated.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_recipient_education_employment_section',
                              ),
                              ..._unlessHidden('recipient_education_level', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_grantor_education_level'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _educationLevel,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.school_outlined),
                                  ),
                                  hint: Text(
                                    'reg_grantor_education_level_hint'.tr,
                                  ),
                                  items: [
                                    for (final e in const [
                                      'none',
                                      'primary',
                                      'secondary',
                                      'diploma',
                                      'bachelor',
                                      'master',
                                      'phd',
                                    ])
                                      DropdownMenuItem(
                                        value: e,
                                        child: Text('education_$e'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _educationLevel = v),
                                ),
                              ]),
                              ..._unlessHidden('recipient_other_certificate', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_other_certificate',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _otherCertificateController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_other_certificate_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.workspace_premium_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_certificates_count', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_certificates_count',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _certificatesCountController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_certificates_count_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.numbers_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_previous_occupation', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_previous_occupation',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _previousOccupationController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_previous_occupation_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.history_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_job_description', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_job_description',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _jobDescriptionController,
                                  minLines: 1,
                                  maxLines: 3,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_job_description_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.description_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_working_hours', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_working_hours'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _workingHoursController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_working_hours_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.schedule_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Employment Status".
                        // Workplace/wage only appear when currently employed.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_recipient_employment_status_section',
                              ),
                              ..._unlessHidden('recipient_is_employed', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_recipient_is_employed'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _isEmployed,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_is_employed_hint'.tr,
                                  ),
                                  items: [
                                    for (final v in const ['yes', 'no'])
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text('yesno_$v'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _isEmployed = v),
                                ),
                              ]),
                              if (_isEmployed == 'yes') ...[
                                ..._unlessHidden('recipient_workplace', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_workplace'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _workplaceController,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText:
                                          'reg_recipient_workplace_hint'.tr,
                                      prefixIcon: const Icon(
                                        Icons.business_outlined,
                                      ),
                                    ),
                                  ),
                                ]),
                                ..._unlessHidden('recipient_wage_amount', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_wage_amount'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _wageAmountController,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText:
                                          'reg_recipient_wage_amount_hint'.tr,
                                      prefixIcon: const Icon(
                                        Icons.payments_outlined,
                                      ),
                                    ),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Social Information".
                        // Total family members is collected in the eligible
                        // section below (reg_family_size) and not repeated.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_social_section'),
                              ..._unlessHidden(
                                'recipient_registered_social_welfare',
                                [
                                  const SizedBox(height: 12),
                                  _label(
                                    context,
                                    'reg_recipient_registered_social_welfare',
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _registeredSocialWelfare,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.volunteer_activism_outlined,
                                      ),
                                    ),
                                    hint: Text(
                                      'reg_recipient_registered_social_welfare_hint'
                                          .tr,
                                    ),
                                    items: [
                                      for (final v in const ['yes', 'no'])
                                        DropdownMenuItem(
                                          value: v,
                                          child: Text('yesno_$v'.tr),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => _registeredSocialWelfare = v,
                                    ),
                                  ),
                                ],
                              ),
                              ..._unlessHidden(
                                'recipient_registered_unemployed',
                                [
                                  const SizedBox(height: 16),
                                  _label(
                                    context,
                                    'reg_recipient_registered_unemployed',
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _registeredUnemployed,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.work_off_outlined),
                                    ),
                                    hint: Text(
                                      'reg_recipient_registered_unemployed_hint'
                                          .tr,
                                    ),
                                    items: [
                                      for (final v in const ['yes', 'no'])
                                        DropdownMenuItem(
                                          value: v,
                                          child: Text('yesno_$v'.tr),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => _registeredUnemployed = v,
                                    ),
                                  ),
                                ],
                              ),
                              for (final f
                                  in <
                                        ({
                                          String rule,
                                          String label,
                                          TextEditingController controller,
                                          IconData icon,
                                        })
                                      >[
                                        (
                                          rule: 'recipient_household_employees',
                                          label:
                                              'reg_recipient_household_employees',
                                          controller:
                                              _householdEmployeesController,
                                          icon: Icons.badge_outlined,
                                        ),
                                        (
                                          rule: 'recipient_working_members',
                                          label:
                                              'reg_recipient_working_members',
                                          controller: _workingMembersController,
                                          icon: Icons.engineering_outlined,
                                        ),
                                        (
                                          rule: 'recipient_men_count',
                                          label: 'reg_recipient_men_count',
                                          controller: _menCountController,
                                          icon: Icons.man_outlined,
                                        ),
                                        (
                                          rule: 'recipient_women_count',
                                          label: 'reg_recipient_women_count',
                                          controller: _womenCountController,
                                          icon: Icons.woman_outlined,
                                        ),
                                        (
                                          rule: 'recipient_male_children_count',
                                          label:
                                              'reg_recipient_male_children_count',
                                          controller: _maleChildrenController,
                                          icon: Icons.boy_outlined,
                                        ),
                                        (
                                          rule:
                                              'recipient_female_children_count',
                                          label:
                                              'reg_recipient_female_children_count',
                                          controller: _femaleChildrenController,
                                          icon: Icons.girl_outlined,
                                        ),
                                        (
                                          rule: 'recipient_age_0_5_count',
                                          label: 'reg_recipient_age_0_5',
                                          controller: _age0To5Controller,
                                          icon: Icons.child_care_outlined,
                                        ),
                                        (
                                          rule: 'recipient_age_5_10_count',
                                          label: 'reg_recipient_age_5_10',
                                          controller: _age5To10Controller,
                                          icon: Icons.child_care_outlined,
                                        ),
                                        (
                                          rule: 'recipient_age_10_15_count',
                                          label: 'reg_recipient_age_10_15',
                                          controller: _age10To15Controller,
                                          icon:
                                              Icons.escalator_warning_outlined,
                                        ),
                                        (
                                          rule: 'recipient_age_15_25_count',
                                          label: 'reg_recipient_age_15_25',
                                          controller: _age15To25Controller,
                                          icon: Icons.person_outline,
                                        ),
                                        (
                                          rule: 'recipient_age_25_40_count',
                                          label: 'reg_recipient_age_25_40',
                                          controller: _age25To40Controller,
                                          icon: Icons.person_outline,
                                        ),
                                        (
                                          rule: 'recipient_age_40_plus_count',
                                          label: 'reg_recipient_age_40_plus',
                                          controller: _age40PlusController,
                                          icon: Icons.elderly_outlined,
                                        ),
                                        (
                                          rule: 'recipient_students_count',
                                          label: 'reg_recipient_students_count',
                                          controller: _studentsCountController,
                                          icon: Icons.school_outlined,
                                        ),
                                        (
                                          rule: 'recipient_orphans_count',
                                          label: 'reg_recipient_orphans_count',
                                          controller: _orphansCountController,
                                          icon: Icons.family_restroom_outlined,
                                        ),
                                        (
                                          rule: 'recipient_widows_count',
                                          label: 'reg_recipient_widows_count',
                                          controller: _widowsCountController,
                                          icon: Icons.person_outline,
                                        ),
                                        (
                                          rule: 'recipient_divorced_count',
                                          label: 'reg_recipient_divorced_count',
                                          controller: _divorcedCountController,
                                          icon: Icons.person_remove_outlined,
                                        ),
                                      ]
                                      .where((f) => !_isHidden(f.rule))) ...[
                                const SizedBox(height: 16),
                                _label(context, f.label),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: f.controller,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: '${f.label}_hint'.tr,
                                    prefixIcon: Icon(f.icon),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Health Information".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_health_section'),
                              ..._unlessHidden('recipient_height', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_recipient_height'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _heightController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_recipient_height_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.height_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_weight', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_weight'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _weightController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_recipient_weight_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.monitor_weight_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_smoking_status', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_smoking_status'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _smokingStatus,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.smoking_rooms_outlined,
                                    ),
                                  ),
                                  hint: Text(
                                    'reg_recipient_smoking_status_hint'.tr,
                                  ),
                                  items: [
                                    for (final s in const [
                                      'non_smoker',
                                      'smoker',
                                      'former',
                                    ])
                                      DropdownMenuItem(
                                        value: s,
                                        child: Text('smoking_$s'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _smokingStatus = v),
                                ),
                              ]),
                              ..._unlessHidden('recipient_eyesight_condition', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_eyesight_condition',
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _eyesightCondition,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.visibility_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_eyesight_condition_hint'.tr,
                                  ),
                                  items: [
                                    for (final e in const [
                                      'normal',
                                      'glasses',
                                      'weak',
                                      'blind',
                                    ])
                                      DropdownMenuItem(
                                        value: e,
                                        child: Text('eyesight_$e'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _eyesightCondition = v),
                                ),
                              ]),
                              ..._unlessHidden('recipient_has_disability', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_has_disability'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _hasDisability,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.accessible_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_has_disability_hint'.tr,
                                  ),
                                  items: [
                                    for (final v in const ['yes', 'no'])
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text('yesno_$v'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _hasDisability = v),
                                ),
                              ]),
                              if (_hasDisability == 'yes' &&
                                  !_isHidden('recipient_disability_type')) ...[
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_disability_type',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _disabilityTypeController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_disability_type_hint'.tr,
                                    prefixIcon: const Icon(Icons.info_outline),
                                  ),
                                ),
                              ],
                              ..._unlessHidden('recipient_household_disabled', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_household_disabled',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _householdDisabledController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_household_disabled_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.accessible_forward_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_chronic_illnesses', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_chronic_illnesses',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _chronicIllnessesController,
                                  minLines: 1,
                                  maxLines: 3,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_chronic_illnesses_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.medical_information_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden(
                                'recipient_medical_conditions_count',
                                [
                                  const SizedBox(height: 16),
                                  _label(
                                    context,
                                    'reg_recipient_medical_conditions_count',
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller:
                                        _medicalConditionsCountController,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText:
                                          'reg_recipient_medical_conditions_count_hint'
                                              .tr,
                                      prefixIcon: const Icon(
                                        Icons.numbers_outlined,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ..._unlessHidden(
                                'recipient_medical_conditions_desc',
                                [
                                  const SizedBox(height: 16),
                                  _label(
                                    context,
                                    'reg_recipient_medical_conditions_desc',
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller:
                                        _medicalConditionsDescController,
                                    minLines: 2,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.newline,
                                    decoration: InputDecoration(
                                      hintText:
                                          'reg_recipient_medical_conditions_desc_hint'
                                              .tr,
                                      prefixIcon: const Icon(
                                        Icons.notes_outlined,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Attachments". Personal
                        // photo and National Card photo reuse the same
                        // columns/pickers as the grantor form.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_recipient_attachments_section',
                              ),
                              for (final a
                                  in <
                                        ({
                                          String rule,
                                          String label,
                                          String? path,
                                          IconData icon,
                                          void Function(String) assign,
                                        })
                                      >[
                                        (
                                          rule: 'recipient_personal_photo',
                                          label: 'reg_recipient_personal_photo',
                                          path: _personalPhotoPath,
                                          icon: Icons.person_outline,
                                          assign: (p) => _personalPhotoPath = p,
                                        ),
                                        (
                                          rule: 'recipient_id_photo',
                                          label: 'reg_recipient_id_photo',
                                          path: _idPhotoPath,
                                          icon: Icons.badge_outlined,
                                          assign: (p) => _idPhotoPath = p,
                                        ),
                                        (
                                          rule: 'recipient_ration_card_photo',
                                          label:
                                              'reg_recipient_ration_card_photo',
                                          path: _rationCardPhotoPath,
                                          icon: Icons.credit_card_outlined,
                                          assign: (p) =>
                                              _rationCardPhotoPath = p,
                                        ),
                                        (
                                          rule:
                                              'recipient_property_proof_photo',
                                          label:
                                              'reg_recipient_property_proof_photo',
                                          path: _propertyProofPhotoPath,
                                          icon: Icons.description_outlined,
                                          assign: (p) =>
                                              _propertyProofPhotoPath = p,
                                        ),
                                        (
                                          rule:
                                              'recipient_medical_report_photo',
                                          label:
                                              'reg_recipient_medical_report_photo',
                                          path: _medicalReportPhotoPath,
                                          icon: Icons.medical_services_outlined,
                                          assign: (p) =>
                                              _medicalReportPhotoPath = p,
                                        ),
                                        (
                                          rule: 'recipient_house_facade_photo',
                                          label:
                                              'reg_recipient_house_facade_photo',
                                          path: _houseFacadePhotoPath,
                                          icon: Icons.home_outlined,
                                          assign: (p) =>
                                              _houseFacadePhotoPath = p,
                                        ),
                                        (
                                          rule: 'recipient_house_inside_photo',
                                          label:
                                              'reg_recipient_house_inside_photo',
                                          path: _houseInsidePhotoPath,
                                          icon: Icons.chair_outlined,
                                          assign: (p) =>
                                              _houseInsidePhotoPath = p,
                                        ),
                                        (
                                          rule: 'recipient_house_outside_photo',
                                          label:
                                              'reg_recipient_house_outside_photo',
                                          path: _houseOutsidePhotoPath,
                                          icon: Icons.yard_outlined,
                                          assign: (p) =>
                                              _houseOutsidePhotoPath = p,
                                        ),
                                      ]
                                      .where((a) => !_isHidden(a.rule))) ...[
                                const SizedBox(height: 16),
                                _label(context, a.label),
                                const SizedBox(height: 6),
                                _PhotoPickerTile(
                                  imagePath: a.path,
                                  placeholderIcon: a.icon,
                                  onTap: () => _pickPhotoInto(a.assign),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Assets" and "Needs".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_assets_section'),
                              ..._unlessHidden('recipient_available_furniture', [
                                const SizedBox(height: 12),
                                _label(
                                  context,
                                  'reg_recipient_available_furniture',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _availableFurnitureController,
                                  minLines: 1,
                                  maxLines: 3,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_available_furniture_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.chair_alt_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('recipient_owns_car', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_owns_car'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _ownsCar,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.directions_car_outlined,
                                    ),
                                  ),
                                  hint: Text('reg_recipient_owns_car_hint'.tr),
                                  items: [
                                    for (final v in const ['yes', 'no'])
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text('yesno_$v'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _ownsCar = v),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_needs_section'),
                              ..._unlessHidden('recipient_needs_description', [
                                const SizedBox(height: 12),
                                _label(
                                  context,
                                  'reg_recipient_needs_description',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _needsDescriptionController,
                                  minLines: 3,
                                  maxLines: 6,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_needs_description_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.volunteer_activism_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Social Media Accounts".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_recipient_social_accounts_section',
                              ),
                              for (final s
                                  in <
                                        ({
                                          String rule,
                                          String label,
                                          TextEditingController controller,
                                          IconData icon,
                                        })
                                      >[
                                        (
                                          rule: 'recipient_social_facebook',
                                          label:
                                              'reg_recipient_social_facebook',
                                          controller: _socialFacebookController,
                                          icon: Icons.facebook_outlined,
                                        ),
                                        (
                                          rule: 'recipient_social_instagram',
                                          label:
                                              'reg_recipient_social_instagram',
                                          controller:
                                              _socialInstagramController,
                                          icon: Icons.camera_alt_outlined,
                                        ),
                                        (
                                          rule: 'recipient_social_telegram',
                                          label:
                                              'reg_recipient_social_telegram',
                                          controller: _socialTelegramController,
                                          icon: Icons.send_outlined,
                                        ),
                                      ]
                                      .where((s) => !_isHidden(s.rule))) ...[
                                const SizedBox(height: 16),
                                _label(context, s.label),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: s.controller,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: '${s.label}_hint'.tr,
                                    prefixIcon: Icon(s.icon),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Eligible Recipient spec — "Privacy". Consent to what
                        // a grantor may see; also editable later from the
                        // Privacy Settings screen.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_recipient_privacy_section'),
                              const SizedBox(height: 8),
                              Text(
                                'reg_recipient_privacy_note'.tr,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: AppThemeConfig.mutedText(context),
                                ),
                              ),
                              ..._unlessHidden(
                                'recipient_consent_show_real_name',
                                [
                                  const SizedBox(height: 16),
                                  _label(
                                    context,
                                    'reg_recipient_consent_show_real_name',
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _consentShowRealName,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    hint: Text(
                                      'reg_recipient_consent_show_real_name_hint'
                                          .tr,
                                    ),
                                    items: [
                                      for (final v in const ['yes', 'no'])
                                        DropdownMenuItem(
                                          value: v,
                                          child: Text('yesno_$v'.tr),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => _consentShowRealName = v,
                                    ),
                                  ),
                                ],
                              ),
                              ..._unlessHidden('recipient_consent_share_info', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_consent_share_info',
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _consentShareInfo,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.privacy_tip_outlined,
                                    ),
                                  ),
                                  hint: Text(
                                    'reg_recipient_consent_share_info_hint'.tr,
                                  ),
                                  items: [
                                    for (final v in const ['yes', 'no'])
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text('yesno_$v'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _consentShareInfo = v),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_eligible_section'),
                              ..._unlessHidden('family_size', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_family_size'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _familySizeController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_family_size_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.group_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('housing_status', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_housing'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _housingStatus,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.home_outlined),
                                  ),
                                  hint: Text('reg_housing_hint'.tr),
                                  items: [
                                    for (final h in const [
                                      'owned',
                                      'rented',
                                      'hosted',
                                      'displaced',
                                    ])
                                      DropdownMenuItem(
                                        value: h,
                                        child: Text('housing_$h'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _housingStatus = v),
                                ),
                              ]),
                              ..._unlessHidden('monthly_income', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_income'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _incomeController,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    hintText: 'reg_income_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.payments_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                      // #41 — volunteer/employee sign-up: extra fields.
                      if (_roleId == 3) ...[
                        // Volunteer/Employee spec — "Identification
                        // Information". The identification code is generated
                        // server-side on submit, so it's shown as a note
                        // rather than an editable field.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_volunteer_identification_section',
                              ),
                              const SizedBox(height: 12),
                              _label(context, 'reg_volunteer_code'),
                              const SizedBox(height: 6),
                              Text(
                                'reg_volunteer_code_auto'.tr,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppThemeConfig.mutedText(context),
                                ),
                              ),
                              ..._unlessHidden('volunteer_national_id', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_volunteer_national_id'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nationalIdController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_volunteer_national_id_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_name_parts', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_volunteer_name_parts'),
                                for (final n
                                    in <
                                      ({
                                        String label,
                                        TextEditingController controller,
                                      })
                                    >[
                                      (
                                        label: 'reg_grantor_name_first_hint',
                                        controller: _nameFirstController,
                                      ),
                                      (
                                        label: 'reg_grantor_name_father_hint',
                                        controller: _nameFatherController,
                                      ),
                                      (
                                        label:
                                            'reg_grantor_name_grandfather_hint',
                                        controller: _nameGrandfatherController,
                                      ),
                                      (
                                        label: 'reg_grantor_name_family_hint',
                                        controller: _nameFamilyController,
                                      ),
                                    ]) ...[
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: n.controller,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText: n.label.tr,
                                      prefixIcon: const Icon(
                                        Icons.person_outline,
                                      ),
                                    ),
                                  ),
                                ],
                              ]),
                              ..._unlessHidden('volunteer_tribe_clan', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_volunteer_tribe_clan'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _tribeClanController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_volunteer_tribe_clan_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.groups_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_title_surname', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_volunteer_title_surname'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _titleSurnameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_volunteer_title_surname_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.title_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Contact Information".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_volunteer_contact_section'),
                              for (final ct
                                  in <
                                        ({
                                          String rule,
                                          String label,
                                          TextEditingController controller,
                                          IconData icon,
                                          TextInputType keyboard,
                                        })
                                      >[
                                        (
                                          rule: 'volunteer_phone1',
                                          label: 'reg_volunteer_phone1',
                                          controller: _phone1Controller,
                                          icon: Icons.phone_outlined,
                                          keyboard: TextInputType.phone,
                                        ),
                                        (
                                          rule: 'volunteer_phone2',
                                          label: 'reg_volunteer_phone2',
                                          controller: _phone2Controller,
                                          icon: Icons.phone_android_outlined,
                                          keyboard: TextInputType.phone,
                                        ),
                                        (
                                          rule: 'volunteer_emergency_phone',
                                          label:
                                              'reg_volunteer_emergency_phone',
                                          controller: _emergencyPhoneController,
                                          icon: Icons.emergency_outlined,
                                          keyboard: TextInputType.phone,
                                        ),
                                        (
                                          rule: 'volunteer_email',
                                          label: 'reg_volunteer_email',
                                          controller: _emailController,
                                          icon: Icons.email_outlined,
                                          keyboard: TextInputType.emailAddress,
                                        ),
                                      ]
                                      .where((ct) => !_isHidden(ct.rule))) ...[
                                const SizedBox(height: 16),
                                _label(context, ct.label),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: ct.controller,
                                  keyboardType: ct.keyboard,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: '${ct.label}_hint'.tr,
                                    prefixIcon: Icon(ct.icon),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Personal Information".
                        // Date of birth and gender are collected in the shared
                        // section above and not repeated here.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_volunteer_personal_section'),
                              ..._unlessHidden('volunteer_nationality', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_recipient_nationality'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _nationality,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.flag_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_nationality_hint'.tr,
                                  ),
                                  items: [
                                    for (final n in const [
                                      'iraqi',
                                      'syrian',
                                      'egyptian',
                                      'gulf',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: n,
                                        child: Text('nationality_$n'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _nationality = v),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_languages', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_volunteer_languages'),
                                const SizedBox(height: 6),
                                for (final lang in volunteerLanguages)
                                  CheckboxListTile(
                                    value: _languages.contains(lang),
                                    onChanged: (checked) => setState(() {
                                      if (checked == true) {
                                        _languages.add(lang);
                                      } else {
                                        _languages.remove(lang);
                                      }
                                    }),
                                    title: Text('language_$lang'.tr),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  ),
                              ]),
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Housing Information".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_volunteer_housing_section'),
                              ..._unlessHidden('volunteer_governorate', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_grantor_governorate'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _governorate,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.map_outlined),
                                  ),
                                  hint: Text('reg_grantor_governorate_hint'.tr),
                                  items: [
                                    for (final g in iraqGovernorates)
                                      DropdownMenuItem(
                                        value: g,
                                        child: Text(g.tr),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _governorate = v;
                                    // Switching governorate invalidates the
                                    // Nineveh-only district/side/neighborhood.
                                    _district = null;
                                    _housingSide = null;
                                    _neighborhoodDropdown = null;
                                  }),
                                ),
                              ]),
                              // Nineveh opens the district picker, then the
                              // side, then the side's neighborhoods.
                              if (_governorate == 'Nineveh') ...[
                                ..._unlessHidden('volunteer_district', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_volunteer_district'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _district,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.location_on_outlined,
                                      ),
                                    ),
                                    hint: Text(
                                      'reg_volunteer_district_hint'.tr,
                                    ),
                                    items: [
                                      for (final d in ninevehDistricts)
                                        DropdownMenuItem(
                                          value: d,
                                          child: Text(d),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _district = v),
                                  ),
                                ]),
                                ..._unlessHidden('volunteer_housing_side', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_housing_side'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _housingSide,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.swap_horiz_rounded,
                                      ),
                                    ),
                                    hint: Text(
                                      'reg_recipient_housing_side_hint'.tr,
                                    ),
                                    items: [
                                      for (final sd in const [
                                        'right',
                                        'left',
                                        'other',
                                      ])
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
                                ]),
                                ..._unlessHidden('volunteer_neighborhood', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_neighborhood'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _neighborhoodDropdown,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.location_city_outlined,
                                      ),
                                    ),
                                    hint: Text(
                                      'reg_recipient_neighborhood_hint'.tr,
                                    ),
                                    items: [
                                      for (final n
                                          in _housingSide == 'left'
                                              ? ninevehLeftSideNeighborhoods
                                              : ninevehRightSideNeighborhoods)
                                        DropdownMenuItem(
                                          value: n,
                                          child: Text(n),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => _neighborhoodDropdown = v,
                                    ),
                                  ),
                                ]),
                              ] else ...[
                                ..._unlessHidden('volunteer_neighborhood', [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_recipient_neighborhood'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _neighborhoodController,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText:
                                          'reg_recipient_neighborhood_free_hint'
                                              .tr,
                                      prefixIcon: const Icon(
                                        Icons.location_city_outlined,
                                      ),
                                    ),
                                  ),
                                ]),
                              ],
                              ..._unlessHidden('volunteer_nearest_landmark', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_nearest_landmark',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _nearestLandmarkController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_nearest_landmark_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.place_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_housing_type', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_housing_type'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _housingType,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.house_outlined),
                                  ),
                                  hint: Text(
                                    'reg_recipient_housing_type_hint'.tr,
                                  ),
                                  items: [
                                    // Volunteer spec lists: owned, rented,
                                    // shared, inherited, other.
                                    for (final h in const [
                                      'owned',
                                      'rented',
                                      'shared',
                                      'inherited',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: h,
                                        child: Text('housing_type_$h'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _housingType = v),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_housing_area', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_recipient_housing_area'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _housingAreaController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_housing_area_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.square_foot_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_family_size', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_family_size'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      _familySizeController.text.trim().isEmpty
                                      ? null
                                      : _familySizeController.text.trim(),
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.group_outlined),
                                  ),
                                  hint: Text('reg_family_size_hint'.tr),
                                  items: [
                                    for (var i = 1; i <= 20; i++)
                                      DropdownMenuItem(
                                        value: '$i',
                                        child: Text(i == 20 ? '20+' : '$i'),
                                      ),
                                  ],
                                  onChanged: (v) => setState(
                                    () => _familySizeController.text = v ?? '',
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_gps_location', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_grantor_gps_location'),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: _gpsLoading
                                      ? null
                                      : _captureGpsLocation,
                                  icon: _gpsLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location_rounded),
                                  label: Text(
                                    _gpsLat == null
                                        ? 'reg_grantor_gps_capture'.tr
                                        : '${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)}',
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Social Information".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_volunteer_social_section'),
                              ..._unlessHidden('volunteer_marital_status', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_recipient_marital_status'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _maritalStatus,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.favorite_outline),
                                  ),
                                  hint: Text(
                                    'reg_recipient_marital_status_hint'.tr,
                                  ),
                                  items: [
                                    for (final m in const [
                                      'single',
                                      'engaged',
                                      'married',
                                      'separated',
                                      'widowed',
                                      'divorced',
                                      'other',
                                    ])
                                      DropdownMenuItem(
                                        value: m,
                                        child: Text('marital_$m'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _maritalStatus = v),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Educational and
                        // Professional Information". Current occupation is
                        // collected in the shared section above; skills and
                        // experience keep their existing panel below.
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_volunteer_education_section',
                              ),
                              ..._unlessHidden('volunteer_education_level', [
                                const SizedBox(height: 12),
                                _label(context, 'reg_grantor_education_level'),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _educationLevel,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.school_outlined),
                                  ),
                                  hint: Text(
                                    'reg_grantor_education_level_hint'.tr,
                                  ),
                                  items: [
                                    for (final e in const [
                                      'none',
                                      'primary',
                                      'secondary',
                                      'diploma',
                                      'bachelor',
                                      'master',
                                      'phd',
                                    ])
                                      DropdownMenuItem(
                                        value: e,
                                        child: Text('education_$e'.tr),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _educationLevel = v),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_other_certificate', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_other_certificate',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _otherCertificateController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_other_certificate_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.workspace_premium_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHidden('volunteer_previous_occupation', [
                                const SizedBox(height: 16),
                                _label(
                                  context,
                                  'reg_recipient_previous_occupation',
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _previousOccupationController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText:
                                        'reg_recipient_previous_occupation_hint'
                                            .tr,
                                    prefixIcon: const Icon(
                                      Icons.history_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Attachments".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_volunteer_attachments_section',
                              ),
                              for (final a
                                  in <
                                        ({
                                          String rule,
                                          String label,
                                          String? path,
                                          IconData icon,
                                          void Function(String) assign,
                                        })
                                      >[
                                        (
                                          rule: 'volunteer_golden_square_photo',
                                          label:
                                              'reg_volunteer_golden_square_photo',
                                          path: _goldenSquarePhotoPath,
                                          icon:
                                              Icons.workspace_premium_outlined,
                                          assign: (p) =>
                                              _goldenSquarePhotoPath = p,
                                        ),
                                        (
                                          rule: 'volunteer_id_photo',
                                          label: 'reg_volunteer_id_photo_doc',
                                          path: _idPhotoPath,
                                          icon: Icons.badge_outlined,
                                          assign: (p) => _idPhotoPath = p,
                                        ),
                                        (
                                          rule: 'volunteer_ration_card_photo',
                                          label:
                                              'reg_volunteer_ration_card_photo',
                                          path: _rationCardPhotoPath,
                                          icon: Icons.credit_card_outlined,
                                          assign: (p) =>
                                              _rationCardPhotoPath = p,
                                        ),
                                        (
                                          rule:
                                              'volunteer_residence_card_photo',
                                          label:
                                              'reg_volunteer_residence_card_photo',
                                          path: _residenceCardPhotoPath,
                                          icon: Icons.home_work_outlined,
                                          assign: (p) =>
                                              _residenceCardPhotoPath = p,
                                        ),
                                        (
                                          rule: 'volunteer_passport_photo',
                                          label: 'reg_volunteer_passport_photo',
                                          path: _passportPhotoPath,
                                          icon: Icons.book_outlined,
                                          assign: (p) => _passportPhotoPath = p,
                                        ),
                                        (
                                          rule: 'volunteer_personal_photo',
                                          label: 'reg_volunteer_personal_photo',
                                          path: _personalPhotoPath,
                                          icon: Icons.person_outline,
                                          assign: (p) => _personalPhotoPath = p,
                                        ),
                                        (
                                          rule:
                                              'volunteer_graduation_cert_photo',
                                          label:
                                              'reg_volunteer_graduation_cert_photo',
                                          path: _graduationCertPhotoPath,
                                          icon: Icons.school_outlined,
                                          assign: (p) =>
                                              _graduationCertPhotoPath = p,
                                        ),
                                        (
                                          rule: 'volunteer_cv_photo',
                                          label: 'reg_volunteer_cv_photo',
                                          path: _cvPhotoPath,
                                          icon: Icons.description_outlined,
                                          assign: (p) => _cvPhotoPath = p,
                                        ),
                                      ]
                                      .where((a) => !_isHidden(a.rule))) ...[
                                const SizedBox(height: 16),
                                _label(context, a.label),
                                const SizedBox(height: 6),
                                _PhotoPickerTile(
                                  imagePath: a.path,
                                  placeholderIcon: a.icon,
                                  onTap: () => _pickPhotoInto(a.assign),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Volunteer/Employee spec — "Social Media Accounts".
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(
                                context,
                                'reg_volunteer_social_accounts_section',
                              ),
                              for (final sm
                                  in <
                                        ({
                                          String rule,
                                          String label,
                                          TextEditingController controller,
                                          IconData icon,
                                        })
                                      >[
                                        (
                                          rule: 'volunteer_social_facebook',
                                          label:
                                              'reg_recipient_social_facebook',
                                          controller: _socialFacebookController,
                                          icon: Icons.facebook_outlined,
                                        ),
                                        (
                                          rule: 'volunteer_social_instagram',
                                          label:
                                              'reg_recipient_social_instagram',
                                          controller:
                                              _socialInstagramController,
                                          icon: Icons.camera_alt_outlined,
                                        ),
                                        (
                                          rule: 'volunteer_social_telegram',
                                          label:
                                              'reg_recipient_social_telegram',
                                          controller: _socialTelegramController,
                                          icon: Icons.send_outlined,
                                        ),
                                        (
                                          rule: 'volunteer_social_other',
                                          label: 'reg_volunteer_social_other',
                                          controller: _socialOtherController,
                                          icon: Icons.link_outlined,
                                        ),
                                      ]
                                      .where((sm) => !_isHidden(sm.rule))) ...[
                                const SizedBox(height: 16),
                                _label(context, sm.label),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: sm.controller,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: '${sm.label}_hint'.tr,
                                    prefixIcon: Icon(sm.icon),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GlassPanel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, 'reg_volunteer_section'),
                              ..._unlessHiddenAny(
                                const ['skills', 'volunteer_skills'],
                                [
                                  const SizedBox(height: 12),
                                  _label(context, 'reg_skills'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _skillsController,
                                    minLines: 1,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText: 'reg_skills_hint'.tr,
                                      prefixIcon: const Icon(
                                        Icons.star_outline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ..._unlessHidden('availability', [
                                const SizedBox(height: 16),
                                _label(context, 'reg_availability'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _availabilityController,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    hintText: 'reg_availability_hint'.tr,
                                    prefixIcon: const Icon(
                                      Icons.schedule_outlined,
                                    ),
                                  ),
                                ),
                              ]),
                              ..._unlessHiddenAny(
                                const ['experience', 'volunteer_experience'],
                                [
                                  const SizedBox(height: 16),
                                  _label(context, 'reg_experience'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _experience,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    hint: Text('reg_experience_hint'.tr),
                                    items: [
                                      for (final e in const [
                                        'none',
                                        'lt1',
                                        'y1to3',
                                        'gt3',
                                      ])
                                        DropdownMenuItem(
                                          value: e,
                                          child: Text('exp_$e'.tr),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _experience = v),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      // E4 — was a hardcoded `Colors.redAccent`, 3.19:1 on this
                      // card and illegible in dark mode. Same widget, same
                      // token as the rest of the sign-in flow.
                      AuthInlineError(
                        message: _error ?? '',
                        padding: const EdgeInsets.only(top: 16),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Checkbox(
                              value: _agreeToTerms,
                              onChanged: (v) =>
                                  setState(() => _agreeToTerms = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AppPressable(
                              onTap: () => Get.to(() => const TermsScreen()),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      color: AppThemeConfig.mutedText(context),
                                      fontSize: 13.5,
                                    ),
                                    children: [
                                      TextSpan(text: 'I agree to the '.tr),
                                      TextSpan(
                                        text: 'Terms & Conditions'.tr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          decoration: TextDecoration.underline,
                                          color: AppThemeConfig.text(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: Text('Submit for approval'.tr),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_loading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text.tr,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: AppThemeConfig.mutedText(context),
    ),
  );
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.tagline,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String tagline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppThemeConfig.primary
                  : AppThemeConfig.border(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? AppThemeConfig.primary
                    : AppThemeConfig.mutedText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grantor registration spec — a tappable square preview for the optional
/// personal photo / ID card photo attachments.
class _PhotoPickerTile extends StatelessWidget {
  const _PhotoPickerTile({
    required this.imagePath,
    required this.placeholderIcon,
    required this.onTap,
  });

  final String? imagePath;
  final IconData placeholderIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 96,
        width: 96,
        decoration: BoxDecoration(
          color: AppThemeConfig.softSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeConfig.border(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: imagePath == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    placeholderIcon,
                    color: AppThemeConfig.mutedText(context),
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: AppThemeConfig.mutedText(context),
                    size: 16,
                  ),
                ],
              )
            : Image.file(File(imagePath!), fit: BoxFit.cover),
      ),
    );
  }
}
