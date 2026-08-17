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
///
/// [includeRoleId] false means "somebody else is writing the role for this
/// response, and they know something I do not". Exactly one caller is entitled
/// to say that: `completeSignInAndRoute`, where the sign-in JSON's ROOT carries
/// `has_role` alongside `role_id` — and `has_role: false` is a statement this
/// function cannot make, because it only ever writes a positive role and never
/// removes one. See the note at that call site (core/auth_navigation.dart).
///
/// Everywhere else the default applies and the server's role is written. The
/// role is written only when it is present and positive: a response that omits
/// the field is a server too old to report it, not an account with no role, and
/// the identity_code block below documents why those two must not be conflated.
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

  // K21 — the account's own identity code (GR-/ER-/VL-). Stored so the profile
  // card can show it without waiting on a fetch.
  //
  // WRITE-OR-CLEAR, not write-if-present, and the difference matters. An
  // account that reports an EMPTY code (staff, guests, or somebody whose code
  // was withdrawn) must clear whatever this device had, or the card would name
  // the wrong person. But a server too OLD to report the field sends no key at
  // all, and that is not the same statement — so absence leaves the stored
  // value alone.
  if (account.containsKey('identity_code')) {
    final identityCode = (account['identity_code'] ?? '').toString().trim();
    if (identityCode.isEmpty) {
      await sharedPreferences.remove('identity_code');
    } else {
      await sharedPreferences.setString('identity_code', identityCode);
    }
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

/// The numeric `role_id` that the server's `role_key` names, or null when the
/// key is not one the app can turn into a role.
///
/// The numbers are the ones the rest of the app already switches on —
/// `proposal_services_section` ('2' beneficiary, '3' volunteer, else donor),
/// `sponsorship_section` ('2'), `settings_section` ('3'), `widgets/dashboard`
/// — and 5 is the marriage service, named as such in `ModuleApi.chooseRole`
/// ("a switch INTO the marriage service (5) or back to guest (0)").
///
/// 'guest' MAPS TO NOTHING ON PURPOSE, and this is the part that would be easy
/// to get wrong. `RoleDashboardController.roleKey` is seeded with 'guest' and
/// falls back to 'guest' whenever the summary cannot be read, so 'guest' is
/// this app's "I do not know" as much as it is a role. Writing it back would
/// let one failed poll demote a real account. Anything unrecognised — a role
/// key added server-side after this build shipped, 'employee' — is left alone
/// for the same reason: silence is not a statement.
String? roleIdForServerRoleKey(String roleKey) => switch (roleKey.trim()) {
  'donor' => '1',
  'beneficiary' => '2',
  'volunteer' => '3',
  'marriage' => '5',
  _ => null,
};

/// Makes the locally stored `role_id` follow the role the server just reported.
///
/// WHY THIS EXISTS (the drift it fixes)
/// SharedPreferences held `flutter.role_id = "1"` (donor) for an account the
/// server reports as `role_id: 2` (beneficiary), confirmed against the
/// simulator's plist and `GET /api/admin/users`. The local copy is written when
/// the account registers (`registration_api.dart`), when it signs in
/// (`core/auth_navigation.dart`) and when the user changes it themselves
/// (`ModuleApi.chooseRole`) — that is, at the moments the USER acts. Nothing
/// wrote it when the SERVER acted, which is the common case: staff grant the
/// Recipient and Volunteer roles after vetting, and `chooseRole` refuses those
/// outright ("Recipient/Volunteer are granted by staff"). So a promoted account
/// kept behaving as a donor on every screen gated on the local value —
/// Services, Kafala, Settings, the assistant, notification filters — until the
/// app was cold-started or the profile tab happened to be opened.
///
/// The app was already being told the truth and discarding it. Every dashboard
/// summary carries `role_key`, the profile menu's own comment says outright
/// that "the backend is the source of truth for the role", and
/// `widgets/dashboard._roleKey` already prefers that value over the stored one
/// — a local workaround that fixed the home screen's body and nothing else.
/// This writes the same answer back to the one place every other screen reads.
///
/// Returns true when the stored value actually changed, so a caller can react
/// (and so the fix is observable in a test rather than inferred).
Future<bool> applyServerRoleKeyToSharedPreferences(String roleKey) async {
  final roleId = roleIdForServerRoleKey(roleKey);
  if (roleId == null) return false;
  if (sharedPreferences.getString('role_id') == roleId) return false;
  await sharedPreferences.setString('role_id', roleId);
  return true;
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
      // DELIBERATE: this is a fallback CHAIN over two account endpoints, not a
      // swallow. A failure on one base is exactly the condition for trying the
      // next; if every base fails the loop falls through to `return null`,
      // which is the failure signal callers already branch on.
      continue;
    } catch (_) {
      // Same reason as the DioException branch above — try the next base URL.
      continue;
    }
  }
  // Every base failed (or returned an unusable body): null tells the caller
  // the account could not be loaded. It never fabricates an account map.
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
    this.pendingReview = const <String>[],
  }) : ok = true,
       errorMessage = null;

  const ProfileUpdateResult.failure(this.errorMessage)
    : ok = false,
      fullName = null,
      address = null,
      gender = null,
      profilePictureUrl = null,
      pendingReview = const <String>[];

  final bool ok;
  final String? errorMessage;
  final String? fullName;
  final String? address;
  final String? gender;
  final String? profilePictureUrl;

  /// Fields the server queued for staff review instead of applying (E17).
  ///
  /// Values are the server's own field names — `full_name`, `profile_picture`
  /// (`backend/internal/profilechanges/profilechanges.go`). An empty list means
  /// everything the user submitted is already live.
  ///
  /// The server has sent this since migration 093, with a comment saying it
  /// exists "so the app can say 'waiting for approval'". Nothing read it, so
  /// the app said "saved" either way.
  final List<String> pendingReview;

  /// True when the user's new name is queued and the live profile still shows
  /// the old one.
  bool get isNamePending => pendingReview.contains(fieldFullName);

  /// True when the user's new photo is queued and the avatar still shows the
  /// old one (or none).
  bool get isPicturePending => pendingReview.contains(fieldProfilePicture);
}

