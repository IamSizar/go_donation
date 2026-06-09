import 'dart:async';
import 'dart:developer';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginController extends GetxController {
  var isLoading = false.obs;
  var errorMessage = ''.obs;
  final pendingPhone = ''.obs;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;
  final Random _random = Random();
  Map<String, dynamic>? _pendingUser;
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
    await _googleSignIn.initialize();
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
      _pendingUser = null; // legacy local-OTP state cleared

      // Coerce the mode to one of the two accepted values — anything else
      // (including null / typos) becomes 'real' for safety.
      final resolvedMode = (mode == 'demo') ? 'demo' : 'real';
      _lastOtpMode = resolvedMode;

      final resp = await _loginSessionDio.post<dynamic>(
        otpRequestUrl,
        data: <String, dynamic>{
          'phone': normalizedPhone,
          'mode': resolvedMode,
        },
        options: Options(contentType: Headers.jsonContentType),
      );

      final code = resp.statusCode ?? 0;
      final body = _dioDataAsMap(resp.data);

      if (code != 200 && code != 201) {
        // Map common backend errors to user-friendly messages.
        final raw = body?['error']?.toString() ?? body?['message']?.toString();
        if (code == 429) {
          errorMessage.value = raw ??
              'Too many requests. Please wait before trying again.'.tr;
        } else if (code == 502 || code == 503) {
          errorMessage.value = raw ??
              'Verification service is temporarily unavailable.'.tr;
        } else {
          errorMessage.value =
              raw ?? 'Failed to send code. (@code)'.trParams({'code': code.toString()});
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
        data: <String, dynamic>{
          'phone': pendingPhone.value,
          'code': code,
        },
        options: Options(contentType: Headers.jsonContentType),
      );

      final status = resp.statusCode ?? 0;
      final body = _dioDataAsMap(resp.data);

      if (status == 401) {
        final left = body?['attempts_left'];
        errorMessage.value = (left is num && left > 0)
            ? 'Incorrect code. @n attempts left.'.trParams({'n': left.toString()})
            : (body?['error']?.toString() ?? 'Incorrect verification code.'.tr);
        return null;
      }
      if (status == 410 || status == 404 || status == 429) {
        errorMessage.value =
            body?['error']?.toString() ?? 'This code is no longer valid. Tap Resend.'.tr;
        return null;
      }
      if (status != 200 || body == null) {
        errorMessage.value =
            body?['error']?.toString() ??
            'Verification failed. (@code)'.trParams({'code': status.toString()});
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
    final resolvedName = pickFromAccountMap(
          accountMap,
          ['full_name', 'name', 'display_name'],
        ) ??
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
    _pendingUser = null;
    _otpExpiresAt = null;
    unawaited(_loginSessionJar.deleteAll());
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s()-]'), '').trim();
  }

  String _generateOtp() {
    return (100000 + _random.nextInt(900000)).toString();
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

  /// GET [loginGetTokenUrl] with `action=login` when user requests OTP (primes PHP session + CSRF).
  Future<bool> _fetchLoginCsrfToken() async {
    try {
      final uri = Uri.parse(
        loginGetTokenUrl,
      ).replace(queryParameters: const {'action': 'login'});
      final resp = await _loginSessionDio.get<dynamic>(uri.toString());
      if (resp.statusCode != 200) {
        errorMessage.value = 'Could not load login security token. (@code)'
            .trParams({'code': '${resp.statusCode}'});
        return false;
      }
      final map = _dioDataAsMap(resp.data);
      if (map == null) {
        errorMessage.value = 'Login security token response was invalid.'.tr;
        return false;
      }
      if (map['status']?.toString() != 'success') {
        errorMessage.value =
            map['error']?.toString() ??
            'Could not load login security token.'.tr;
        return false;
      }
      final token = map['csrf_token']?.toString();
      if (token == null || token.isEmpty) {
        errorMessage.value =
            'Login security token missing. Check @url on the server.'.trParams({
              'url': loginGetTokenUrl,
            });
        return false;
      }
      log('Login CSRF token (action=login): $token');
      sharedPreferences.setString('csrf_token', token);
      return true;
    } on DioException catch (e, stack) {
      log('Login CSRF fetch error: $e', stackTrace: stack);
      final data = _dioDataAsMap(e.response?.data);
      errorMessage.value =
          data?['error']?.toString() ??
          'Could not reach login security endpoint. Check your network.'.tr;
      return false;
    } catch (e, stack) {
      log('Login CSRF fetch error: $e', stackTrace: stack);
      errorMessage.value = 'Could not load login security token.'.tr;
      return false;
    }
  }

  /// POST [insertUserWithPhoneUrl] with JSON `{ phone }` after OTP is OK.
  /// Reuses [_loginSessionDio] so session matches the Send OTP CSRF request.
  Future<Map<String, dynamic>?> _insertUserWithPhone(String phone) async {
    try {
      final loginResp = await _loginSessionDio.post<dynamic>(
        insertUserWithPhoneUrl,
        data: <String, dynamic>{'phone': phone},
        options: Options(contentType: Headers.jsonContentType),
      );

      final code = loginResp.statusCode ?? 0;
      final body = _dioDataAsMap(loginResp.data);

      if (code == 400) {
        errorMessage.value =
            body?['error']?.toString() ?? 'Invalid phone number.'.tr;
        return null;
      }

      if (code != 200 && code != 201) {
        errorMessage.value =
            body?['error']?.toString() ??
            'Phone sign-in failed. (@code)'.trParams({'code': code.toString()});
        return null;
      }

      if (body == null) {
        final raw = loginResp.data?.toString().trim() ?? '';
        final rawInsertedId = int.tryParse(raw);
        if (rawInsertedId != null) {
          return _buildPhoneUser(
            id: rawInsertedId.toString(),
            phone: phone,
            name: _pendingUser?['name']?.toString(),
          );
        }
        errorMessage.value =
            'Phone sign-in endpoint returned an invalid response.'.tr;
        return null;
      }

      final isSuccess = body['status'] == 'success' || body['success'] == true;
      if (!isSuccess) {
        errorMessage.value =
            body['message']?.toString() ??
            body['error']?.toString() ??
            'Could not complete phone sign in. Please try again.'.tr;
        return null;
      }

      final insertedId = _extractInsertedUserId(body);
      if (insertedId == null || insertedId.isEmpty) {
        errorMessage.value =
            'Phone sign-in endpoint returned an invalid response.'.tr;
        return null;
      }

      final userData = body['user'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(body['user'] as Map<String, dynamic>)
          : body['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(body['data'] as Map<String, dynamic>)
          : <String, dynamic>{};

      Map<String, dynamic>? accountMap;
      final accRaw = body['account'];
      if (accRaw is Map) {
        accountMap = flattenAccountMap(Map<String, dynamic>.from(accRaw));
      }

      final resolvedPhone =
          pickFromAccountMap(accountMap, ['phone', 'number', 'phone_number']) ??
          () {
            final p = userData['phone']?.toString().trim();
            return (p != null && p.isNotEmpty) ? p : phone;
          }();

      final resolvedName =
          pickFromAccountMap(accountMap, [
            'full_name',
            'name',
            'display_name',
          ]) ??
          () {
            final n = userData['name']?.toString().trim();
            return (n != null && n.isNotEmpty) ? n : null;
          }() ??
          _pendingUser?['name']?.toString();

      final resolvedEmail =
          pickFromAccountMap(accountMap, ['email']) ??
          userData['email']?.toString();

      final user = _buildPhoneUser(
        id: userData['id']?.toString() ?? insertedId,
        phone: resolvedPhone,
        name: resolvedName,
        email: resolvedEmail,
      );

      if (accountMap != null) {
        user['account'] = accountMap;
      }

      await persistApiSessionFromResponse(body);

      // `auth/login/index.php`: has_role, role_id, returning_user
      final hasRole = body['has_role'] == true || body['has_role'] == 1;
      user['has_role'] = hasRole;
      if (body['returning_user'] != null) {
        user['returning_user'] =
            body['returning_user'] == true || body['returning_user'] == 1;
      }
      final rawRole = body['role_id'];
      if (rawRole != null && rawRole.toString().trim().isNotEmpty) {
        final rid = int.tryParse(rawRole.toString());
        if (rid != null && rid > 0) {
          user['role_id'] = rid;
        }
      }
      if (!hasRole) {
        user.remove('role_id');
      }

      await AppEventFirestore.log(
        eventType: user['returning_user'] == true ? 'login' : 'register',
        eventLabel: user['returning_user'] == true
            ? 'User logged in'
            : 'User registered',
        module: 'auth',
        action: user['returning_user'] == true ? 'login' : 'register',
        userId: int.tryParse(user['id']?.toString() ?? ''),
        roleId: user['role_id'] is int
            ? user['role_id'] as int
            : int.tryParse(user['role_id']?.toString() ?? ''),
        name: resolvedName,
        number: resolvedPhone,
        note: user['returning_user'] == true
            ? 'Phone login succeeded'
            : 'Phone registration succeeded',
      );

      return user;
    } on DioException catch (e, stack) {
      log('Phone sign-in error: $e', stackTrace: stack);
      final data = _dioDataAsMap(e.response?.data);
      errorMessage.value =
          data?['error']?.toString() ??
          'Phone sign-in failed. Please check your internet or API endpoint.'
              .tr;
      return null;
    } catch (e, stack) {
      log('Phone sign-in error: $e', stackTrace: stack);
      errorMessage.value =
          'Phone sign-in failed. Please check your internet or API endpoint.'
              .tr;
      return null;
    }
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
      final String fallbackName = googleUser.email.split('@').first;

      return <String, dynamic>{
        'id': googleUser.id,
        'email': googleUser.email,
        'name':
            (googleUser.displayName != null &&
                googleUser.displayName!.trim().isNotEmpty)
            ? googleUser.displayName!.trim()
            : fallbackName,
      };
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
