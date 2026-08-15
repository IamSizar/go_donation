// Admin-managed project categories (#17). Public GET /api/project-categories
// (no auth) returns the active, ordered list; the beneficiary submit-project
// screen shows them in a dropdown instead of a free-text field.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:http/http.dart' as http;

class ProjectCategory {
  const ProjectCategory({
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

  factory ProjectCategory.fromJson(Map<String, dynamic> j) => ProjectCategory(
    id: _int(j['id']),
    slug: (j['slug'] ?? '').toString(),
    nameEn: (j['name_en'] ?? '').toString(),
    nameAr: (j['name_ar'] ?? '').toString(),
    nameCkb: (j['name_ckb'] ?? '').toString(),
    nameKmr: (j['name_kmr'] ?? '').toString(),
  );
}

/// Fetches the active project categories, in admin order.
///
/// THROWS on failure. It used to end in `catch (_) { return const []; }`, and
/// the comment defending that silence made a real argument: these are an input
/// VOCABULARY rather than the user's own data, and both call sites degraded to
/// something usable — a free-text category field on the submit-project form,
/// or a hidden picker on checkout with the gift going to the general fund.
///
/// That argument held exactly as long as the picker was an optional
/// refinement. M4 turned it into one of two named paths a donor chooses
/// between, so a failed load now means tapping "donate to a specific project"
/// and being shown nothing — the C2 mistake in a new place. Once the failure
/// is visible here, [AidTargetField] can tell "there are no projects open"
/// apart from "we could not ask", and offer a retry for the second.
///
/// The submit-project form still wants the old behaviour and still gets it:
/// it catches this and keeps its free-text fallback, which is now a written-
/// down decision at the call site instead of one inherited by accident.
///
/// A 200 carrying no `items` list is a genuinely empty catalogue, not an
/// error.
Future<List<ProjectCategory>> fetchProjectCategories() async {
  final resp = await http.get(
    Uri.parse(projectCategoriesUrl),
    headers: const {'Accept': 'application/json'},
  );
  if (resp.statusCode != 200) {
    throw Exception('Project categories request failed (${resp.statusCode})');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is Map && decoded['items'] is List) {
    return (decoded['items'] as List)
        .whereType<Map>()
        .map((m) => ProjectCategory.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
  return const [];
}
