// Admin-managed in-kind donation categories (Donations Page spec, "4. In-Kind
// Donations"). Public GET /api/inkind-categories. Mirrors
// project_categories_api.dart — adding a category is a Dashboard action, not
// an app change.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:http/http.dart' as http;

class InkindCategory {
  const InkindCategory({
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

  factory InkindCategory.fromJson(Map<String, dynamic> j) => InkindCategory(
    id: _int(j['id']),
    slug: (j['slug'] ?? '').toString(),
    nameEn: (j['name_en'] ?? '').toString(),
    nameAr: (j['name_ar'] ?? '').toString(),
    nameCkb: (j['name_ckb'] ?? '').toString(),
    nameKmr: (j['name_kmr'] ?? '').toString(),
  );
}

/// Fetches the active project categories (ordered), or an empty list on
/// error/offline (the submit screen then falls back to a free-text field).
Future<List<InkindCategory>> fetchInkindCategories() async {
  try {
    final resp = await http.get(
      Uri.parse(inkindCategoriesUrl),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return const [];
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .whereType<Map>()
          .map((m) => InkindCategory.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return const [];
  } catch (_) {
    // DELIBERATE silence, same reasoning as fetchProjectCategories: an input
    // vocabulary rather than the user's data. The submit screen falls back to
    // a free-text field, so the form stays usable and claims nothing false.
    return const [];
  }
}
