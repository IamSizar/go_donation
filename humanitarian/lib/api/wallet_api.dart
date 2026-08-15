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

/// Fetches the current user's wallet balance.
///
/// THROWS on any failure — offline, timeout, non-200, unparseable body.
///
/// This used to return `WalletBalance(balanceIQD: 0)` on every failure, with
/// the stated intent of keeping the Home screen's wallet card from crashing.
/// The intent was right; the mechanism was not. A zero balance is not a
/// missing value, it is a WRONG one: the user is shown a confident, specific
/// number telling them their wallet is empty, and cannot tell that apart from
/// actually having no money. On a screen about money that is the worst
/// available failure mode, and it also made the payment screen's error state
/// unreachable, since the screen never learned anything had gone wrong.
///
/// Callers must now handle the throw. A caller that genuinely cannot show an
/// error — the Home dashboard card — should render an explicit "unavailable"
/// placeholder rather than a number it does not have.
Future<WalletBalance> fetchWalletBalance() async {
  final resp = await http
      .get(Uri.parse(walletUrl), headers: withApiAuthHeaders())
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) {
    throw Exception('Wallet balance request failed (${resp.statusCode})');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map) {
    throw Exception('Wallet balance response was not an object');
  }
  return WalletBalance(
    balanceIQD: int.tryParse('${decoded['balance_iqd']}') ?? 0,
    currency: (decoded['currency'] ?? 'IQD').toString(),
  );
}

/// Fetches the current user's own wallet ledger, newest first.
///
/// THROWS on failure. Previously returned `[]`, which the UI could not tell
/// apart from a genuinely empty ledger, so a failed load rendered "No wallet
/// activity yet."
///
/// A missing `transactions` key on an otherwise valid 200 is still treated as
/// an empty ledger rather than an error — that is the server saying "no rows",
/// not a failure to answer.
Future<List<WalletTransaction>> fetchWalletTransactions() async {
  final resp = await http
      .get(Uri.parse(walletTransactionsUrl), headers: withApiAuthHeaders())
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) {
    throw Exception('Wallet ledger request failed (${resp.statusCode})');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map) {
    throw Exception('Wallet ledger response was not an object');
  }
  if (decoded['transactions'] is! List) return [];
  return (decoded['transactions'] as List)
      .whereType<Map>()
      .map((m) => WalletTransaction.fromMap(Map<String, dynamic>.from(m)))
      .toList();
}
