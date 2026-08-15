import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:http/http.dart' as http;

class ModuleApi {
  const ModuleApi();

  /// How long any single request may hang before it is treated as a failure.
  ///
  /// This file had NO timeout at all, unlike wallet_api and task_api which
  /// both use 12s. That is not a tidiness point: a request that never returns
  /// also never runs its caller's `finally`, so a screen's `isLoading` stays
  /// true forever. The home dashboard was caught in exactly that state against
  /// a hanging backend — a skeleton with no error and no retry, permanently,
  /// because its only non-silent load was the one that hung and the 10s poll
  /// that follows is silent by design.
  ///
  /// A timeout converts "hangs forever" into "fails", and this app already
  /// knows how to show a failure.
  static const Duration _requestTimeout = Duration(seconds: 12);

  String _normalizedUrl(String url) {
    final parsed = Uri.parse(url);
    final path = parsed.path.endsWith('/') && parsed.path.length > 1
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    return path;
  }

  Future<void> _trackEvent(
    String url,
    Map<String, dynamic> requestBody,
    Map<String, dynamic> responseBody,
  ) async {
    final path = _normalizedUrl(url);
    final action = requestBody['action']?.toString().trim();
    final entityId = responseBody['id'] is int
        ? responseBody['id'] as int
        : int.tryParse(responseBody['id']?.toString() ?? '');

    if (path.endsWith('/beneficiary_cases')) {
      await AppEventFirestore.log(
        eventType: 'beneficiary_case_submit',
        eventLabel: 'Beneficiary case submitted',
        module: 'beneficiary_cases',
        action: 'submit',
        entityId: entityId,
        note: requestBody['public_title']?.toString(),
        metadata: {
          'city': requestBody['city'],
          'priority_level': requestBody['priority_level'],
        },
      );
      return;
    }

    if (path.endsWith('/sponsorships')) {
      await AppEventFirestore.log(
        eventType: action == 'cancel'
            ? 'sponsorship_cancel'
            : 'sponsorship_submit',
        eventLabel: action == 'cancel'
            ? 'Sponsorship cancelled'
            : 'Sponsorship submitted',
        module: 'sponsorships',
        action: action == 'cancel' ? 'cancel' : 'submit',
        entityId: entityId,
        targetId: int.tryParse(
          requestBody['project_request_id']?.toString() ?? '',
        ),
        amount: num.tryParse(requestBody['amount']?.toString() ?? ''),
        currency: requestBody['currency']?.toString(),
        note: requestBody['sponsorship_type']?.toString(),
      );
      return;
    }

    if (path.endsWith('/in_kind_donations')) {
      await AppEventFirestore.log(
        eventType: 'in_kind_donation_submit',
        eventLabel: 'In-kind donation submitted',
        module: 'in_kind_donations',
        action: 'submit',
        entityId: entityId,
        note: requestBody['item_name']?.toString(),
        metadata: {
          'category': requestBody['category'],
          'quantity': requestBody['quantity'],
        },
      );
      return;
    }

    if (path.endsWith('/marriage')) {
      await AppEventFirestore.log(
        eventType: 'marriage_profile_submit',
        eventLabel: 'Marriage profile submitted',
        module: 'marriage',
        action: 'submit',
        entityId: entityId,
        note: requestBody['city']?.toString(),
        metadata: {'gender': requestBody['gender'], 'age': requestBody['age']},
      );
      return;
    }

    if (path.endsWith('/support')) {
      await AppEventFirestore.log(
        eventType: 'support_ticket_submit',
        eventLabel: 'Support ticket submitted',
        module: 'support',
        action: 'submit',
        entityId: entityId,
        note: requestBody['subject']?.toString(),
      );
      return;
    }

    if (path.endsWith('/volunteer_hub')) {
      await AppEventFirestore.log(
        eventType: action == 'join_mission'
            ? 'volunteer_mission_join'
            : 'volunteer_application_submit',
        eventLabel: action == 'join_mission'
            ? 'Volunteer mission joined'
            : 'Volunteer application submitted',
        module: 'volunteer_hub',
        action: action == 'join_mission' ? 'join_mission' : 'submit',
        entityId: entityId,
        targetId: int.tryParse(requestBody['mission_id']?.toString() ?? ''),
        note: requestBody['full_name']?.toString(),
        metadata: {
          'city': requestBody['city'],
          'skills': requestBody['skills'],
        },
      );
      return;
    }

    if (path.endsWith('/marketplace') && requestBody['product_id'] != null) {
      await AppEventFirestore.log(
        eventType: 'marketplace_order_submit',
        eventLabel: 'Marketplace order submitted',
        module: 'marketplace',
        action: 'checkout',
        entityId: entityId,
        targetId: int.tryParse(requestBody['product_id']?.toString() ?? ''),
        note: 'Marketplace order from app cart',
        metadata: {'quantity': requestBody['quantity']},
      );
      return;
    }

    if (path.endsWith('/notifications') && action == 'mark_read') {
      await AppEventFirestore.log(
        eventType: 'notification_mark_read',
        eventLabel: 'Notification marked read',
        module: 'notifications',
        action: 'mark_read',
        targetId: int.tryParse(requestBody['id']?.toString() ?? ''),
      );
    }
  }

