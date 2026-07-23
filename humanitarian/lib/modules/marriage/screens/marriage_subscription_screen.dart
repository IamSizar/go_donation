import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Client note — Marriage "Subscription": a real, dynamic package list
/// (admin adds/edits/removes these — nothing is hardcoded here) with a real
/// purchase flow. Wallet payments activate instantly; cash/bank payments
/// stay pending until staff confirms them.
class MarriageSubscriptionScreen extends StatefulWidget {
  const MarriageSubscriptionScreen({super.key});

  @override
  State<MarriageSubscriptionScreen> createState() =>
      _MarriageSubscriptionScreenState();
}

class _MarriageSubscriptionScreenState
    extends State<MarriageSubscriptionScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _packages = [];
  int _walletBalanceIQD = 0;
  List<PaymentMethod> _paymentMethods = [];
  final _busyPackageIds = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      const ModuleApi().fetchMarriageSubscriptionPackages(),
      fetchWalletBalance(),
      fetchPaymentMethods(),
    ]);
    if (!mounted) return;
    setState(() {
      _packages = results[0] as List<Map<String, dynamic>>;
      _walletBalanceIQD = (results[1] as WalletBalance).balanceIQD;
      _paymentMethods = (results[2] as List<PaymentMethod>)
          .where((m) => m.methodType != 'wallet')
          .toList();
      _loading = false;
    });
  }

  String _localized(Map<String, dynamic> pkg, String field) {
    const byLang = {
      'en': 'name_en',
      'ar': 'name_ar',
      'ckb': 'name_ckb',
      'kmr': 'name_kmr',
    };
    final key = field == 'name'
        ? (byLang[AppLocaleService.assistantLang()] ?? 'name_en')
        : 'description_${AppLocaleService.assistantLang() == 'en' ? 'en' : AppLocaleService.assistantLang()}';
    final v = (pkg[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    return (pkg[field == 'name' ? 'name_en' : 'description_en'] ?? '').toString();
  }

  Future<void> _choosePayment(Map<String, dynamic> pkg) async {
    final id = (pkg['id'] as num).toInt();
    final priceIQD = (pkg['price_iqd'] as num?)?.toInt() ?? 0;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: AppThemeConfig.surface(sheetContext),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppThemeConfig.border(sheetContext)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment method'.tr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(sheetContext),
                  ),
                ),
                const SizedBox(height: 14),
                _PaymentOptionTile(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'App Wallet'.tr,
                  subtitle: '${'Balance'.tr}: $_walletBalanceIQD IQD',
                  enabled: _walletBalanceIQD >= priceIQD,
                  onTap: () => Navigator.of(sheetContext).pop('app_wallet'),
                ),
                for (final m in _paymentMethods)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _PaymentOptionTile(
                      icon: Icons.payments_rounded,
                      title: m.localizedName,
                      subtitle: m.localizedInstructions,
                      enabled: true,
                      onTap: () => Navigator.of(sheetContext).pop(m.slug),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    await _purchase(id, result);
  }

  Future<void> _purchase(int packageId, String paymentMethod) async {
    setState(() => _busyPackageIds.add(packageId));
    try {
      final res = await const ModuleApi()
          .purchaseMarriageSubscription(packageId, paymentMethod);
      if (!mounted) return;
      final paid = res['status'] == 'paid';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            paid ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
            size: 48,
            color: paid ? Colors.green : Colors.orange,
          ),
          title: Text(
            (paid ? 'Subscription activated'.tr : 'Subscription pending'.tr),
            textAlign: TextAlign.center,
          ),
          content: Text(
            paid
                ? 'Your subscription is now active.'.tr
                : 'Your payment is pending staff confirmation.'.tr,
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('OK'.tr),
            ),
          ],
        ),
      );
      if (paid) await _load();
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error'.tr, e.toString());
      }
    } finally {
      if (mounted) setState(() => _busyPackageIds.remove(packageId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Subscription',
      subtitle: 'Choose a subscription package.',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (_packages.isEmpty)
                    SectionTile(
                      icon: Icons.workspace_premium_rounded,
                      title: 'Subscription',
                      subtitle: 'No subscription packages are available yet.'.tr,
                      color: Colors.pinkAccent,
                    ),
                  for (var i = 0; i < _packages.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _PackageCard(
                      package: _packages[i],
                      name: _localized(_packages[i], 'name'),
                      description: _localized(_packages[i], 'description'),
                      busy: _busyPackageIds
                          .contains((_packages[i]['id'] as num).toInt()),
                      onTap: () => _choosePayment(_packages[i]),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.name,
    required this.description,
    required this.busy,
    required this.onTap,
  });

  final Map<String, dynamic> package;
  final String name;
  final String description;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priceIQD = (package['price_iqd'] as num?)?.toInt() ?? 0;
    final locale = Get.locale?.toLanguageTag() ?? 'en';
    final formattedPrice = NumberFormat.decimalPattern(locale).format(priceIQD);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TileIcon(icon: Icons.workspace_premium_rounded, color: Colors.pinkAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ),
              Text(
                '$formattedPrice IQD',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ],
          ),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onTap,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
              label: Text('Subscribe'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppThemeConfig.softSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppThemeConfig.border(context)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? AppThemeConfig.primary
                    : AppThemeConfig.mutedText(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? AppThemeConfig.text(context)
                            : AppThemeConfig.mutedText(context),
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    if (!enabled)
                      Text(
                        'Insufficient wallet balance'.tr,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
