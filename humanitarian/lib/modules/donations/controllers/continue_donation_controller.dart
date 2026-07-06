import 'dart:convert';

import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class ContinueDonationController extends GetxController {
  final isSubmitting = false.obs;

  /// Returns `null` on success, or a user-facing error string.
  Future<String?> submitDonation({
    int? userId,
    int? campaignsId,
    String? message,
    required int amount,
    required String paymentMethod,
    String donationType = 'general',
  }) async {
    if (isSubmitting.value) {
      return 'Please wait'.tr;
    }

    isSubmitting.value = true;
    try {
      final base = Uri.parse(insertDonationUsersUrl);
      final uri = userId != null
          ? base.replace(
              queryParameters: withApiAuthQueryParameters({
                ...base.queryParameters,
                'user_id': '$userId',
              }),
            )
          : base.replace(
              queryParameters: withApiAuthQueryParameters(base.queryParameters),
            );

      final body = <String, String>{
        'amount': amount.toString(),
        'payment_method': paymentMethod,
        'donation_type': donationType,
      };
      final token = apiAuthTokenFieldValue();
      if (token != null && token.isNotEmpty) {
        body['access_token'] = token;
      }
      if (campaignsId != null) {
        body['campaigns_id'] = campaignsId.toString();
      }
      final trimmed = message?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        body['message'] = trimmed;
      }

      final response = await http.post(
        uri,
        headers: withApiAuthHeaders(),
        body: body,
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

      if (decoded['success'] == true) {
        await AppEventFirestore.log(
          eventType: 'donation_submit',
          eventLabel: 'Contribution submitted',
          module: 'donations',
          action: 'submit',
          userId: userId,
          entityId: decoded['id'] is int
              ? decoded['id'] as int
              : int.tryParse(decoded['id']?.toString() ?? ''),
          targetId: campaignsId,
          amount: amount,
          paymentMethod: paymentMethod,
          note: trimmed,
          metadata: {'campaign_id': campaignsId},
        );
        return null;
      }

      final err = decoded['error']?.toString();
      if (err != null && err.isNotEmpty) {
        return err;
      }
      return 'Failed to save donation.'.tr;
    } catch (_) {
      return 'Could not reach the server. Check your connection.'.tr;
    } finally {
      isSubmitting.value = false;
    }
  }
}