/// The two reviewable field names, mirroring the Go constants so no call site
/// writes the literal twice (`profilechanges.FieldFullName` / `FieldPicture`).
const String fieldFullName = 'full_name';
const String fieldProfilePicture = 'profile_picture';

/// What to tell the user after a profile save, given what the server actually
/// did with it.
///
/// E17 — the screen used to say "Your profile details have been saved" no
/// matter what. When the name or the photo is queued for review that sentence
/// is false: the live profile still shows the old value, and the user walks
/// away believing a change landed that nobody has approved.
///
/// Pure and separate from the widget so the decision can be tested without
/// pumping a screen or mocking an upload — the branch is the part that was
/// wrong, not the snackbar.
///
/// Returns an untranslated (title, body) pair; the caller applies `.tr`.
({String title, String body}) profileSaveMessage(ProfileUpdateResult result) {
  final name = result.isNamePending;
  final picture = result.isPicturePending;

  if (!name && !picture) {
    return (
      title: 'Profile updated',
      body: 'Your profile details have been saved.',
    );
  }
  // "Your other details are saved" is load-bearing: address and gender DO
  // apply immediately, so a message that only mentioned the review would be
  // just as misleading in the other direction.
  const title = 'Saved — waiting for approval';
  if (name && picture) {
    return (
      title: title,
      body:
          'Your other details are saved. Your new name and photo need staff approval before they appear.',
    );
  }
  if (name) {
    return (
      title: title,
      body:
          'Your other details are saved. Your new name needs staff approval before it appears.',
    );
  }
  return (
    title: title,
    body:
        'Your other details are saved. Your new photo needs staff approval before it appears.',
  );
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
      // E17 — `pending_review` lists the fields the server QUEUED rather than
      // applied. Absent on an older server, which is why the default is an
      // empty list rather than a null: "no key" and "nothing queued" mean the
      // same thing to every caller.
      final pendingRaw = body['pending_review'];
      final pending = pendingRaw is List
          ? pendingRaw.map((e) => e.toString()).toList(growable: false)
          : const <String>[];
      return ProfileUpdateResult.success(
        fullName: resolvedFullName,
        address: resolvedAddress,
        gender: resolvedGender,
        profilePictureUrl: resolveProfilePictureUrl(body['profile_picture']),
        pendingReview: pending,
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