  dynamic _decodeJson(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      // NOT a swallow: this catch does real work and then always throws. The
      // decode failure is the evidence, and the body is inspected to turn a
      // PHP fatal-error page into a message a human can act on.
      final body = response.body.trim();
      final looksLikeHtml =
          body.startsWith('<!DOCTYPE html') ||
          body.startsWith('<html') ||
          body.startsWith('<br') ||
          body.contains('<b>Fatal error</b>') ||
          body.contains('Warning</b>');
      if (looksLikeHtml) {
        throw Exception(
          'The server returned an invalid response. Please refresh or contact support.',
        );
      }
      throw Exception('Invalid response from server.');
    }
  }

  /// Authed GET.
  ///
  /// 27.2 added a "self-heal" retry here: on a 401/403 it re-derived a token
  /// from the stored phone number and replayed the request. A16 removed it,
  /// because that re-derivation was the authentication hole — the server no
  /// longer trades a phone number for a session, so the retry could only ever
  /// fail, and the refresh it called cleared the caller's still-valid token on
  /// the way (which is how a plain 403 — an approval gate, a guest
  /// restriction — used to sign a working user out).
  ///
  /// A 401/403 is now surfaced to the caller, which renders the screen's
  /// designed error state; the next launch routes an expired session to
  /// sign-in.
  Future<http.Response> _authedGet(String url) async {
    Uri buildUri() => Uri.parse(url).replace(
      queryParameters: withApiAuthQueryParameters(
        Uri.parse(url).queryParameters,
      ),
    );
    return http
        .get(buildUri(), headers: withApiAuthHeaders())
        .timeout(_requestTimeout);
  }

  Future<List<Map<String, dynamic>>> getItems(String url) async {
    final response = await _authedGet(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed (${response.statusCode})');
    }
    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception(
        decoded is Map
            ? decoded['error']?.toString() ?? 'Request failed'
            : 'Request failed',
      );
    }
    final items = decoded['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getObject(String url) async {
    final response = await _authedGet(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed (${response.statusCode})');
    }
    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception(
        decoded is Map
            ? decoded['error']?.toString() ?? 'Request failed'
            : 'Request failed',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body,
  ) async {
    final enrichedBody = withApiAuthJsonBody(body);
    final response = await http
        .post(
          Uri.parse(url),
          headers: withApiAuthHeaders(const {
            'Content-Type': 'application/json',
          }),
          body: jsonEncode(enrichedBody),
        )
        .timeout(_requestTimeout);
    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Request failed');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Request failed');
    }
    await _trackEvent(url, enrichedBody, decoded);
    return decoded;
  }

  /// Same as [postJson] but WITHOUT firing [_trackEvent]. Used by the activity
  /// event logger itself (posting an event must never recursively log another
  /// event), and for any call that shouldn't generate analytics.
  Future<Map<String, dynamic>> postJsonNoTrack(
    String url,
    Map<String, dynamic> body,
  ) async {
    final enrichedBody = withApiAuthJsonBody(body);
    final response = await http
        .post(
          Uri.parse(url),
          headers: withApiAuthHeaders(const {
            'Content-Type': 'application/json',
          }),
          body: jsonEncode(enrichedBody),
        )
        .timeout(_requestTimeout);
    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Request failed');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Request failed');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> marketplaceProducts() =>
      getItems(marketplaceProductsUrl);

  /// #28 — admin-managed marketplace categories for name lookup + filter chips.
  Future<List<Map<String, dynamic>>> marketplaceCategories() =>
      getItems(marketplaceCategoriesUrl);

  Future<List<Map<String, dynamic>>> communityDirectory({String? q}) {
    // #33 — optional q so a single-entry lookup isn't capped by the default
    // page limit (see _fetchPlaceEntry in global_search_screen.dart).
    if (q != null && q.isNotEmpty) {
      final uri = Uri.parse(
        communityDirectoryUrl,
      ).replace(queryParameters: {'q': q});
      return getItems(uri.toString());
    }
    return getItems(communityDirectoryUrl);
  }

  Future<List<Map<String, dynamic>>> citySectors() => getItems(citySectorsUrl);

  Future<Map<String, dynamic>> submitCommunity(Map<String, dynamic> body) =>
      postJson(communitySubmitUrl, body);

  // #31 — per-user notification switch.
  Future<bool> getNotificationSetting() async {
    final res = await getObject(notificationSettingUrl);
    return res['enabled'] == true;
  }

  Future<bool> setNotificationSetting(bool enabled) async {
    final res = await postJson(notificationSettingUrl, {'enabled': enabled});
    return res['enabled'] == true;
  }

  /// "Eleventh: Partners Section" — activities implemented with a partner.
  ///
  /// THROWS on failure. The old doc said it returned an empty list "so the
  /// Partner Page shows its empty state rather than an error" — which names
  /// the bug precisely: the empty state asserts this partner has run no
  /// activities, and that assertion is false when the request simply failed.
  Future<List<Map<String, dynamic>>> partnerActivities(int partnerId) async {
    final res = await getObject(partnerActivitiesUrl(partnerId));
    final raw = res['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Switch the signed-in user's own account type.
  ///
  /// The backend only honours a switch INTO the marriage service (5) or back
  /// to guest (0); Recipient/Volunteer are granted by staff after vetting, and
  /// a request for those comes back with role_unchanged:true rather than an
  /// error. Returns the role_id actually in effect afterwards.
  Future<int> chooseRole(int roleId) async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) {
      throw Exception('No user ID found. Please sign in again.');
    }
    final res = await postJson(chooseRoleUrl, {
      'user_id': userId,
      'role_id': roleId,
    });
    final applied = (res['role_id'] as num?)?.toInt() ?? roleId;
    await sharedPreferences.setString('role_id', applied.toString());
    return applied;
  }

  // #32 — profile field privacy (list of hidden field keys).
  Future<List<String>> getFieldPrivacy() async {
    final res = await getObject(fieldPrivacyUrl);
    final raw = res['hidden'];
    return raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
  }

  Future<void> setFieldPrivacy(List<String> hidden) =>
      postJson(fieldPrivacyUrl, {'hidden': hidden});

  /// Privacy Settings spec ("Future Development") — the server-managed list
  /// of toggleable fields. Returns an empty list on failure; the caller falls
  /// back to its built-in defaults so the screen still works offline.
  /// "Eighth: Sponsorship Schedule and Calendar" — the caller's schedule
  /// occurrences, optionally filtered by status.
  ///
  /// THROWS on failure. The old behaviour returned an empty list "so the
  /// tracking screen can show its empty state rather than an error dead end".
  /// The dead end was the real problem and it has since been fixed properly —
  /// the screen now has an error state WITH a retry — so the workaround can
  /// go, and with it the false claim that a sponsor has no upcoming payments.
  Future<List<ScheduleOccurrence>> getSponsorshipSchedule({
    String status = '',
  }) async {
    final url = status.isEmpty
        ? sponsorshipScheduleUrl
        : '$sponsorshipScheduleUrl?status=$status';
    final res = await getObject(url);
    final raw = res['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ScheduleOccurrence.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Donations Page spec — whether the project list and the Comprehensive
  /// Grant option are shown. Falls back to both enabled on failure.
  ///
  /// DELIBERATELY still swallows, unlike its neighbours in this file. These
  /// are FEATURE FLAGS, not the user's data: falling back to "both enabled"
  /// shows the standard donate screen, which tells the user nothing false
  /// about themselves. Compare the wallet, where the equivalent fallback
  /// asserted a specific balance of zero. The test for whether a default is
  /// acceptable is not "does it avoid a crash" but "does it state something
  /// untrue to the user".
  Future<DonationOptions> getDonationOptions() async {
    try {
      final res = await getObject(donationOptionsUrl);
      return DonationOptions(
        projectsVisible: res['projects_visible'] != false,
        comprehensiveEnabled: res['comprehensive_enabled'] != false,
      );
    } catch (_) {
      // DELIBERATE — see the doc comment above: feature flags, not user data.
      return const DonationOptions();
    }
  }

  /// The per-field privacy toggles this user can set.
  ///
  /// THROWS on failure. Returning `[]` rendered a privacy screen with nothing
  /// on it, which reads as "there is nothing here you can control" — a bad
  /// thing to tell someone wrongly on a privacy screen specifically.
  Future<List<PrivacyFieldOption>> getPrivacyOptions() async {
    final res = await getObject(privacyOptionsUrl);
    final raw = res['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (e) => PrivacyFieldOption(
            fieldKey: (e['field_key'] ?? '').toString(),
            labelKey: (e['label_key'] ?? '').toString(),
            defaultHidden: e['default_hidden'] == true,
          ),
        )
        .where((o) => o.fieldKey.isNotEmpty)
        .toList();
  }

  // Privacy Settings spec — display-name choice (real name vs. alias) and
  // optional social media links.
  Future<Map<String, dynamic>> getPrivacyExtras() async {
    final res = await getObject(privacyExtrasUrl);
    final extras = res['extras'];
    return extras is Map
        ? Map<String, dynamic>.from(extras)
        : <String, dynamic>{};
  }

  Future<void> setPrivacyExtras({
    required String displayNameMode,
    required String aliasName,
    required String facebook,
    required String instagram,
    required String telegram,
  }) => postJson(privacyExtrasUrl, {
    'display_name_mode': displayNameMode,
    'alias_name': aliasName,
    'social_facebook': facebook,
    'social_instagram': instagram,
    'social_telegram': telegram,
  });

  // #33 — global search across the app's content. perType overrides the
  // backend's default per-category cap (see search.go) so callers can fetch
  // one extra row to detect truncation.
  Future<List<Map<String, dynamic>>> globalSearch(String q, {int? perType}) {
    var url = '$globalSearchUrl?q=${Uri.encodeQueryComponent(q)}';
    if (perType != null) url += '&per_type=$perType';
    return getItems(url);
  }

  // #42 — create a marriage/engagement profile.
  Future<Map<String, dynamic>> submitMarriage(Map<String, dynamic> body) =>
      postJson(marriageSubmitUrl, body);

  // #46 — search marriage profiles (q + gender). Client note — Marriage
  // "Search": extended with marital status/religion/employment status/
  // weight/height, each only meaningful when staff enabled it as a filter
  // (the caller is responsible for only passing values for enabled ones).
  Future<List<Map<String, dynamic>>> searchMarriage({
    String q = '',
    String gender = '',
    int minAge = 0,
    int maxAge = 0,
    String maritalStatus = '',
    String religion = '',
    String employmentStatus = '',
    int minWeight = 0,
    int maxWeight = 0,
    int minHeight = 0,
    int maxHeight = 0,
    int beforeId = 0,
  }) {
    final params = <String, String>{'status': 'active'};
    if (q.trim().isNotEmpty) params['q'] = q.trim();
    if (gender.trim().isNotEmpty) params['gender'] = gender.trim();
    if (minAge > 0) params['min_age'] = '$minAge';
    if (maxAge > 0) params['max_age'] = '$maxAge';
    if (maritalStatus.trim().isNotEmpty) {
      params['marital_status'] = maritalStatus.trim();
    }
    if (religion.trim().isNotEmpty) params['religion'] = religion.trim();
    if (employmentStatus.trim().isNotEmpty) {
      params['employment_status'] = employmentStatus.trim();
    }
    if (minWeight > 0) params['min_weight'] = '$minWeight';
    if (maxWeight > 0) params['max_weight'] = '$maxWeight';
    if (minHeight > 0) params['min_height'] = '$minHeight';
    if (maxHeight > 0) params['max_height'] = '$maxHeight';
    // Marriage Posts — cursor pagination for the continuous feed (older
    // profiles than the last card seen); unused by the filtered Search screen.
    if (beforeId > 0) params['before_id'] = '$beforeId';
    final uri = Uri.parse(marriageSubmitUrl).replace(queryParameters: params);
    return getItems(uri.toString());
  }

  // Client note — Marriage "Subscription": active packages the user can buy.
  Future<List<Map<String, dynamic>>> fetchMarriageSubscriptionPackages() =>
      getItems('$marriageSubmitUrl/subscription-packages');

  // Purchases a subscription package. paymentMethod is 'app_wallet' or a
  // payment_methods.slug (cash/bank); wallet activates instantly, everything
  // else stays pending until staff confirms it.
  Future<Map<String, dynamic>> purchaseMarriageSubscription(
    int packageId,
    String paymentMethod,
  ) => postJson(
    '$marriageSubmitUrl/subscription-packages/$packageId/purchase',
    {'payment_method': paymentMethod},
  );

  // #46 — toggle-save a profile; returns the resulting saved state.
  Future<bool> toggleSaveMarriage(int profileId) async {
    final res = await postJson('$marriageSubmitUrl/$profileId/save', {});
    return res['saved'] == true;
  }

  // #46 — request a meeting about a profile.
  /// [requestType] is one of 'meeting' (in person), 'intermediary' (handled by
  /// a staff member) or 'visit'. The backend normalises anything else back to
  /// 'meeting', which is what the single old button meant.
  Future<void> requestMarriageMeeting(
    int profileId,
    String message, {
    String requestType = 'meeting',
  }) => postJson('$marriageSubmitUrl/$profileId/request-meeting', {
    'request_type': requestType,
    'message': message,
  });

  // Note #35 — staff-mediated marriage chat. My threads (identity-masked —
  // the other party is only ever a profile_code or a generic placeholder,
  // never a real name/phone).
  Future<List<Map<String, dynamic>>> marriageChats() =>
      getItems(marriageChatsUrl);

  // Only the profile owner may accept/decline (enforced server-side too).
  Future<Map<String, dynamic>> acceptMarriageChat(int threadId) =>
      postJson('$marriageChatsUrl/$threadId/accept', {});

  Future<Map<String, dynamic>> declineMarriageChat(int threadId) =>
      postJson('$marriageChatsUrl/$threadId/decline', {});

  // Returns {status, items} — status gates whether the reply box shows.
  Future<Map<String, dynamic>> marriageChatMessages(int threadId) =>
      getObject('$marriageChatsUrl/$threadId/messages');

  Future<Map<String, dynamic>> sendMarriageChatMessage(
    int threadId,
    String body,
  ) => postJson('$marriageChatsUrl/$threadId/messages', {'body': body});

  // Note #36 — Staff↔Volunteer↔Beneficiary chat. Opens automatically once a
  // volunteer's signup is linked to a case and approved (or further along);
  // real identities, no accept/decline step needed (staff already confirmed
  // the pairing by approving the signup).
  Future<List<Map<String, dynamic>>> caseChats() => getItems(caseChatsUrl);

  Future<Map<String, dynamic>> caseChatMessages(int threadId) =>
      getObject('$caseChatsUrl/$threadId/messages');

  Future<Map<String, dynamic>> sendCaseChatMessage(int threadId, String body) =>
      postJson('$caseChatsUrl/$threadId/messages', {'body': body});

  // Note #37 — uploads a photo (e.g. a check-in/out live photo) and returns
  // the stored relative path (same "upload, then save the path" convention
  // used everywhere else — e.g. profile pictures). Reuses the exact same
  // handler the admin dashboard's uploader hits, just without the admin
  // gate on this route.
  Future<String> uploadPhoto(File file) async {
    final request = http.MultipartRequest('POST', Uri.parse(uploadsUrl));
    request.headers.addAll(withApiAuthHeaders());
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeJson(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map<String, dynamic> ||
        decoded['success'] != true) {
      throw Exception(
        decoded is Map
            ? decoded['error']?.toString() ?? 'Upload failed'
            : 'Upload failed',
      );
    }
    return decoded['path'].toString();
  }

  // Note #37 — volunteer self check-in: records arrival with GPS + a live
  // photo. Only valid while the signup is 'approved'.
  Future<Map<String, dynamic>> checkInMissionSignup({
    required int signupId,
    required double lat,
    required double lng,
    required String photoPath,
  }) => postJson('$volunteerMissionSignupsUrl/$signupId/check-in', {
    'lat': lat,
    'lng': lng,
    'photo_path': photoPath,
  });

  // Note #37 — volunteer self check-out: records departure/self-reported
  // completion with GPS + a live photo + notes. Only valid while the signup
  // is 'joined'. Staff still confirms via the dashboard before it becomes
  // 'completed'.
  Future<Map<String, dynamic>> checkOutMissionSignup({
    required int signupId,
    required double lat,
    required double lng,
    required String photoPath,
    String notes = '',
  }) => postJson('$volunteerMissionSignupsUrl/$signupId/check-out', {
    'lat': lat,
    'lng': lng,
    'photo_path': photoPath,
    'notes': notes,
  });

  // #50 — the current user's digital aid-delivery receipts.
  Future<List<Map<String, dynamic>>> myAidReceipts() =>
      getItems(aidReceiptsUrl);

  // #45 — open (or reuse) a direct chat with support/tech; returns thread_id.
  Future<int?> startSupportChat() async {
    final res = await postJson(chatSupportUrl, {});
    final id = res['thread_id'];
    return id is int ? id : int.tryParse('$id');
  }

  // #36 — support WhatsApp number (null when disabled/unset).
  Future<String?> supportWhatsapp() async {
    try {
      final res = await getObject(supportWhatsappUrl);
      final number = (res['number'] ?? '').toString().trim();
      return (res['enabled'] == true && number.isNotEmpty) ? number : null;
    } catch (_) {
      // DELIBERATE: null already means "no WhatsApp contact configured", a
      // legitimate absence, and both callers simply hide the WhatsApp button.
      // A failed fetch collapses into that same absence — the user loses one
      // of several support channels and is told nothing untrue. (The support
      // screen additionally logs its own failures around this call.)
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> volunteerMissions() =>
      getItems(volunteerMissionsUrl);

  Future<Map<String, dynamic>> volunteerDashboard(int userId) {
    final uri = Uri.parse(
      volunteerMissionsUrl,
    ).replace(queryParameters: {'user_id': '$userId'});
    return getObject(uri.toString());
  }

  Future<Map<String, dynamic>> joinVolunteerMission({
    required int userId,
    required int missionId,
  }) {
    return postJson(volunteerMissionsUrl, {
      'action': 'join_mission',
      'user_id': userId,
      'mission_id': missionId,
    });
  }

  Future<List<Map<String, dynamic>>> partners({int? userId}) {
    // #27 — pass user_id so the list flags the viewer's own rating.
    if (userId != null && userId > 0) {
      final uri = Uri.parse(
        partnersUrl,
      ).replace(queryParameters: {'user_id': '$userId'});
      return getItems(uri.toString());
    }
    return getItems(partnersUrl);
  }

  /// #27 — submit a 1–5 star rating for a partner. Returns
  /// {avg_rating, rating_count, my_rating}.
  Future<Map<String, dynamic>> ratePartner(int partnerId, int stars) =>
      postJsonNoTrack(partnerRateUrl(partnerId), {'stars': stars});

  Future<List<Map<String, dynamic>>> mediaPosts({int? userId}) {
    // #24 — pass user_id when logged in so the feed flags liked posts.
    if (userId != null && userId > 0) {
      final uri = Uri.parse(
        mediaPostsUrl,
      ).replace(queryParameters: {'user_id': '$userId'});
      return getItems(uri.toString());
    }
    return getItems(mediaPostsUrl);
  }

  /// #24 — toggle like on a post. Returns {liked, like_count}.
  Future<Map<String, dynamic>> likeMediaPost(int postId) =>
      postJsonNoTrack(mediaLikeUrl(postId), const {});

  /// Toggle "save for later" on a post. Returns {saved}.
  Future<Map<String, dynamic>> saveMediaPost(int postId) =>
      postJsonNoTrack(mediaSaveUrl(postId), const {});

  /// The signed-in user's saved posts, newest saved first.
  Future<List<Map<String, dynamic>>> savedMediaPosts(int userId) {
    final uri = Uri.parse(
      mediaPostsUrl,
    ).replace(queryParameters: {'user_id': '$userId', 'saved': '1'});
    return getItems(uri.toString());
  }

  /// #24 — approved comments for a post.
  Future<List<Map<String, dynamic>>> mediaComments(int postId) =>
      getItems(mediaCommentsUrl(postId));

  /// #24 — submit a comment. Returns {comment, held} (held = awaiting review).
  Future<Map<String, dynamic>> postMediaComment(int postId, String body) =>
      postJsonNoTrack(mediaCommentsUrl(postId), {'body': body});

  /// #24 — record a share. Returns {share_count}.
  Future<Map<String, dynamic>> shareMediaPost(int postId) =>
      postJsonNoTrack(mediaShareUrl(postId), const {});

  /// #22 — admin-managed "Our Work" categories for the News & Activities
  /// filter chips. Returns [] on error (the feed still works unfiltered).
  Future<List<Map<String, dynamic>>> mediaCategories() =>
      getItems(mediaCategoriesUrl);

  Future<List<Map<String, dynamic>>> beneficiaryCases() =>
      getItems(beneficiaryCasesUrl);

  Future<Map<String, dynamic>> dashboardSummary({required int userId}) {
    final uri = Uri.parse(
      dashboardSummaryUrl,
    ).replace(queryParameters: {'user_id': '$userId'});
    return getObject(uri.toString());
  }

  Future<Map<String, dynamic>> roleHistory({required int userId}) {
    final uri = Uri.parse(
      roleHistoryUrl,
    ).replace(queryParameters: {'user_id': '$userId'});
    return getObject(uri.toString());
  }

  Future<List<Map<String, dynamic>>> sponsorships({int? userId}) {
    if (userId == null || userId <= 0) {
      return getItems(sponsorshipsUrl);
    }
    final uri = Uri.parse(
      sponsorshipsUrl,
    ).replace(queryParameters: {'user_id': '$userId'});
    return getItems(uri.toString());
  }

  /// #21 — sponsorships that BENEFIT this user (their case is sponsored),
  /// for the beneficiary "My Entitlements" screen.
  Future<List<Map<String, dynamic>>> sponsorshipsAsBeneficiary(int userId) {
    final uri = Uri.parse(
      sponsorshipsUrl,
    ).replace(queryParameters: {'as': 'beneficiary', 'user_id': '$userId'});
    return getItems(uri.toString());
  }

  Future<Map<String, dynamic>> cancelSponsorship({
    required int sponsorshipId,
    required int userId,
  }) {
    return postJson(sponsorshipsUrl, {
      'action': 'cancel',
      'id': sponsorshipId,
      'user_id': userId,
    });
  }

  Future<List<Map<String, dynamic>>> marriageProfiles() =>
      getItems(marriageProfilesUrl);

  Future<Map<String, dynamic>> reports() => getObject(reportsUrl);
}

/// One toggleable entry in the Privacy Settings screen, served by
/// GET /api/profile/privacy-options.
class PrivacyFieldOption {
  const PrivacyFieldOption({
    required this.fieldKey,
    required this.labelKey,
    this.defaultHidden = false,
  });

  final String fieldKey;
  final String labelKey;
  final bool defaultHidden;
}

/// Donate-screen switches from GET /api/donation-options (Donations Page
/// spec). Both default to true so a fetch failure keeps the screen fully
/// functional.
class DonationOptions {
  const DonationOptions({
    this.projectsVisible = true,
    this.comprehensiveEnabled = true,
  });

  final bool projectsVisible;
  final bool comprehensiveEnabled;
}

/// One scheduled due date on a sponsorship ("Eighth: Sponsorship Schedule and
/// Calendar"). status is one of: upcoming, due, overdue, paid, skipped.
class ScheduleOccurrence {
  const ScheduleOccurrence({
    required this.id,
    required this.dueDate,
    required this.amount,
    required this.currency,
    required this.status,
    required this.sponsorshipType,
    this.notes = '',
  });

  final int id;
  final String dueDate; // YYYY-MM-DD
  final double amount;
  final String currency;
  final String status;
  final String sponsorshipType;
  final String notes;

  factory ScheduleOccurrence.fromJson(Map<String, dynamic> j) {
    final rawAmount = j['amount'];
    return ScheduleOccurrence(
      id: (j['id'] is int) ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      dueDate: (j['due_date'] ?? '').toString(),
      amount: rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse('$rawAmount') ?? 0,
      currency: (j['currency'] ?? 'IQD').toString(),
      status: (j['status'] ?? '').toString(),
      sponsorshipType: (j['sponsorship_type'] ?? '').toString(),
      notes: (j['notes'] ?? '').toString(),
    );
  }
}
