// Public aggregate "impact" numbers for the home stats slider (#10). No auth —
// these are org-wide totals with no personal data. GET /api/stats/impact returns
// {success, stats:{grantors, eligibles, volunteers, completed_works, total_given}}.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:http/http.dart' as http;

const String impactStatsUrl = '${baseUrl}stats/impact';

/// The five headline impact numbers. Counts are ints; [totalGiven] is kept as a
/// num parsed from the backend's string (amount is stored as TEXT there).
class ImpactStats {
  const ImpactStats({
    required this.grantors,
    required this.eligibles,
    required this.volunteers,
    required this.completedWorks,
    required this.totalGiven,
  });

  final int grantors;
  final int eligibles;
  final int volunteers;
  final int completedWorks;
  final num totalGiven;

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static num _num(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ImpactStats.fromJson(Map<String, dynamic> json) => ImpactStats(
        grantors: _int(json['grantors']),
        eligibles: _int(json['eligibles']),
        volunteers: _int(json['volunteers']),
        completedWorks: _int(json['completed_works']),
        totalGiven: _num(json['total_given']),
      );

  /// True when every number is zero — nothing meaningful to show yet.
  bool get isEmpty =>
      grantors == 0 &&
      eligibles == 0 &&
      volunteers == 0 &&
      completedWorks == 0 &&
      totalGiven == 0;
}

/// Fetches the public impact stats, or null on error/offline (the slider then
/// hides itself gracefully).
Future<ImpactStats?> fetchImpactStats() async {
  try {
    final resp = await http.get(
      Uri.parse(impactStatsUrl),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['stats'] is Map) {
      return ImpactStats.fromJson(
        Map<String, dynamic>.from(decoded['stats'] as Map),
      );
    }
    return null;
  } catch (_) {
    return null;
  }
}
