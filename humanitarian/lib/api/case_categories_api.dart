// Admin-managed beneficiary-case categories (Quick Filter Capsules).
// Public GET /api/case-categories (no auth) returns the active, ordered
// list; the Home screen shows them as capsule chips that jump into the
// case list pre-filtered.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:http/http.dart' as http;

class CaseCategory {
  const CaseCategory({
    required this.id,
    required this.slug,
    required this.nameEn,
    required this.nameAr,
    required this.nameCkb,
    required this.nameKmr,
  });

  final int id;
  final String slug;
  final String nameEn;
  final String nameAr;
  final String nameCkb;
  final String nameKmr;

  /// The category name in the current app language, falling back to English.
  String get localizedName {
    final lang = AppLocaleService.assistantLang(); // en | ar | ckb | kmr
    final v = switch (lang) {
      'ar' => nameAr,
      'ckb' => nameCkb,
      'kmr' => nameKmr,
      _ => nameEn,
    }.trim();
    return v.isNotEmpty ? v : nameEn;
  }

  static int _int(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  factory CaseCategory.fromJson(Map<String, dynamic> j) => CaseCategory(
    id: _int(j['id']),
    slug: (j['slug'] ?? '').toString(),
    nameEn: (j['name_en'] ?? '').toString(),
    nameAr: (j['name_ar'] ?? '').toString(),
    nameCkb: (j['name_ckb'] ?? '').toString(),
    nameKmr: (j['name_kmr'] ?? '').toString(),
  );
}

/// Fetches the active case categories, in admin order.
///
/// THROWS on failure. It used to end in `catch (_) { return const []; }`, with
/// a comment arguing the silence was safe: these are a browse FILTER taxonomy
/// rather than the user's own data, so an absent row "states nothing untrue"
/// — unlike an empty list of *their* cases, which would claim they have none.
///
/// That argument was correct about the row and wrong about the screen. Home
/// prints the heading "Browse by category" above these capsules, and a heading
/// with nothing under it asserts two contradictory things at once: that there
/// are categories, and that there are none. Once the failure is visible here,
/// [CaseCategoryCapsules] can tell the two apart and show a retry (C2).
///
/// A successful response carrying no items is still an empty list, not an
/// error — over-throwing would replace a legitimately empty taxonomy with a
/// permanent error banner.
Future<List<CaseCategory>> fetchCaseCategories() async {
  final resp = await http.get(
    Uri.parse(caseCategoriesUrl),
    headers: const {'Accept': 'application/json'},
  );
  if (resp.statusCode != 200) {
    throw Exception('Case categories request failed (${resp.statusCode})');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is Map && decoded['items'] is List) {
    return (decoded['items'] as List)
        .whereType<Map>()
        .map((m) => CaseCategory.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
  return const [];
}
