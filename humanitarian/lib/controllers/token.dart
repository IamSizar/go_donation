import 'dart:convert';

import 'package:flutter_application_1/api/campaigns_api_client.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';

class TokenController extends GetxController {
  var isLoading = false.obs;
  var errorMessage = ''.obs;
  var csrfToken = ''.obs;
  var action = 'login'.obs;
  var ttl = 600.obs;

  final Dio _dio = Dio();

  /// Fetches CSRF from [loginGetTokenUrl] with `?action=…`.
  ///
  /// - `actionParam == 'campaigns'`: uses [CampaignsApiClient.dio] (same cookies as
  ///   [FeaturedCampaignsController]) and saves to `csrf_token_campaigns`.
  /// - Otherwise: plain [_dio]; for `login` you may also persist via [sharedPreferences]
  ///   if you call this outside [LoginController].
  Future<bool> fetchToken({
    String apiUrl = loginGetTokenUrl,
    String actionParam = 'login',
  }) async {
    isLoading.value = true;
    errorMessage.value = '';
    csrfToken.value = '';
    action.value = actionParam;

    final dio = actionParam == 'campaigns'
        ? CampaignsApiClient.dio
        : _dio;

    try {
      final uri =
          Uri.parse(apiUrl).replace(queryParameters: {'action': actionParam});
      final response = await dio.get(uri.toString());

      if (response.statusCode != 200) {
        errorMessage.value =
            'Could not fetch CSRF token. Status code: ${response.statusCode}';
        isLoading.value = false;
        return false;
      }

      final data =
          response.data is String ? jsonDecode(response.data) : response.data;

      if (data['status'] != 'success') {
        errorMessage.value =
            data['error']?.toString() ?? 'Failed to fetch CSRF token.';
        isLoading.value = false;
        return false;
      }

      csrfToken.value = data['csrf_token']?.toString() ?? '';
      action.value = data['action']?.toString() ?? actionParam;
      final ttlRaw = data['ttl'];
      if (ttlRaw is int) {
        ttl.value = ttlRaw;
      } else {
        ttl.value = int.tryParse(ttlRaw?.toString() ?? '') ?? 600;
      }

      if (csrfToken.value.isEmpty) {
        errorMessage.value = 'CSRF token missing in response.';
        isLoading.value = false;
        return false;
      }

      if (actionParam == 'campaigns') {
        await sharedPreferences.setString(
          kCampaignsCsrfPrefsKey,
          csrfToken.value,
        );
      } else if (actionParam == 'login') {
        await sharedPreferences.setString('csrf_token', csrfToken.value);
      }

      isLoading.value = false;
      return true;
    } on DioException catch (e) {
      errorMessage.value = 'Network error: ${e.message}';
      isLoading.value = false;
      return false;
    } catch (e) {
      errorMessage.value = 'Unexpected error: $e';
      isLoading.value = false;
      return false;
    }
  }
}