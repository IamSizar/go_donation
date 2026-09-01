// profile_full_api.dart — the signed-in user's complete profile row.
//
// WHY THIS IS SEPARATE FROM fetchUserAccount()
// `/profile/get` (and fetchUserAccount around it) returns the eight columns
// the app needed while Edit Profile was a four-field form: name, gender,
// address, picture, date of birth, the identity codes, the privacy blob.
//
// The edit form now has to show every field the person's ROLE asks for,
// prefilled with what they already entered — a hundred columns, not eight. So
// the backend grew GET /api/profile/full (internal/handlers/profile_full.go),
// which returns the same row the dashboard's detail page reads.
//
// The endpoint takes NO user id: the row is chosen by the bearer token alone.
// That is deliberate on the server and it is why nothing here passes one.
import 'package:dio/dio.dart';

import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';

/// The signed-in user's profile columns, or null when the request failed.
///
/// An account that has not registered yet has no profile row; the server
/// answers `{}` for that rather than 404, so this returns an EMPTY MAP — a
/// meaningfully different answer from null. The caller must be able to tell
/// "you have filled nothing in" (prefill nothing, carry on) from "we could not
/// read your profile" (do not show an empty form that invites the user to
/// overwrite what they had).
Future<Map<String, dynamic>?> fetchFullProfile() async {
  final dio = Dio(
    BaseOptions(
      validateStatus: (status) => status != null && status < 600,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: withApiAuthHeaders(),
    ),
  );
  try {
    final uri = Uri.parse('${baseUrl}profile/full').replace(
      queryParameters: withApiAuthQueryParameters(const {}),
    );
    final res = await dio.get<dynamic>(uri.toString(), options: withApiAuthOptions());
    if (res.statusCode != 200) return null;
    final body = res.data;
    if (body is! Map) return null;
    if (body['status'] != 'success') return null;
    final profile = body['profile'];
    if (profile is Map) {
      return profile.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  } on DioException catch (_) {
    return null;
  } catch (_) {
    return null;
  }
}
