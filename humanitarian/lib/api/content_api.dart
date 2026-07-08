// Public editable content pages (Terms & Conditions now). No auth required —
// the app renders these before/without login. GET /api/content/:slug returns
// {content: {title_en/ar/ckb/kmr, body_en/ar/ckb/kmr}}.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:http/http.dart' as http;

const String contentTermsUrl = '${baseUrl}content/terms';

/// Fetches an app_content page by slug (terms / about / contact …), or null on
/// error/offline. Returns the {title_*/body_*} map.
Future<Map<String, dynamic>?> fetchContent(String slug) async {
  try {
    final resp = await http.get(
      Uri.parse('${baseUrl}content/$slug'),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['content'] is Map) {
      return Map<String, dynamic>.from(decoded['content'] as Map);
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Fetches the Terms & Conditions content map, or null on error/offline.
Future<Map<String, dynamic>?> fetchTermsContent() => fetchContent('terms');
