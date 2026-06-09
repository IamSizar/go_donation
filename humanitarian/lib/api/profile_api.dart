import 'package:flutter_application_1/api/auth_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:flutter_application_1/core/app_state.dart';

/// Fixes bad absolute URLs from the server or older app builds.
String? normalizeProfilePictureUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  var s = url.trim();

  // Was resolved under .../api/images/ → should be .../<project>/images/
  const wrong = '/api/images/';
  if (s.contains(wrong)) {
    s = s.replaceFirst(wrong, '/images/');
  }

  final site = Uri.tryParse(publicBaseUrl);
  final parsed = Uri.tryParse(s);
  if (site == null || parsed == null || !parsed.hasScheme) return s;

  final sameHost = parsed.host == site.host && parsed.port == site.port;
  if (!sameHost) return s;

  final basePath = site.path.endsWith('/') ? site.path : '${site.path}/';
  final underProject = parsed.path.startsWith('$basePath/images/');

  // Wrong: http://host:8888/images/... (missing project folder). Right: .../easy_tech_test/images/...
  if (parsed.path.startsWith('/images/') && !underProject) {
    final rel = parsed.path.startsWith('/')
        ? parsed.path.substring(1)
        : parsed.path;
    final base = publicBaseUrl.endsWith('/')
        ? publicBaseUrl
        : '$publicBaseUrl/';
    return Uri.parse(base).resolve(rel).toString();
  }

  return s;
}

/// Merges nested `user` / `profile` / `data` maps into one map (common API shapes).
Map<String, dynamic> flattenAccountMap(Map<String, dynamic> raw) {
  final out = Map<String, dynamic>.from(raw);
  for (final key in ['user', 'profile', 'data']) {
    final inner = out[key];
    if (inner is Map) {
      out.addAll(Map<String, dynamic>.from(inner));
    }
  }
  return out;
}

/// First non-empty string among [keys] on [account] (skips literal `NULL`).
String? pickFromAccountMap(Map<String, dynamic>? account, List<String> keys) {
  if (account == null) return null;
  for (final k in keys) {
    final v = account[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'NULL') continue;
    return s;
  }
  return null;
}

bool _hasProfileImageInAccount(Map<String, dynamic> account) {
  final picRaw = _firstNonEmptyAccountValue(account, _profilePictureKeys);
  return resolveProfilePictureUrl(picRaw)?.isNotEmpty == true;
}

List<String> missingProfileFieldsFromAccount(Map<String, dynamic> rawAccount) {
  final account = flattenAccountMap(Map<String, dynamic>.from(rawAccount));
  final missing = <String>[];
  if ((pickFromAccountMap(account, [
            'full_name',
            'fullName',
            'name',
            'display_name',
            'displayName',
            'username',
            'user_name',
          ]) ??
          '')
      .isEmpty) {
    missing.add('Full name');
  }
  if ((pickFromAccountMap(account, ['address', 'location']) ?? '').isEmpty) {
    missing.add('Address');
  }
  if ((pickFromAccountMap(account, ['gender', 'sex']) ?? '').isEmpty) {
    missing.add('Gender');
  }
  if (!_hasProfileImageInAccount(account)) {
    missing.add('Profile picture');
  }
  return missing;
}

List<String> missingProfileFieldsFromPreferences() {
  final missing = <String>[];
  final name = sharedPreferences.getString('name_user')?.trim() ?? '';
  final address = sharedPreferences.getString('address_user')?.trim() ?? '';
  final gender = sharedPreferences.getString('gender_user')?.trim() ?? '';
  final localImage =
      sharedPreferences.getString('profile_image_path')?.trim() ?? '';
  final remoteImage = normalizeProfilePictureUrl(
    sharedPreferences.getString('profile_picture_url'),
  );
  if (name.isEmpty) missing.add('Full name');
  if (address.isEmpty) missing.add('Address');
  if (gender.isEmpty) missing.add('Gender');
  if (localImage.isEmpty && (remoteImage == null || remoteImage.isEmpty)) {
    missing.add('Profile picture');
  }
  return missing;
}

bool isProfileCompleteFromPreferences() {
  return missingProfileFieldsFromPreferences().isEmpty;
}

