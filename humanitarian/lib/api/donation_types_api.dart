// Admin-managed donor-facing donation TYPES (M7 server-side, M3 app-side).
//
// WHY THIS FILE EXISTS
// The giving type a donor files a gift under — General / Zakat / Sadaqah, plus
// whatever staff add later — stopped being a switch in the Go binary when
// migration 103 turned it into rows behind `GET /api/donation-types`. The app
// kept its own copy of that list hardcoded in a widget
// (`_DonationTypeSelector` in continue_donation_screen.dart), so a type added
// from the dashboard was accepted by the server and invisible to the donor:
// exactly the defect the migration was written to remove, one layer up.
//
// Mirrors case_categories_api.dart — same {slug, name_en, name_ar, name_ckb,
// name_kmr} shape, same localizedName resolution, same failure contract.
//
// NOT the same thing as a payment method or a donation KIND. See
// lib/modules/donations/models/donation_channel.dart for that distinction.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:http/http.dart' as http;

/// One donation type as the dashboard defines it.
class DonationType {
  const DonationType({
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

  /// The type's name in the current app language, falling back to English.
  ///
  /// The fallback matters: `name_ckb` / `name_kmr` default to `''` in the
  /// table, so a type staff added without Kurdish must degrade to English
  /// rather than render an empty chip.
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

  factory DonationType.fromJson(Map<String, dynamic> j) => DonationType(
    id: _int(j['id']),
    slug: (j['slug'] ?? '').toString(),
    nameEn: (j['name_en'] ?? '').toString(),
    nameAr: (j['name_ar'] ?? '').toString(),
    nameCkb: (j['name_ckb'] ?? '').toString(),
    nameKmr: (j['name_kmr'] ?? '').toString(),
  );
}

/// Fetches the ACTIVE donation types, in the order staff arranged them.
///
/// THROWS on failure, matching the contract pinned by
/// test/api/failure_signalling_test.dart: a 500 or an offline device must not
/// arrive at the UI as a successful empty result, or the donate screen would
/// silently claim the organization offers no giving types at all.
///
/// A 200 carrying no `items` list is a genuinely empty catalogue, not an
/// error — over-throwing would replace a legitimate empty state with a
/// permanent error banner.
Future<List<DonationType>> fetchDonationTypes() async {
  final resp = await http.get(
    Uri.parse(donationTypesUrl),
    headers: const {'Accept': 'application/json'},
  );
  if (resp.statusCode != 200) {
    throw Exception('Donation types request failed (${resp.statusCode})');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is Map && decoded['items'] is List) {
    return (decoded['items'] as List)
        .whereType<Map>()
        .map((m) => DonationType.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
  return const [];
}
