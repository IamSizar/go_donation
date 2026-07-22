import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'links.dart';

/// Note #42 — test-phase internal app wallet (IQD). Read-only from the app's
/// side for now: crediting only happens via an admin action on the
/// dashboard (see `backend/internal/handlers/wallet.go`'s AdminTopUp).

class WalletBalance {
  const WalletBalance({required this.balanceIQD, required this.currency});
  final int balanceIQD;
  final String currency;
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.amountIQD,
    required this.type,
    required this.createdAt,
    this.note,
  });

  final int id;
  final int amountIQD;
  final String type; // topup | donation | purchase | refund
  final DateTime createdAt;
  final String? note;

  factory WalletTransaction.fromMap(Map<String, dynamic> m) {
    return WalletTransaction(
      id: int.tryParse('${m['id']}') ?? 0,
      amountIQD: int.tryParse('${m['amount_iqd']}') ?? 0,
      type: (m['type'] ?? '').toString(),
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      note: m['note']?.toString(),
    );
  }
}

/// Fetches the current user's wallet balance. Returns a zero balance on any
/// failure (offline, unauthenticated) so a wallet card never crashes the
/// Home screen — it just shows 0 until the next successful refresh.
Future<WalletBalance> fetchWalletBalance() async {
  try {
    final resp = await http
        .get(Uri.parse(walletUrl), headers: withApiAuthHeaders())
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      return const WalletBalance(balanceIQD: 0, currency: 'IQD');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      return const WalletBalance(balanceIQD: 0, currency: 'IQD');
    }
    return WalletBalance(
      balanceIQD: int.tryParse('${decoded['balance_iqd']}') ?? 0,
      currency: (decoded['currency'] ?? 'IQD').toString(),
    );
  } catch (_) {
    return const WalletBalance(balanceIQD: 0, currency: 'IQD');
  }
}

/// Fetches the current user's own wallet ledger, newest first.
Future<List<WalletTransaction>> fetchWalletTransactions() async {
  try {
    final resp = await http
        .get(Uri.parse(walletTransactionsUrl), headers: withApiAuthHeaders())
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return [];
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map || decoded['transactions'] is! List) return [];
    return (decoded['transactions'] as List)
        .whereType<Map>()
        .map((m) => WalletTransaction.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  } catch (_) {
    return [];
  }
}
