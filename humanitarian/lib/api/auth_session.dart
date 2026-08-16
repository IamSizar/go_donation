import 'package:dio/dio.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String kApiAccessTokenPrefsKey = 'api_access_token';
const String kApiAccessTokenExpiryPrefsKey = 'api_access_token_expires_at';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

// The token is kept in the OS-encrypted keystore/keychain (see
// `_secureStorage` above), not in plain SharedPreferences — a rooted/
// jailbroken device or a backup extraction can no longer read it in plain
// text. Reads elsewhere in the app must stay synchronous, so a copy is held
// in memory and refreshed on every write; `loadApiSessionFromSecureStorage`
// primes it once at startup (see `initializeAppState`).
String? _cachedToken;

/// Loads the persisted token into memory. Awaited once during app startup,
/// before any screen can call the synchronous accessors below. Also
/// migrates a token left over from the old plaintext-SharedPreferences
/// storage (pre-fix app versions) into secure storage, then wipes the
/// plaintext copy.
Future<void> loadApiSessionFromSecureStorage() async {
  var token = await _secureStorage.read(key: kApiAccessTokenPrefsKey);
  if (token == null || token.trim().isEmpty) {
    final legacyToken = sharedPreferences
        .getString(kApiAccessTokenPrefsKey)
        ?.trim();
    if (legacyToken != null && legacyToken.isNotEmpty) {
      token = legacyToken;
      await _secureStorage.write(key: kApiAccessTokenPrefsKey, value: token);
      final legacyExpiry = sharedPreferences.getString(
        kApiAccessTokenExpiryPrefsKey,
      );
      if (legacyExpiry != null && legacyExpiry.isNotEmpty) {
        await _secureStorage.write(
          key: kApiAccessTokenExpiryPrefsKey,
          value: legacyExpiry,
        );
      }
    }
  }
  await sharedPreferences.remove(kApiAccessTokenPrefsKey);
  await sharedPreferences.remove(kApiAccessTokenExpiryPrefsKey);
  _cachedToken = (token != null && token.trim().isNotEmpty)
      ? token.trim()
      : null;
}

String? currentApiAccessToken() {
  final token = _cachedToken?.trim();
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
    await _secureStorage.write(key: kApiAccessTokenPrefsKey, value: token);
    _cachedToken = token;
  }
  if (expiresAt != null && expiresAt.isNotEmpty) {
    await _secureStorage.write(
      key: kApiAccessTokenExpiryPrefsKey,
      value: expiresAt,
    );
  }
}

Future<void> clearApiSession() async {
  await _secureStorage.delete(key: kApiAccessTokenPrefsKey);
  await _secureStorage.delete(key: kApiAccessTokenExpiryPrefsKey);
  _cachedToken = null;
}

/// Identity keys wiped on logout. Intentionally does NOT include preferences
/// the user expects to survive a logout (selected language, theme) — those are
/// left untouched so the app doesn't reset to English after signing out.
const List<String> _identityPrefsKeys = [
  'id_user',
  'email_user',
  'phone_user',
  'name_user',
  'address_user',
  'gender_user',
  'profile_image_path',
  'profile_picture_url',
  'role_id',
  'registration_status',
  'reject_reason',
  // K21 — the account's own GR-/ER-/VL- code. It names a person, so it must go
  // with the rest of the identity: a code left behind after sign-out would be
  // shown to whoever signs in next.
  'identity_code',
];

/// Section 27.5 — full logout. Revokes the session token on the server (so it
/// can never be reused / auto-restored), then clears the local session,
/// identity, and guest flag. Best-effort on the network call: local state is
/// always cleared even if the device is offline.
///
/// IMPORTANT: navigate away from the authenticated screen (Get.offAllNamed to
/// the login/welcome route) BEFORE awaiting this, so no still-mounted section
/// rebuilds against the cleared prefs (that was the black-screen bug, 27.4).
Future<void> logout() async {
  final token = currentApiAccessToken();
  if (token != null && token.isNotEmpty) {
    try {
      await http
          .post(
            Uri.parse(logoutUrl),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline / server unreachable — local state is still cleared below, and
      // the token expires server-side on its own TTL.
    }
  }
  await clearApiSession();
  for (final key in _identityPrefsKeys) {
    await sharedPreferences.remove(key);
  }
  // A signed-out user is not a guest either; drop the guest flag so the splash
  // routes to welcome/login, not straight into guest Home.
  await exitGuestMode();
}

/// A16 — `ensureApiSession()` USED TO LIVE HERE, and it is gone on purpose.
///
/// It re-minted a session by POSTing the phone number stashed in
/// `phone_user` to `/api/auth/login`, which handed back a fresh 30-day token
/// for any number that had no password. That silent re-mint WAS the
/// authentication hole, seen from the client side: a phone number is not a
/// secret, and the server now refuses to trade one for a token (it answers
/// `401 otp_required`). Keeping the call would have achieved nothing except
/// destroying the caller's working token on its way to a guaranteed refusal —
/// it cleared the session BEFORE the request, so every failure logged the user
/// out. (That already happened to guests and to anyone with no `phone_user`
/// pref: those callers returned early, after the clear.)
///
/// A session now comes from one place only — a sign-in that verified
/// something: a password, or an OTP delivered out-of-band. When the token is
/// gone, the session is over, and the splash screen routes to sign-in rather
/// than papering over it.
///
/// Callers that need to know whether a usable session exists should read
/// [currentApiAccessToken] directly.
