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

/// Fetches the active case categories (ordered), or an empty list on
/// error/offline (the capsule row then simply doesn't show).
Future<List<CaseCategory>> fetchCaseCategories() async {
  try {
    final resp = await http.get(
      Uri.parse(caseCategoriesUrl),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return const [];
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .whereType<Map>()
          .map((m) => CaseCategory.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return const [];
  } catch (_) {
    // DELIBERATE silence: these are a browse FILTER taxonomy, not the user's
    // data. CaseCategoryCapsules renders nothing when the list is empty, so a
    // failed load costs the user a filter row and states nothing untrue —
    // unlike an empty list of *their* cases, which would claim they have none.
    return const [];
  }
}