Future<void> syncProfileCompletionPreference({
  List<String>? missingFields,
}) async {
  final missing = missingFields ?? missingProfileFieldsFromPreferences();
  final doneProfile = missing.isEmpty ? 1 : 0;
  await sharedPreferences.setInt('done_profile', doneProfile);
  profileIncompleteNotifier.value = missing.isNotEmpty;
}

const _profilePictureKeys = <String>[
  'profile_picture',
  'profile_picture_url',
  'profile_image',
  'profile_image_url',
  'photo',
  'photo_url',
  'avatar',
  'avatar_url',
  'picture',
  'image',
  'image_url',
];

dynamic _firstNonEmptyAccountValue(
  Map<String, dynamic> account,
  List<String> keys,
) {
  for (final k in keys) {
    final v = account[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'NULL') continue;
    return v;
  }
  return null;
}

/// Persists fields from [account] (shape from `getUserAccountForClient`) into prefs.
/// Set [includeRoleId] false when role already came from the login JSON root.
Future<void> applyUserAccountToSharedPreferences(
  Map<String, dynamic> rawAccount, {
  bool includeRoleId = true,
}) async {
  final account = flattenAccountMap(Map<String, dynamic>.from(rawAccount));

  final phone = pickFromAccountMap(account, [
    'phone',
    'number',
    'phone_number',
    'mobile',
  ]);
  if (phone != null) {
    await sharedPreferences.setString('phone_user', phone);
  }

  final name = pickFromAccountMap(account, [
    'full_name',
    'fullName',
    'name',
    'display_name',
    'displayName',
    'username',
    'user_name',
  ]);
  if (name != null) {
    await sharedPreferences.setString('name_user', name);
  }

  final email = pickFromAccountMap(account, ['email', 'email_address']);
  if (email != null) {
    await sharedPreferences.setString('email_user', email);
  }

  final address = pickFromAccountMap(account, ['address', 'location']);
  if (address != null) {
    await sharedPreferences.setString('address_user', address);
  }

  final gender = pickFromAccountMap(account, ['gender', 'sex']);
  if (gender != null) {
    await sharedPreferences.setString('gender_user', gender);
  }

  final picRaw = _firstNonEmptyAccountValue(account, _profilePictureKeys);
  final pic = resolveProfilePictureUrl(picRaw);
  if (pic != null && pic.isNotEmpty) {
    await sharedPreferences.setString('profile_picture_url', pic);
    await sharedPreferences.remove('profile_image_path');
  }

  final doneRaw = account['done_profile'] ?? account['profile_complete'];
  if (doneRaw != null) {
    final n = int.tryParse(doneRaw.toString());
    if (n != null) {
      await sharedPreferences.setInt('done_profile', n);
    } else if (doneRaw == true) {
      await sharedPreferences.setInt('done_profile', 1);
    }
  }

  if (includeRoleId) {
    final roleRaw = account['role_id'];
    final roleInt = roleRaw is int
        ? roleRaw
        : int.tryParse(roleRaw?.toString() ?? '');
    if (roleInt != null && roleInt > 0) {
      await sharedPreferences.setString('role_id', roleInt.toString());
    }
  }

  final missingFields = missingProfileFieldsFromAccount(account);
  await syncProfileCompletionPreference(missingFields: missingFields);
}

Map<String, dynamic>? _parseAccountGetResponse(Response<dynamic> response) {
  final code = response.statusCode ?? 0;
  final data = response.data;
  if (data is! Map) return null;
  final map = Map<String, dynamic>.from(data);
  if (code != 200) return null;
  if (map['status']?.toString() != 'success') return null;
  final acc = map['account'];
  if (acc is! Map) return null;
  return flattenAccountMap(Map<String, dynamic>.from(acc));
}

