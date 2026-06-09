import 'dart:convert';

import 'package:flutter_application_1/api/auth_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/app_event_firestore.dart';
import 'package:http/http.dart' as http;

class ModuleApi {
  const ModuleApi();

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

  Future<List<Map<String, dynamic>>> getItems(String url) async {
    final uri = Uri.parse(url).replace(
      queryParameters: withApiAuthQueryParameters(
        Uri.parse(url).queryParameters,
      ),
    );
    final response = await http.get(uri, headers: withApiAuthHeaders());
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
    final uri = Uri.parse(url).replace(
      queryParameters: withApiAuthQueryParameters(
        Uri.parse(url).queryParameters,
      ),
    );
    final response = await http.get(uri, headers: withApiAuthHeaders());
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
    final response = await http.post(
      Uri.parse(url),
      headers: withApiAuthHeaders(const {'Content-Type': 'application/json'}),
      body: jsonEncode(enrichedBody),
    );
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

  Future<List<Map<String, dynamic>>> marketplaceProducts() =>
      getItems(marketplaceProductsUrl);

  Future<List<Map<String, dynamic>>> communityDirectory() =>
      getItems(communityDirectoryUrl);

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

  Future<List<Map<String, dynamic>>> partners() => getItems(partnersUrl);

  Future<List<Map<String, dynamic>>> mediaPosts() => getItems(mediaPostsUrl);

  /// Media posts filtered by post_type (e.g. "marriage" for the marriage
  /// service's posts tab). The backend keeps these out of the general feed.
  Future<List<Map<String, dynamic>>> mediaPostsByType(String type) =>
      getItems('$mediaPostsUrl?type=$type');

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
