import 'dart:async';
import 'dart:developer';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginController extends GetxController {
  var isLoading = false.obs;
  var errorMessage = ''.obs;
  final pendingPhone = ''.obs;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;
  // Phase 19 — these were the local-only OTP placeholder fields the pre-19
  // code used. We keep them as nullable for back-compat with code paths
  // that still touch them (clearPendingOtp, the demo-snackbar branch), but
  // the server is now the source of truth for code expiry + correctness.
  // The `// ignore: unused_field` is intentional — the fields are still
  // assigned in a few places, just never read for verification.
  // ignore: unused_field
  String? _pendingOtp;
  // ignore: unused_field
  DateTime? _otpExpiresAt;

  final CookieJar _loginSessionJar = CookieJar();
  late final Dio _loginSessionDio;

  @override
  void onInit() {
    super.onInit();
    _loginSessionDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {'Accept': 'application/json'},
        validateStatus: (code) => code != null && code < 600,
      ),
    );
    _loginSessionDio.interceptors.add(CookieManager(_loginSessionJar));
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    // Passing the server (Web) client ID makes the returned idToken's audience
    // the Web client ID, which the backend verifies. Empty → platform default.
    await _googleSignIn.initialize(
      serverClientId: googleServerClientId.isEmpty
          ? null
          : googleServerClientId,
    );
    _googleInitialized = true;
  }

  /// Phase 19 — sendOtp now calls the real backend at /api/auth/otp/request.
  ///
  /// The backend stores a hashed 6-digit code in `otp_codes` and dispatches
  /// it via OTPIQ with `provider=whatsapp-sms` (WhatsApp first, SMS as
  /// automatic fallback). Demo mode (controlled by the OTP_DEMO_ENABLED
  /// env flag on the backend) returns the code in the response body — we
  /// surface it in a snackbar then so developers can verify without a
  /// real number.
  ///
  /// Phase 19b — `mode` lets the caller pick between 'real' (OTPIQ
  /// delivery) and 'demo' (static 123456, backend-side). The login screen
  /// has a UI toggle that decides which one to send. Defaults to 'real'
  /// so old call sites keep their previous behavior.
  ///
  /// `lastOtpMode` stashes the mode that was actually used by the most
  /// recent send — `resendOtp()` reads it so re-issuing a code uses the
  /// same mode without needing the screen to pass it back.
  String _lastOtpMode = 'real';
  Future<bool> sendOtp(String phone, {String mode = 'real'}) async {
    isLoading.value = true;
    errorMessage.value = '';

    try {
      final normalizedPhone = _normalizePhone(phone);
      if (normalizedPhone.isEmpty) {
        errorMessage.value = 'Enter a valid phone number.'.tr;
        return false;
      }

      // We keep `pendingPhone` so the verify screen can show "Code sent to
      // +964…" and so resendOtp() works without re-asking the phone.
      pendingPhone.value = normalizedPhone;

      // Coerce the mode to one of the two accepted values — anything else
      // (including null / typos) becomes 'real' for safety.
      final resolvedMode = (mode == 'demo') ? 'demo' : 'real';
      _lastOtpMode = resolvedMode;

      final resp = await _loginSessionDio.post<dynamic>(
        otpRequestUrl,
        data: <String, dynamic>{'phone': normalizedPhone, 'mode': resolvedMode},
        options: Options(contentType: Headers.jsonContentType),
      );

      final code = resp.statusCode ?? 0;
      final body = _dioDataAsMap(resp.data);

      if (code != 200 && code != 201) {
        // Map common backend errors to user-friendly messages.
        final raw = body?['error']?.toString() ?? body?['message']?.toString();
        if (code == 429) {
          errorMessage.value =
              raw ?? 'Too many requests. Please wait before trying again.'.tr;
        } else if (code == 502 || code == 503) {
          errorMessage.value =
              raw ?? 'Verification service is temporarily unavailable.'.tr;
        } else {
          errorMessage.value =
              raw ??
              'Failed to send code. (@code)'.trParams({
                'code': code.toString(),
              });
        }
        return false;
      }

      // Save TTL for the verify screen's countdown.
      final expiresIn = (body?['expires_in'] is num)
          ? (body!['expires_in'] as num).toInt()
          : 300;
      _otpExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));

      // Demo path: the backend returned the actual code so the dev can copy it.
      final demoCode = body?['demo_code']?.toString();
      if (demoCode != null && demoCode.isNotEmpty) {
        _pendingOtp = demoCode; // also stashed for legacy local code
        Get.snackbar(
          'OTP ready'.tr,
          'Demo OTP: @code'.trParams({'code': demoCode}),
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6),
        );
      } else {
        _pendingOtp = null;
        Get.snackbar(
          'OTP sent'.tr,
          'Check WhatsApp first — SMS arrives if WhatsApp delivery fails.'.tr,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
      AppHaptics.gentle();
      return true;
    } catch (e, stack) {
      log('OTP send error: $e', stackTrace: stack);
      errorMessage.value = 'An error occurred: @error'.trParams({
        'error': e.toString(),
      });
    } finally {
      isLoading.value = false;
    }
    return false;
  }

  /// Phase 19 — verifyOtp now POSTs to /api/auth/otp/verify which returns
  /// the SAME shape as /api/auth/login (access_token + account + role_id +
  /// expires_at), so we can drop the second "_insertUserWithPhone" call
  /// that the old flow needed.
  Future<Map<String, dynamic>?> verifyOtp(String otp) async {
    isLoading.value = true;
    errorMessage.value = '';

    try {
      if (pendingPhone.value.isEmpty) {
        errorMessage.value = 'Request a new OTP first.'.tr;
        return null;
      }
      final code = otp.trim();
      if (code.length != 6 || int.tryParse(code) == null) {
        errorMessage.value = 'Verification code must be 6 digits.'.tr;
        return null;
      }

      final resp = await _loginSessionDio.post<dynamic>(
        otpVerifyUrl,
        data: <String, dynamic>{'phone': pendingPhone.value, 'code': code},
        options: Options(contentType: Headers.jsonContentType),
      );

      final status = resp.statusCode ?? 0;
      final body = _dioDataAsMap(resp.data);

      if (status == 401) {
        final left = body?['attempts_left'];
        errorMessage.value = (left is num && left > 0)
            ? 'Incorrect code. @n attempts left.'.trParams({
                'n': left.toString(),
              })
            : (body?['error']?.toString() ?? 'Incorrect verification code.'.tr);
        return null;
      }
      if (status == 410 || status == 404 || status == 429) {
        errorMessage.value =
            body?['error']?.toString() ??
            'This code is no longer valid. Tap Resend.'.tr;
        return null;
      }
      if (status != 200 || body == null) {
        errorMessage.value =
            body?['error']?.toString() ??
            'Verification failed. (@code)'.trParams({
              'code': status.toString(),
            });
        return null;
      }

      // Server returned a valid session — translate the login-shape into the
      // legacy user-map that the rest of the app already consumes. This
      // also persists the access_token + logs the login event to Firestore.
      final user = await _buildUserFromLoginResponse(body, pendingPhone.value);
      if (user == null) {
        errorMessage.value =
            'Verification endpoint returned an invalid response.'.tr;
        return null;
      }

      clearPendingOtp();
      return user;
    } catch (e, stack) {
      log('OTP verification error: $e', stackTrace: stack);
      errorMessage.value = 'An error occurred: @error'.trParams({
        'error': e.toString(),
      });
    } finally {
      isLoading.value = false;
    }

    return null;
  }

  /// Translate the /auth/otp/verify (or /auth/login) success response into
  /// the user-map shape the rest of the app expects. Mirrors the second
  /// half of `_insertUserWithPhone` so the OTP path produces an identical
  /// user record (session persisted + Firestore login/register event).
  Future<Map<String, dynamic>?> _buildUserFromLoginResponse(
    Map<String, dynamic> body,
    String phoneFallback,
  ) async {
    final accRaw = body['account'];
    Map<String, dynamic>? accountMap;
    if (accRaw is Map) {
      accountMap = flattenAccountMap(Map<String, dynamic>.from(accRaw));
    }
    final insertedId = _extractInsertedUserId(body);
    if (insertedId == null || insertedId.isEmpty) return null;

    final userData = body['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(body['user'] as Map<String, dynamic>)
        : body['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(body['data'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final resolvedPhone =
        pickFromAccountMap(accountMap, ['phone', 'number', 'phone_number']) ??
        () {
          final p = userData['phone']?.toString().trim();
          return (p != null && p.isNotEmpty) ? p : phoneFallback;
        }();
    final resolvedName =
        pickFromAccountMap(accountMap, ['full_name', 'name', 'display_name']) ??
        userData['name']?.toString();
    final resolvedEmail =
        pickFromAccountMap(accountMap, ['email']) ??
        userData['email']?.toString();

    final user = _buildPhoneUser(
      id: insertedId,
      phone: resolvedPhone,
      name: resolvedName,
      email: resolvedEmail,
    );
    if (accountMap != null) user['account'] = accountMap;

    // Persist the access_token so the rest of the app's API calls work.
    await persistApiSessionFromResponse(body);

    // Mirror the role / returning-user fields the rest of the app reads.
    final hasRole = body['has_role'] == true || body['has_role'] == 1;
    user['has_role'] = hasRole;
    if (body['returning_user'] != null) {
      user['returning_user'] =
          body['returning_user'] == true || body['returning_user'] == 1;
    }
    final rawRole = body['role_id'];
    if (rawRole != null && rawRole.toString().trim().isNotEmpty) {
      final rid = int.tryParse(rawRole.toString());
      if (rid != null && rid > 0) user['role_id'] = rid;
    }
    if (!hasRole) user.remove('role_id');

    // New-user approval flow — pass the server's registration_status through
    // so the post-login router can branch on it.
    final regStatus = body['registration_status']?.toString().trim();
    if (regStatus != null && regStatus.isNotEmpty) {
      user['registration_status'] = regStatus;
    }

    // Fire the same Firestore login/register analytics event as the legacy
    // path — keeps dashboards consistent regardless of which auth method
    // the user took.
    await AppEventFirestore.log(
      eventType: user['returning_user'] == true ? 'login' : 'register',
      eventLabel: user['returning_user'] == true
          ? 'User logged in (OTP)'
          : 'User registered (OTP)',
      module: 'auth',
      action: user['returning_user'] == true ? 'login' : 'register',
      userId: int.tryParse(user['id']?.toString() ?? ''),
      roleId: user['role_id'] is int
          ? user['role_id'] as int
          : int.tryParse(user['role_id']?.toString() ?? ''),
      name: resolvedName,
      number: resolvedPhone,
      note: user['returning_user'] == true
          ? 'OTP login succeeded'
          : 'OTP registration succeeded',
    );

    return user;
  }

  /// Phase 19b — resend uses the SAME mode the original send used. So a
  /// user who picked "Demo OTP" on the login screen still gets a demo
  /// code on resend (never silently fall back to real and burn credit).
  Future<bool> resendOtp() async {
    if (pendingPhone.value.isEmpty) {
      errorMessage.value = 'Enter your phone number first.'.tr;
      return false;
    }
    return sendOtp(pendingPhone.value, mode: _lastOtpMode);
  }

  void clearPendingOtp() {
    pendingPhone.value = '';
    _pendingOtp = null;
    _otpExpiresAt = null;
    unawaited(_loginSessionJar.deleteAll());
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s()-]'), '').trim();
  }

  String _lastDigits(String value) {
    if (value.length <= 4) {
      return value;
    }
    return value.substring(value.length - 4);
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

  String? _extractInsertedUserId(Map<String, dynamic> decoded) {
    final dynamic data = decoded['data'];
    final dynamic user = decoded['user'];

    final candidates = <dynamic>[
      decoded['id'],
      decoded['user_id'],
      decoded['inserted_id'],
      decoded['lastInsertId'],
      decoded['last_insert_id'],
      if (data is Map<String, dynamic>) data['id'],
      if (data is Map<String, dynamic>) data['user_id'],
      if (data is Map<String, dynamic>) data['inserted_id'],
      if (user is Map<String, dynamic>) user['id'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return null;
  }

  Map<String, dynamic> _buildPhoneUser({
    required String id,
    required String phone,
    String? name,
    String? email,
  }) {
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : 'User ${_lastDigits(phone)}';

    return <String, dynamic>{
      'id': id,
      'phone': phone,
      'name': resolvedName,
      'email': email ?? '',
    };
  }

  Future<Map<String, dynamic>?> signInWithGoogle() async {
    isLoading.value = true;
    errorMessage.value = '';

    try {
      await _ensureGoogleInitialized();
      if (!_googleSignIn.supportsAuthenticate()) {
        errorMessage.value =
            'Google sign-in is not supported on this platform.'.tr;
        return null;
      }

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // The ID token is what the backend verifies (its signature/audience).
      final String? idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        errorMessage.value =
            'Google sign-in did not return an ID token. Check the client-ID setup.'
                .tr;
        return null;
      }

      // Exchange the Google ID token for an app session at our backend. The
      // response mirrors /auth/login, so _buildUserFromLoginResponse persists
      // the access_token, runs the registration/approval branch, and logs the
      // analytics event — identical to the phone/OTP path.
      final resp = await _loginSessionDio.post(
        '${baseUrl}auth/google',
        data: {'id_token': idToken},
      );
      final body = _dioDataAsMap(resp.data);
      if (body == null || body['status'] != 'success') {
        errorMessage.value =
            body?['error']?.toString() ?? 'Google sign-in failed.'.tr;
        return null;
      }

      final user = await _buildUserFromLoginResponse(body, '');
      if (user == null) {
        errorMessage.value = 'Google sign-in returned an invalid response.'.tr;
        return null;
      }
      return user;
    } on DioException catch (e, stack) {
      log('Google backend auth error: $e', stackTrace: stack);
      final data = _dioDataAsMap(e.response?.data);
      errorMessage.value =
          data?['error']?.toString() ??
          'Google sign-in could not reach the server.'.tr;
      return null;
    } on GoogleSignInException catch (e, stack) {
      log('Google sign-in error: $e', stackTrace: stack);
      errorMessage.value = switch (e.code) {
        GoogleSignInExceptionCode.canceled =>
          'Google sign-in was cancelled.'.tr,
        _ =>
          'Google sign-in failed. Please check the Google Sign-In configuration and try again.'
              .tr,
      };
    } catch (e, stack) {
      log('Unexpected Google sign-in error: $e', stackTrace: stack);
      errorMessage.value =
          'Google sign-in could not start. Please verify the platform setup.'
              .tr;
    } finally {
      isLoading.value = false;
    }

    return null;
  }
}