/// GET `?user_id=` — `status: success`, `account`. Tries [profileApiUrlGet] then [accountGetUrlAlternate].
Future<Map<String, dynamic>?> fetchUserAccount(int userId) async {
  if (userId <= 0) return null;
  final dio = Dio(
    BaseOptions(
      validateStatus: (status) => status != null && status < 600,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: withApiAuthHeaders(),
    ),
  );
  final bases = <String>{profileApiUrlGet, accountGetUrlAlternate};
  for (final base in bases) {
    try {
      final uri = Uri.parse(base).replace(
        queryParameters: withApiAuthQueryParameters({'user_id': '$userId'}),
      );
      final response = await dio.get<dynamic>(
        uri.toString(),
        options: withApiAuthOptions(),
      );
      final parsed = _parseAccountGetResponse(response);
      if (parsed != null) {
        return parsed;
      }
    } on DioException catch (_) {
      continue;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Turns a DB-relative path from the API into a loadable image URL.
String? resolveProfilePictureUrl(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return normalizeProfilePictureUrl(s);
  }
  final base = Uri.parse(baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  if (s.startsWith('/')) {
    return normalizeProfilePictureUrl('$origin$s');
  }
  final site = Uri.parse(publicBaseUrl);
  return normalizeProfilePictureUrl(site.resolve(s).toString());
}

class ProfileUpdateResult {
  const ProfileUpdateResult.success({
    required this.fullName,
    required this.address,
    required this.gender,
    this.profilePictureUrl,
  }) : ok = true,
       errorMessage = null;

  const ProfileUpdateResult.failure(this.errorMessage)
    : ok = false,
      fullName = null,
      address = null,
      gender = null,
      profilePictureUrl = null;

  final bool ok;
  final String? errorMessage;
  final String? fullName;
  final String? address;
  final String? gender;
  final String? profilePictureUrl;
}

Future<void> _sendProfileUpdateEventToFirestore({
  required int userId,
  required String fullName,
}) async {
  try {
    final phone = sharedPreferences.getString('phone_user')?.trim() ?? '';
    await AppEventFirestore.log(
      eventType: 'profile_update',
      eventLabel: 'Profile updated',
      module: 'profile',
      action: 'update',
      userId: userId,
      name: fullName.trim(),
      number: phone,
      note: 'User updated profile details from the app.',
    );
  } catch (_) {
    // Keep profile save successful even if analytics/event logging fails.
  }
}

/// POST multipart: user_id, full_name, address, gender; optional file field [profile_picture].
Future<ProfileUpdateResult> updateUserProfile({
  required int userId,
  required String fullName,
  required String address,
  required String gender,
  String? localImagePath,
  bool removeProfilePicture = false,
}) async {
  final dio = Dio(
    BaseOptions(
      validateStatus: (status) => status != null && status < 500,
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: withApiAuthHeaders(),
    ),
  );

  final map = <String, dynamic>{
    'user_id': userId.toString(),
    'full_name': fullName,
    'address': address,
    'gender': gender,
    if (removeProfilePicture) 'remove_profile_picture': '1',
  };
  final token = apiAuthTokenFieldValue();
  if (token != null && token.isNotEmpty) {
    map['access_token'] = token;
  }

  if (!removeProfilePicture &&
      localImagePath != null &&
      localImagePath.isNotEmpty) {
    map['profile_picture'] = await MultipartFile.fromFile(
      localImagePath,
      filename: localImagePath.split(RegExp(r'[/\\]')).last,
    );
  }

  final formData = FormData.fromMap(map);

  try {
    final response = await dio.post<dynamic>(
      profileApiUrlSet,
      data: formData,
      options: withApiAuthOptions(),
    );
    final status = response.statusCode ?? 0;
    final data = response.data;

    if (data is! Map) {
      return ProfileUpdateResult.failure('Invalid server response.');
    }

    final body = Map<String, dynamic>.from(data);
    if (status == 200 && body['success'] == true) {
      final resolvedFullName = (body['full_name'] ?? fullName).toString();
      final resolvedAddress = (body['address'] ?? address).toString();
      final resolvedGender = (body['gender'] ?? gender).toString();
      await _sendProfileUpdateEventToFirestore(
        userId: userId,
        fullName: resolvedFullName,
      );
      return ProfileUpdateResult.success(
        fullName: resolvedFullName,
        address: resolvedAddress,
        gender: resolvedGender,
        profilePictureUrl: resolveProfilePictureUrl(body['profile_picture']),
      );
    }

    final err = body['error']?.toString();
    return ProfileUpdateResult.failure(
      err?.isNotEmpty == true ? err! : 'Request failed ($status).',
    );
  } on DioException catch (e) {
    final msg = e.message ?? e.toString();
    return ProfileUpdateResult.failure(msg);
  } catch (e) {
    return ProfileUpdateResult.failure(e.toString());
  }
}
