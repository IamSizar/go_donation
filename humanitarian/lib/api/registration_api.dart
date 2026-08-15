import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:http/http.dart' as http;

/// #43 — the set of optional registration field keys the admin marked required.
/// Empty on error/offline (so the form falls back to its baseline validation).
Future<Set<String>> fetchRequiredFields() async {
  return (await fetchFieldRuleSets()).required;
}

/// Result of GET /api/registration/field-rules: which optional fields the
/// admin marked required, and which the admin marked hidden entirely.
class FieldRuleSets {
  const FieldRuleSets({
    required this.required,
    required this.hidden,
    this.searchable = const {},
  });
  final Set<String> required;
  final Set<String> hidden;
  // Client note — Marriage "Search": which fields staff enabled as filters.
  final Set<String> searchable;
  static const empty = FieldRuleSets(required: {}, hidden: {});
}

/// Note #33 — like fetchRequiredFields, but also returns the `hidden` list so
/// a form can skip rendering fields the admin switched off entirely. Empty on
/// error/offline (so forms fall back to showing every field, none required).
Future<FieldRuleSets> fetchFieldRuleSets() async {
  try {
    final resp = await http.get(
      Uri.parse(fieldRulesUrl),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return FieldRuleSets.empty;
    final decoded = jsonDecode(resp.body);
    if (decoded is Map) {
      final required = decoded['required'] is List
          ? (decoded['required'] as List).map((e) => e.toString()).toSet()
          : <String>{};
      final hidden = decoded['hidden'] is List
          ? (decoded['hidden'] as List).map((e) => e.toString()).toSet()
          : <String>{};
      final searchable = decoded['searchable'] is List
          ? (decoded['searchable'] as List).map((e) => e.toString()).toSet()
          : <String>{};
      return FieldRuleSets(
        required: required,
        hidden: hidden,
        searchable: searchable,
      );
    }
  } catch (_) {
    // DELIBERATE, same class as ModuleApi.getDonationOptions(): these are
    // admin FORM-CONFIG flags, not the user's data. Falling back to empty
    // means "show every field, require none", i.e. the plain registration
    // form — which tells the user nothing untrue about themselves. The server
    // remains the authority on what is actually required, so a wrongly-lenient
    // client still gets a real, reportable error on submit rather than a
    // silently wrong save. Deliberately not a throw: this feeds the signup
    // form, and failing it would lock a new user out over a config fetch.
  }
  return FieldRuleSets.empty;
}

/// Result of POSTing the registration form.
class RegistrationSubmitResult {
  RegistrationSubmitResult({required this.ok, this.status, this.error});

  final bool ok;
  final String? status; // server's resulting registration_status
  final String? error;
}

/// Submits the new-user registration form (name / date of birth / address /
/// role). On success the resulting `registration_status` ("pending", or
/// "approved" for a grandfathered account completing its role) is persisted to
/// prefs so the splash/router can react.
Future<RegistrationSubmitResult> submitRegistration({
  required String fullName,
  required String dateOfBirth, // "YYYY-MM-DD" or ""
  required String address,
  required int roleId,
  String gender = '', // #39 — optional fuller sign-up fields
  String city = '',
  String occupation = '',
  String familySize = '', // #40 — eligible fields
  String housingStatus = '',
  String monthlyIncome = '',
  String skills = '', // #41 — volunteer fields
  String availability = '',
  String experience = '',
  // Grantor registration spec — additional grantor-only detail fields.
  String nationalId = '',
  String nameFirst = '',
  String nameFather = '',
  String nameGrandfather = '',
  String nameFamily = '',
  String titleSurname = '',
  String phone1 = '',
  String phone2 = '',
  String email = '',
  double? gpsLat,
  double? gpsLng,
  String governorate = '',
  String educationLevel = '',
  // Eligible Recipient registration spec — beneficiary-only detail fields.
  String tribeClan = '',
  String emergencyPhone = '',
  String nationality = '',
  String maritalStatus = '',
  String residencyStatus = '',
  // Eligible Recipient registration spec — "Housing Information" section.
  String housingSide = '',
  String neighborhood = '',
  String nearestLandmark = '',
  String housingType = '',
  String rentalAmount = '',
  String housingArea = '',
  String floorsCount = '',
  String roomsCount = '',
  String familiesCount = '',
  // Eligible Recipient registration spec — "Educational and Employment
  // Information", "Employment Status", and "Social Information" sections.
  String otherCertificate = '',
  String certificatesCount = '',
  String previousOccupation = '',
  String jobDescription = '',
  String workingHours = '',
  String isEmployed = '',
  String workplace = '',
  String wageAmount = '',
  String registeredSocialWelfare = '',
  String registeredUnemployed = '',
  String householdEmployeesCount = '',
  String workingMembersCount = '',
  String menCount = '',
  String womenCount = '',
  String maleChildrenCount = '',
  String femaleChildrenCount = '',
  String age0To5Count = '',
  String age5To10Count = '',
  String age10To15Count = '',
  String age15To25Count = '',
  String age25To40Count = '',
  String age40PlusCount = '',
  String studentsCount = '',
  String orphansCount = '',
  String widowsCount = '',
  String divorcedCount = '',
  // Eligible Recipient registration spec — "Health Information", "Assets",
  // "Needs", and "Social Media Accounts" sections.
  String height = '',
  String weight = '',
  String smokingStatus = '',
  String eyesightCondition = '',
  String hasDisability = '',
  String disabilityType = '',
  String householdDisabledCount = '',
  String chronicIllnesses = '',
  String medicalConditionsCount = '',
  String medicalConditionsDesc = '',
  String availableFurniture = '',
  String ownsCar = '',
  String needsDescription = '',
  String socialFacebook = '',
  String socialInstagram = '',
  String socialTelegram = '',
  // Eligible Recipient registration spec — "Privacy" consent section.
  String consentShowRealName = '',
  String consentShareInfo = '',
  // Volunteer/Employee registration spec — Personal / Housing / Social Media.
  String languages = '',
  String district = '',
  String socialOther = '',
}) async {
  try {
    final resp = await http.post(
      Uri.parse(registrationSubmitUrl),
      headers: withApiAuthHeaders({'Content-Type': 'application/json'}),
      body: jsonEncode(
        withApiAuthJsonBody({
          'full_name': fullName,
          'date_of_birth': dateOfBirth,
          'address': address,
          'role_id': roleId,
          'gender': gender,
          'city': city,
          'occupation': occupation,
          'family_size': familySize,
          'housing_status': housingStatus,
          'monthly_income': monthlyIncome,
          'skills': skills,
          'availability': availability,
          'experience': experience,
          'national_id': nationalId,
          'name_first': nameFirst,
          'name_father': nameFather,
          'name_grandfather': nameGrandfather,
          'name_family': nameFamily,
          'title_surname': titleSurname,
          'phone1': phone1,
          'phone2': phone2,
          'email': email,
          if (gpsLat != null) 'gps_lat': gpsLat,
          if (gpsLng != null) 'gps_lng': gpsLng,
          'governorate': governorate,
          'education_level': educationLevel,
          'tribe_clan': tribeClan,
          'emergency_phone': emergencyPhone,
          'nationality': nationality,
          'marital_status': maritalStatus,
          'residency_status': residencyStatus,
          'housing_side': housingSide,
          'neighborhood': neighborhood,
          'nearest_landmark': nearestLandmark,
          'housing_type': housingType,
          'rental_amount': rentalAmount,
          'housing_area': housingArea,
          'floors_count': floorsCount,
          'rooms_count': roomsCount,
          'families_count': familiesCount,
          'other_certificate': otherCertificate,
          'certificates_count': certificatesCount,
          'previous_occupation': previousOccupation,
          'job_description': jobDescription,
          'working_hours': workingHours,
          'is_employed': isEmployed,
          'workplace': workplace,
          'wage_amount': wageAmount,
          'registered_social_welfare': registeredSocialWelfare,
          'registered_unemployed': registeredUnemployed,
          'household_employees_count': householdEmployeesCount,
          'working_members_count': workingMembersCount,
          'men_count': menCount,
          'women_count': womenCount,
          'male_children_count': maleChildrenCount,
          'female_children_count': femaleChildrenCount,
          'age_0_5_count': age0To5Count,
          'age_5_10_count': age5To10Count,
          'age_10_15_count': age10To15Count,
          'age_15_25_count': age15To25Count,
          'age_25_40_count': age25To40Count,
          'age_40_plus_count': age40PlusCount,
          'students_count': studentsCount,
          'orphans_count': orphansCount,
          'widows_count': widowsCount,
          'divorced_count': divorcedCount,
          'height': height,
          'weight': weight,
          'smoking_status': smokingStatus,
          'eyesight_condition': eyesightCondition,
          'has_disability': hasDisability,
          'disability_type': disabilityType,
          'household_disabled_count': householdDisabledCount,
          'chronic_illnesses': chronicIllnesses,
          'medical_conditions_count': medicalConditionsCount,
          'medical_conditions_desc': medicalConditionsDesc,
          'available_furniture': availableFurniture,
          'owns_car': ownsCar,
          'needs_description': needsDescription,
          'social_facebook': socialFacebook,
          'social_instagram': socialInstagram,
          'social_telegram': socialTelegram,
          'consent_show_real_name': consentShowRealName,
          'consent_share_info': consentShareInfo,
          'languages': languages,
          'district': district,
          'social_other': socialOther,
        }),
      ),
    );
    final body = _decode(resp.body);
    if (resp.statusCode == 200 && body['status'] == 'success') {
      final status = body['registration_status']?.toString();
      if (status != null && status.isNotEmpty) {
        await sharedPreferences.setString('registration_status', status);
      }
      // Mirror the chosen role + the entered name/address/gender locally so
      // the pending screen shows what the user typed (not the "User 1234"
      // login fallback) and Edit Profile's completeness check doesn't nag
      // for a gender that was already submitted and saved server-side.
      await sharedPreferences.setString('role_id', roleId.toString());
      await sharedPreferences.setString('name_user', fullName);
      await sharedPreferences.setString('address_user', address);
      if (gender.trim().isNotEmpty) {
        await sharedPreferences.setString('gender_user', gender.trim());
      }
      await sharedPreferences.remove('reject_reason');
      return RegistrationSubmitResult(ok: true, status: status);
    }
    return RegistrationSubmitResult(
      ok: false,
      error: body['error']?.toString(),
    );
  } catch (e) {
    return RegistrationSubmitResult(ok: false, error: e.toString());
  }
}

/// Grantor registration spec — uploads the optional personal photo and/or
/// ID card photo captured on the registration form. Best-effort: called
/// after submitRegistration() succeeds, and a failure here never blocks the
/// registration itself (both attachments are optional). Returns true only
/// if the request reached the server and it reported success.
Future<bool> uploadRegistrationPhotos({
  String? personalPhotoPath,
  String? idPhotoPath,
  // Eligible Recipient spec — "Attachments" section. All optional.
  String? rationCardPhotoPath,
  String? propertyProofPhotoPath,
  String? medicalReportPhotoPath,
  String? houseFacadePhotoPath,
  String? houseInsidePhotoPath,
  String? houseOutsidePhotoPath,
  // Volunteer/Employee spec — "Attachments". All optional.
  String? goldenSquarePhotoPath,
  String? residenceCardPhotoPath,
  String? passportPhotoPath,
  String? graduationCertPhotoPath,
  String? cvPhotoPath,
}) async {
  // Form field name -> local file path, skipping any that weren't picked.
  final pending = <String, String>{
    for (final e in <String, String?>{
      'personal_photo': personalPhotoPath,
      'id_photo': idPhotoPath,
      'ration_card_photo': rationCardPhotoPath,
      'property_proof_photo': propertyProofPhotoPath,
      'medical_report_photo': medicalReportPhotoPath,
      'house_facade_photo': houseFacadePhotoPath,
      'house_inside_photo': houseInsidePhotoPath,
      'house_outside_photo': houseOutsidePhotoPath,
      'golden_square_photo': goldenSquarePhotoPath,
      'residence_card_photo': residenceCardPhotoPath,
      'passport_photo': passportPhotoPath,
      'graduation_cert_photo': graduationCertPhotoPath,
      'cv_photo': cvPhotoPath,
    }.entries)
      if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
  };
  if (pending.isEmpty) {
    return true; // nothing to upload — not an error.
  }
  try {
    final dio = Dio(
      BaseOptions(
        validateStatus: (status) => status != null && status < 500,
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final map = <String, dynamic>{};
    for (final entry in pending.entries) {
      map[entry.key] = await MultipartFile.fromFile(
        entry.value,
        filename: entry.value.split(RegExp(r'[/\\]')).last,
      );
    }
    final resp = await dio.post<dynamic>(
      registrationPhotosUrl,
      data: FormData.fromMap(map),
      options: withApiAuthOptions(),
    );
    final body = resp.data;
    return resp.statusCode == 200 && body is Map && body['status'] == 'success';
  } catch (_) {
    // Fire-and-forget by design: registration_form.dart calls this inside
    // `unawaited(...)` AFTER submitRegistration() has already succeeded, and
    // discards the bool. The catch is therefore load-bearing — letting the
    // error escape an unawaited future would surface as an unhandled async
    // error, not as anything the user could act on. The attachments are all
    // optional and the registration itself is already saved, so a failed
    // upload costs the user nothing they were promised.
    //
    // NEEDS A DECISION (not made here — the fix lives in the caller, which
    // belongs to another change): because the result is discarded, a user
    // whose documents fail to upload is never told, and there is no retry.
    // If staff later require those documents, the silence becomes the bug.
    return false;
  }
}

/// Fetches the current registration status (ungated — reachable while pending).
/// Persists `registration_status`, `reject_reason` and any `role_id` to prefs.
/// Returns the decoded body, or null on network/auth failure.
Future<Map<String, dynamic>?> fetchRegistrationStatus() async {
  try {
    final resp = await http
        .get(Uri.parse(registrationStatusUrl), headers: withApiAuthHeaders())
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return null;
    final body = _decode(resp.body);

    final status = body['registration_status']?.toString();
    if (status != null && status.isNotEmpty) {
      await sharedPreferences.setString('registration_status', status);
    }

    final reason = body['reject_reason'];
    if (reason != null && reason.toString().trim().isNotEmpty) {
      await sharedPreferences.setString('reject_reason', reason.toString());
    } else {
      await sharedPreferences.remove('reject_reason');
    }

    final roleRaw = body['role_id'];
    final rid = roleRaw is int
        ? roleRaw
        : int.tryParse(roleRaw?.toString() ?? '');
    if (rid != null && rid > 0) {
      await sharedPreferences.setString('role_id', rid.toString());
    }

    // Mirror the submitted name/address so the pending screen shows the real
    // values (server is authoritative — works even on a fresh install).
    final fn = body['full_name']?.toString();
    if (fn != null && fn.trim().isNotEmpty) {
      await sharedPreferences.setString('name_user', fn.trim());
    }
    final ad = body['address']?.toString();
    if (ad != null && ad.trim().isNotEmpty) {
      await sharedPreferences.setString('address_user', ad.trim());
    }
    return body;
  } catch (_) {
    // NOT swallowed: null is the documented failure signal. Crucially, the
    // prefs writes above are skipped entirely on failure, so the last KNOWN
    // registration status is kept rather than being overwritten with a guess
    // — the user is never wrongly told they were approved or rejected.
    // Deliberately not a throw: this runs on the pending/splash path where an
    // exception would become a launch crash instead of a stale-but-true view.
    return null;
  }
}

Map<String, dynamic> _decode(String s) {
  try {
    final d = jsonDecode(s);
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {
    // DELIBERATE: an unparseable body yields the empty map below, and every
    // caller then finds no status/error key and reports its generic failure.
    // The error surfaces there, with the HTTP status still in hand.
  }
  return <String, dynamic>{};
}
