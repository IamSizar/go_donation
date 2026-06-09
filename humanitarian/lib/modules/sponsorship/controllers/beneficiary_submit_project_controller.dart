import 'dart:convert';

import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// POST JSON to [submitBeneficiaryProjectUrl] — keys align with PHP
/// `insertBeneficiaryProjectRequest` (camelCase remapped server-side where noted).
///
/// When logged in, `user_id` is sent from SharedPreferences key `id_user`
/// (same as login / donations). Omit from JSON if missing or invalid.
class BeneficiarySubmitProjectController extends GetxController {
  final isSubmitting = false.obs;

  /// Last successful insert id from the API (for UI / navigation).
  final lastSubmittedId = Rxn<int>();

  /// Returns `null` on success, or a user-facing error string.
  Future<String?> submitProjectRequest({
    required String title,
    required String category,
    required String summary,
    required String description,
    required double amount,
    required String currency,
    required String location,
    required String beneficiaryName,
    String? peopleAffected,
    String? maleCount,
    String? femaleCount,
    String? volunteerAgeProfile,
    String? volunteerSkills,
    String? peopleVolunteerDescription,
    String? timeline,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
    String? notes,
  }) async {
    if (isSubmitting.value) {
      return 'Please wait'.tr;
    }

    isSubmitting.value = true;
    lastSubmittedId.value = null;

    final body = <String, dynamic>{
      'title': title.trim(),
      'category': category.trim(),
      'summary': summary.trim(),
      'description': description.trim(),
      'amount': amount,
      'currency': currency.trim(),
      'location': location.trim(),
      'beneficiaryName': beneficiaryName.trim(),
      'content_locale': currentContentLocaleTag(),
    };

    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId != null && userId > 0) {
      body['user_id'] = userId;
    }
    final token = apiAuthTokenFieldValue();
    if (token != null && token.isNotEmpty) {
      body['access_token'] = token;
    }

    void putIfNonempty(String key, String? value) {
      final t = value?.trim();
      if (t != null && t.isNotEmpty) {
        body[key] = t;
      }
    }

    putIfNonempty('peopleAffected', peopleAffected);
    putIfNonempty('maleCount', maleCount);
    putIfNonempty('femaleCount', femaleCount);
    putIfNonempty('volunteerAgeProfile', volunteerAgeProfile);
    putIfNonempty('volunteerSkills', volunteerSkills);
    putIfNonempty('peopleVolunteerDescription', peopleVolunteerDescription);
    putIfNonempty('timeline', timeline);
    putIfNonempty('contactName', contactName);
    putIfNonempty('contact_phone', contactPhone);
    putIfNonempty('contact_email', contactEmail);
    putIfNonempty('notes', notes);

    try {
      final response = await http.post(
        Uri.parse(submitBeneficiaryProjectUrl),
        headers: withApiAuthHeaders(const {'Content-Type': 'application/json'}),
        body: jsonEncode(withApiAuthJsonBody(body)),
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return 'Invalid response from server.'.tr;
      }

      if (decoded is! Map) {
        return 'Invalid response from server.'.tr;
      }

      final map = Map<String, dynamic>.from(decoded);

      if (map['success'] == true) {
        final idRaw = map['id'];
        final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
        lastSubmittedId.value = id;
        await AppEventFirestore.log(
          eventType: 'project_request_submit',
          eventLabel: 'Project request submitted',
          module: 'beneficiary_project_requests',
          action: 'submit',
          userId: userId,
          entityId: id,
          amount: amount,
          currency: currency.trim(),
          contentLocale: currentContentLocaleTag(),
          note: title.trim(),
          metadata: {
            'category': category.trim(),
            'location': location.trim(),
            'beneficiary_name': beneficiaryName.trim(),
          },
        );
        return null;
      }

      final err = map['error']?.toString();
      if (err != null && err.isNotEmpty) {
        return err;
      }
      return 'Could not submit project request.'.tr;
    } catch (_) {
      return 'Could not reach the server. Check your connection.'.tr;
    } finally {
      isSubmitting.value = false;
    }
  }
}
