import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Client note — "Payment Methods and Payment Gateways" (piece 2 of the
/// Settings/Profile drawer note).
///
/// There's no "saved card" concept in this app — payment methods are
/// admin-configured (Cash/FIB/bank instructions the donate screen already
/// shows) and the only account-level payment method a user actually has is
/// the internal wallet. So this screen shows: the wallet balance + its
/// transaction ledger (the wallet API already supported this — no UI existed
/// for it anywhere yet), then the available ways to pay, read-only.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  bool _loading = true;
  WalletBalance _wallet = const WalletBalance(balanceIQD: 0, currency: 'IQD');
  List<WalletTransaction> _transactions = const [];
  List<PaymentMethod> _methods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      fetchWalletBalance(),
      fetchWalletTransactions(),
      fetchPaymentMethods(),
    ]);
    if (!mounted) return;
    setState(() {
      _wallet = results[0] as WalletBalance;
      _transactions = results[1] as List<WalletTransaction>;
      _methods = results[2] as List<PaymentMethod>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Payment Methods',
      subtitle: 'Your wallet balance and the ways you can pay.',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _WalletBalanceCard(wallet: _wallet),
                  const SizedBox(height: 22),
                  SectionLabel(title: 'Wallet activity'.tr),
                  const SizedBox(height: 10),
                  if (_transactions.isEmpty)
                    _EmptyNote(text: 'No wallet activity yet.'.tr)
                  else
                    for (var i = 0; i < _transactions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _TransactionRow(
                        tx: _transactions[i],
                        currency: _wallet.currency,
                      ),
                    ],
                  const SizedBox(height: 22),
                  SectionLabel(title: 'Ways to pay'.tr),
                  const SizedBox(height: 10),
                  if (_methods.isEmpty)
                    _EmptyNote(text: 'No payment methods configured yet.'.tr)
                  else
                    for (var i = 0; i < _methods.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _PaymentMethodInfoCard(method: _methods[i]),
                    ],
                ],
              ),
            ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({required this.wallet});

  final WalletBalance wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'My wallet'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _formatMoney(wallet.balanceIQD.toDouble(), wallet.currency),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx, required this.currency});

  final WalletTransaction tx;
  final String currency;

  ({IconData icon, Color color, bool isCredit}) _visual() {
    switch (tx.type) {
      case 'topup':
        return (icon: Icons.add_circle_rounded, color: Colors.green, isCredit: true);
      case 'refund':
        return (icon: Icons.undo_rounded, color: Colors.blue, isCredit: true);
      case 'donation':
        return (icon: Icons.favorite_rounded, color: Colors.pinkAccent, isCredit: false);
      case 'purchase':
        return (icon: Icons.shopping_bag_rounded, color: Colors.deepOrange, isCredit: false);
      default:
        return (icon: Icons.receipt_long_rounded, color: Colors.blueGrey, isCredit: false);
    }
  }

  String _typeLabel() {
    switch (tx.type) {
      case 'topup':
        return 'Wallet top-up'.tr;
      case 'refund':
        return 'Refund'.tr;
      case 'donation':
        return 'Donation'.tr;
      case 'purchase':
        return 'Marketplace purchase'.tr;
      default:
        return tx.type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual();
    final locale = Get.locale?.toLanguageTag() ?? 'en';
    final date = DateFormat.yMMMd(locale).add_jm().format(tx.createdAt.toLocal());
    final sign = v.isCredit ? '+' : '-';

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          TileIcon(icon: v.icon, color: v.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                if ((tx.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.note!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$sign${_formatMoney(tx.amountIQD.toDouble(), currency)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: v.isCredit ? Colors.green : AppThemeConfig.text(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodInfoCard extends StatelessWidget {
  const _PaymentMethodInfoCard({required this.method});

  final PaymentMethod method;

  IconData _icon() {
    switch (method.methodType) {
      case 'bank':
        return Icons.account_balance_rounded;
      case 'wallet':
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileIcon(icon: _icon(), color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method.localizedName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                if (method.localizedInstructions.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    method.localizedInstructions,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
                if (method.accountNumber.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      method.accountNumber,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: AppThemeConfig.mutedText(context)),
      ),
    );
  }
}

String _formatMoney(double amount, String currency) {
  final locale = Get.locale?.toLanguageTag() ?? 'en';
  final formatter = NumberFormat.decimalPattern(locale);
  return '${formatter.format(amount)} $currency';
}
