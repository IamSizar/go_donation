// Admin-managed donation payment methods (#19). Public GET /api/payment-methods
// (no auth) returns the active, ordered list with account details; the donate
// screen renders them instead of the hardcoded Cash/FIB pair.
import 'dart:convert';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:http/http.dart' as http;

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.slug,
    required this.methodType,
    required this.nameEn,
    required this.nameAr,
    required this.nameCkb,
    required this.nameKmr,
    required this.instructionsEn,
    required this.instructionsAr,
    required this.instructionsCkb,
    required this.instructionsKmr,
    required this.accountNumber,
    required this.accountName,
  });

  final int id;
  final String slug;
  final String methodType; // cash | bank | wallet
  final String nameEn;
  final String nameAr;
  final String nameCkb;
  final String nameKmr;
  final String instructionsEn;
  final String instructionsAr;
  final String instructionsCkb;
  final String instructionsKmr;
  final String accountNumber;
  final String accountName;

  String _localized(String en, String ar, String ckb, String kmr) {
    final lang = AppLocaleService.assistantLang(); // en | ar | ckb | kmr
    final v = switch (lang) {
      'ar' => ar,
      'ckb' => ckb,
      'kmr' => kmr,
      _ => en,
    }
        .trim();
    return v.isNotEmpty ? v : en;
  }

  String get localizedName => _localized(nameEn, nameAr, nameCkb, nameKmr);
  String get localizedInstructions =>
      _localized(instructionsEn, instructionsAr, instructionsCkb, instructionsKmr);

  static String _s(dynamic v) => (v ?? '').toString();
  static int _int(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(
        id: _int(j['id']),
        slug: _s(j['slug']),
        methodType: _s(j['method_type']),
        nameEn: _s(j['name_en']),
        nameAr: _s(j['name_ar']),
        nameCkb: _s(j['name_ckb']),
        nameKmr: _s(j['name_kmr']),
        instructionsEn: _s(j['instructions_en']),
        instructionsAr: _s(j['instructions_ar']),
        instructionsCkb: _s(j['instructions_ckb']),
        instructionsKmr: _s(j['instructions_kmr']),
        accountNumber: _s(j['account_number']),
        accountName: _s(j['account_name']),
      );
}

/// Fetches the active payment methods (ordered), or an empty list on
/// error/offline (the donate screen then uses its built-in fallback).
Future<List<PaymentMethod>> fetchPaymentMethods() async {
  try {
    final resp = await http.get(
      Uri.parse(paymentMethodsUrl),
      headers: const {'Accept': 'application/json'},
    );
    if (resp.statusCode != 200) return const [];
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .whereType<Map>()
          .map((m) => PaymentMethod.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return const [];
  } catch (_) {
    return const [];
  }
}
