// Public editable content pages (Terms & Conditions, About Us, Contact Us …).
// No auth required — the app renders these before/without login.
//
// GET /api/content/:slug returns
//   {
//     content:  {title_en/ar/ckb/kmr, body_en/ar/ckb/kmr,
//                logo_path, contact_phone, contact_whatsapp, contact_email,
//                social_links, address_en/ar/ckb/kmr},
//     sections: [{id, display_order, title_*, body_*}, …]
//   }
//
// `sections` (K12, migration 111) is the page's NAMED, ORDERED sub-sections.
// The server also recomposes them back into `content.body_*` in the same
// transaction, so both halves of the response describe the same words: a
// reader must render one or the other, never both.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:http/http.dart' as http;

const String contentTermsUrl = '${baseUrl}content/terms';

/// One editable content page: the page row itself, plus its sub-sections.
///
/// [sections] is empty for a page the owner has not split — which is the
/// ordinary case, and the case the screen must still render from [content]'s
/// `body_*`.
class ContentPage {
  const ContentPage({required this.content, required this.sections});

  /// The `app_content` row: `title_*`, `body_*` and the K13 contact columns.
  final Map<String, dynamic> content;

  /// The `app_content_sections` rows, already in `display_order`.
  final List<Map<String, dynamic>> sections;
}

/// Fetches an app_content page by slug (terms / about / contact …), or null on
/// error/offline.
///
/// Null is the single failure signal, as it was before this returned sections:
/// there is no "successfully empty" CMS page, so every caller renders
/// AppErrorState with a retry. Throwing would only move the same decision into
/// a try/catch at each call site.
Future<ContentPage?> fetchContentPage(String slug) async {
  try {
    final resp = await http.get(
      Uri.parse('${baseUrl}content/$slug'),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map || decoded['content'] is! Map) return null;
    final rawSections = decoded['sections'];
    return ContentPage(
      content: Map<String, dynamic>.from(decoded['content'] as Map),
      // An older server (pre-111) sends no `sections` key at all, and the
      // handler sends `[]` for a page with none. Both mean the same thing to
      // the screen, so both become an empty list rather than a null to check.
      sections: rawSections is List
          ? rawSections
                .whereType<Map>()
                .map((s) => Map<String, dynamic>.from(s))
                .toList(growable: false)
          : const [],
    );
  } catch (_) {
    return null;
  }
}

/// Fetches the Terms & Conditions content map, or null on error/offline.
///
/// Terms is a single legal document rather than a set of named parts, so it
/// reads the page row only and ignores any sub-sections — `body_*` already
/// carries their composition.
Future<Map<String, dynamic>?> fetchTermsContent() async =>
    (await fetchContentPage('terms'))?.content;
