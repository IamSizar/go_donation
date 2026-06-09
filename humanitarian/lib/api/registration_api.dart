import 'dart:convert';

import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:http/http.dart' as http;

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
        }),
      ),
    );
    final body = _decode(resp.body);
    if (resp.statusCode == 200 && body['status'] == 'success') {
      final status = body['registration_status']?.toString();
      if (status != null && status.isNotEmpty) {
        await sharedPreferences.setString('registration_status', status);
      }
      // Mirror the chosen role + the entered name/address so the pending
      // screen shows what the user typed (not the "User 1234" login fallback).
      await sharedPreferences.setString('role_id', roleId.toString());
      await sharedPreferences.setString('name_user', fullName);
      await sharedPreferences.setString('address_user', address);
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

/// Fetches the current registration status (ungated — reachable while pending).
/// Persists `registration_status`, `reject_reason` and any `role_id` to prefs.
/// Returns the decoded body, or null on network/auth failure.
Future<Map<String, dynamic>?> fetchRegistrationStatus() async {
  try {
    final resp = await http.get(
      Uri.parse(registrationStatusUrl),
      headers: withApiAuthHeaders(),
    );
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
    final rid =
        roleRaw is int ? roleRaw : int.tryParse(roleRaw?.toString() ?? '');
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
    return null;
  }
}

Map<String, dynamic> _decode(String s) {
  try {
    final d = jsonDecode(s);
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {}
  return <String, dynamic>{};
}
