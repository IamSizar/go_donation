import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_application_1/api/campaigns_api_client.dart'
    show CampaignsApiClient, kCampaignsCsrfPrefsKey;
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:get/get.dart';

class FeaturedCampaignsController extends GetxController
    with RealtimePollingMixin {
  final isLoading = false.obs;
  final campaigns = <FeaturedCampaignData>[].obs;
  final errorMessage = RxnString();
  final pagination = Rxn<Map<String, dynamic>>();

  final Dio _dio = CampaignsApiClient.dio;

  // Campaigns are slower-moving than donations or signups, so we poll
  // every 15s rather than the default 5s — enough to surface progress
  // bars climbing without hammering the API.
  @override
  Duration get pollInterval => const Duration(seconds: 15);

  @override
  Future<void> realtimePoll() => fetchCampaigns(silent: true);

  @override
  void onInit() {
    super.onInit();
    fetchCampaigns();
    startPolling();
  }

  Map<String, dynamic>? _dioDataAsMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  void _persistCampaignsCsrfFromBody(Map<String, dynamic>? body) {
    final next = body?['csrf_token']?.toString();
    if (next != null && next.isNotEmpty) {
      sharedPreferences.setString(kCampaignsCsrfPrefsKey, next);
    }
  }

  /// GET [loginGetTokenUrl] with `action=campaigns` (same session as list request).
  Future<bool> fetchCampaignsCsrfToken() async {
    try {
      final uri = Uri.parse(
        loginGetTokenUrl,
      ).replace(queryParameters: const {'action': 'campaigns'});
      final resp = await _dio.get<dynamic>(uri.toString());
      if (resp.statusCode != 200) {
        return false;
      }
      final map = _dioDataAsMap(resp.data);
      if (map == null || map['status']?.toString() != 'success') {
        return false;
      }
      final token = map['csrf_token']?.toString();
      if (token == null || token.isEmpty) {
        return false;
      }
      await sharedPreferences.setString(kCampaignsCsrfPrefsKey, token);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads campaigns: ensures CSRF, then GET list with `csrf_token` in query.
  /// `silent` skips the loading spinner — used by the real-time polling
  /// tick so the progress bars update smoothly instead of flashing.
  Future<void> fetchCampaigns({
    int page = 1,
    int perPage = 12,
    bool isRetryAfter403 = false,
    bool silent = false,
  }) async {
    if (!silent) {
      isLoading.value = true;
      errorMessage.value = null;
    }

    try {
      var token = sharedPreferences.getString(kCampaignsCsrfPrefsKey);
      if (token == null || token.isEmpty) {
        final ok = await fetchCampaignsCsrfToken();
        if (!ok) {
          errorMessage.value =
              'Could not load campaigns security token. Try again.'.tr;
          campaigns.clear();
          pagination.value = null;
          return;
        }
        token = sharedPreferences.getString(kCampaignsCsrfPrefsKey);
      }

      if (token == null || token.isEmpty) {
        errorMessage.value = 'Missing campaigns security token.'.tr;
        campaigns.clear();
        pagination.value = null;
        return;
      }

      final uri = Uri.parse(featuredCampaignsUrl).replace(
        queryParameters: <String, String>{
          'page': '$page',
          'per_page': '$perPage',
          'csrf_token': token,
        },
      );

      final response = await _dio.get<dynamic>(uri.toString());
      final code = response.statusCode ?? 0;
      final body = _dioDataAsMap(response.data);

      if (code == 403 && !isRetryAfter403) {
        await sharedPreferences.remove(kCampaignsCsrfPrefsKey);
        final refreshed = await fetchCampaignsCsrfToken();
        if (refreshed) {
          await fetchCampaigns(
            page: page,
            perPage: perPage,
            isRetryAfter403: true,
          );
        } else {
          errorMessage.value =
              body?['error']?.toString() ??
              'Invalid or expired security token.'.tr;
          campaigns.clear();
          pagination.value = null;
        }
        return;
      }

      if (code == 403) {
        errorMessage.value =
            body?['error']?.toString() ??
            'Invalid or expired security token.'.tr;
        campaigns.clear();
        pagination.value = null;
        return;
      }

      if (code != 200) {
        errorMessage.value =
            body?['error']?.toString() ??
            'Failed to load campaigns (@code).'.trParams({
              'code': code.toString(),
            });
        campaigns.clear();
        pagination.value = null;
        return;
      }

      if (body == null) {
        errorMessage.value = 'Invalid campaigns response.'.tr;
        campaigns.clear();
        pagination.value = null;
        return;
      }

      _persistCampaignsCsrfFromBody(body);

      if (body['status']?.toString() != 'success' || body['data'] is! List) {
        errorMessage.value =
            body['error']?.toString() ?? 'Failed to load campaigns.'.tr;
        campaigns.clear();
        pagination.value = null;
        return;
      }

      final pag = body['pagination'];
      if (pag is Map<String, dynamic>) {
        pagination.value = pag;
      } else if (pag is Map) {
        pagination.value = Map<String, dynamic>.from(pag);
      } else {
        pagination.value = null;
      }

      final raw = body['data'] as List;
      final items = <FeaturedCampaignData>[];
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          items.add(FeaturedCampaignData.fromJson(e));
        } else if (e is Map) {
          items.add(
            FeaturedCampaignData.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }

      campaigns.assignAll(items);
    } on DioException catch (e) {
      if (!silent) {
        final body = _dioDataAsMap(e.response?.data);
        errorMessage.value =
            body?['error']?.toString() ??
            'Could not load campaigns. Check your network.'.tr;
        campaigns.clear();
        pagination.value = null;
      }
    } catch (_) {
      if (!silent) {
        errorMessage.value =
            'Could not load campaigns. Please check the API endpoint.'.tr;
        campaigns.clear();
        pagination.value = null;
      }
      // Silent polls preserve the existing campaigns list on failure.
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  Future<void> refreshCampaigns() => fetchCampaigns();
}
