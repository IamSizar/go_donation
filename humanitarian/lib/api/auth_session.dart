import 'package:dio/dio.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String kApiAccessTokenPrefsKey = 'api_access_token';
const String kApiAccessTokenExpiryPrefsKey = 'api_access_token_expires_at';

String? currentApiAccessToken() {
  final token = sharedPreferences.getString(kApiAccessTokenPrefsKey)?.trim();
  if (token == null || token.isEmpty) {
    return null;
  }
  return token;
}

String? apiAuthTokenFieldValue() {
  final token = currentApiAccessToken();
  if (token == null || token.isEmpty) {
    return null;
  }
  return token;
}

Map<String, String> withApiAuthHeaders([Map<String, String>? base]) {
  final headers = <String, String>{...?base};
  final token = currentApiAccessToken();
  if (token != null) {
    headers['Authorization'] = 'Bearer $token';
  }
  headers.putIfAbsent('Accept', () => 'application/json');
  return headers;
}

Map<String, String> withApiAuthQueryParameters([Map<String, String>? base]) {
  final query = <String, String>{...?base};
  final token = apiAuthTokenFieldValue();
  if (token != null && token.isNotEmpty) {
    query.putIfAbsent('access_token', () => token);
  }
  return query;
}

Map<String, dynamic> withApiAuthJsonBody([Map<String, dynamic>? base]) {
  final body = <String, dynamic>{...?base};
  final token = apiAuthTokenFieldValue();
  if (token != null && token.isNotEmpty) {
    body.putIfAbsent('access_token', () => token);
  }
  return body;
}

Options withApiAuthOptions([Options? options]) {
  final headers = <String, dynamic>{...?options?.headers};
  headers.addAll(withApiAuthHeaders());
  return (options ?? Options()).copyWith(headers: headers);
}

Future<void> persistApiSessionFromResponse(Map<String, dynamic> body) async {
  final token = body['access_token']?.toString().trim().isNotEmpty == true
      ? body['access_token'].toString().trim()
      : body['session'] is Map
      ? (body['session']['access_token']?.toString().trim())
      : null;
  final expiresAt = body['expires_at']?.toString().trim().isNotEmpty == true
      ? body['expires_at'].toString().trim()
      : body['session'] is Map
      ? body['session']['expires_at']?.toString().trim()
      : null;
  if (token != null && token.isNotEmpty) {
    await sharedPreferences.setString(kApiAccessTokenPrefsKey, token);
  }
  if (expiresAt != null && expiresAt.isNotEmpty) {
    await sharedPreferences.setString(kApiAccessTokenExpiryPrefsKey, expiresAt);
  }
}

Future<void> clearApiSession() async {
  await sharedPreferences.remove(kApiAccessTokenPrefsKey);
  await sharedPreferences.remove(kApiAccessTokenExpiryPrefsKey);
}

Future<bool> ensureApiSession({
  String? phone,
  String? expectedUserId,
  bool forceRefresh = false,
}) async {
  final existing = currentApiAccessToken();
  if (!forceRefresh && existing != null && existing.isNotEmpty) {
    return true;
  }

  if (forceRefresh) {
    await clearApiSession();
  }

  final phoneValue = (phone ?? sharedPreferences.getString('phone_user') ?? '')
      .trim();
  if (phoneValue.isEmpty) {
    return false;
  }

  try {
    final response = await http.post(
      Uri.parse(insertUserWithPhoneUrl),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'phone': phoneValue}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    final success =
        decoded['status'] == 'success' || decoded['success'] == true;
    if (!success) {
      return false;
    }

    final returnedUserId = decoded['user_id']?.toString().trim();
    final expected =
        (expectedUserId ?? sharedPreferences.getString('id_user') ?? '').trim();
    if (expected.isNotEmpty &&
        returnedUserId != null &&
        returnedUserId.isNotEmpty &&
        returnedUserId != expected) {
      return false;
    }

    await persistApiSessionFromResponse(decoded);
    return currentApiAccessToken() != null;
  } catch (_) {
    return false;
  }
}
