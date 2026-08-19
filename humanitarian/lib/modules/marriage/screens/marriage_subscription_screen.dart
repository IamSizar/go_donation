import 'package:flutter/material.dart';

import 'package:flutter_application_1/localization/money.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
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
  // True only for the FIRST load. `_load()` also runs on pull-to-refresh and
  // after a successful purchase; those must update the list in place rather
  // than flash a skeleton over packages the user is already reading.
  bool _loading = true;

  /// A user-facing failure message, or null when the last load succeeded.
  /// Cleared on every retry so a recovered fetch stops showing the banner.
  String? _error;
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
    // The three calls had NO error handling at all: any one of them throwing
    // left `_loading` true forever behind a spinner that never resolved, and
    // once the four-state pass landed it would have fallen through to the
    // "No subscription packages are available yet." copy — telling the user
    // there is nothing to buy when in fact the request simply failed, with no
    // way to retry.
    try {
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
        // A successful load is the retry succeeding — drop the banner.
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load subscription packages.';
        _loading = false;
      });
      debugPrint('marriage subscription load failed: $e');
    }
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
    return (pkg[field == 'name' ? 'name_en' : 'description_en'] ?? '')
        .toString();
  }

  Future<void> _choosePayment(Map<String, dynamic> pkg) async {
    // The error state keeps the previously-loaded packages on screen, dimmed
    // but still tappable (AppErrorState only wraps stale content in Opacity).
    // `_walletBalanceIQD` comes from the same failed load, so opening the
    // payment sheet here would offer — or refuse — the wallet on a balance we
    // know we could not refresh. Money decisions do not get made on data we
    // have already admitted is stale, so the purchase is gated until a retry
    // succeeds.
    if (_error != null) {
      Get.snackbar(
        'Subscription'.tr,
        'Your balance could not be refreshed. Retry the load before subscribing.',
      );
      return;
    }
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
              color: AppThemeConfig.elevatedSurface(sheetContext),
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
                  subtitle: '${'Balance'.tr}: $_walletBalanceIQD ${localizedCurrency('IQD')}',
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
      final res = await const ModuleApi().purchaseMarriageSubscription(
        packageId,
        paymentMethod,
      );
      if (!mounted) return;
      final paid = res['status'] == 'paid';
      await showAdaptiveMessage(
        context,
        title: paid ? 'Subscription activated'.tr : 'Subscription pending'.tr,
        message: paid
            ? 'Your subscription is now active.'.tr
            : 'Your payment is pending staff confirmation.'.tr,
        buttonLabel: 'OK'.tr,
        icon: Icon(
          paid ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
          size: 48,
          color: paid ? Colors.green : Colors.orange,
        ),
      );
      if (paid) await _load();
    } catch (e) {
      debugPrint('marriage subscription purchase failed: $e');
      if (mounted) {
        Get.snackbar(
          'Error'.tr,
          failureMessage(e, 'error_subscription_failed'),
        );
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
      child: AppAsync<List<Map<String, dynamic>>>(
        // The gutter lives inside this screen's own list, so the skeleton
        // and the error banner would otherwise sit edge-to-edge while the
        // content that replaces them sits in a 20pt margin.
        gutter: const EdgeInsets.symmetric(horizontal: 20),
        loading: _loading,
        error: _error,
        onRetry: _load,
        data: _packages,
        isEmpty: (packages) => packages.isEmpty,
        // AppAsync would otherwise fall back to AppSkeleton.rows, which draws
        // bare text rows — the real content here is a column of panelled
        // cards, so the rows would jump into cards rather than fill into
        // them. Reached only on the first load: `_loading` stays false for
        // pull-to-refresh and for the reload after a purchase.
        skeleton: const _PackageSkeleton(),
        empty: AppEmpty(
          icon: Icons.workspace_premium_rounded,
          title: 'Subscription'.tr,
          message: 'No subscription packages are available yet.'.tr,
        ),
        builder: (packages) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              for (var i = 0; i < packages.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _PackageCard(
                  package: packages[i],
                  name: _localized(packages[i], 'name'),
                  description: _localized(packages[i], 'description'),
                  busy: _busyPackageIds.contains(
                    (packages[i]['id'] as num).toInt(),
                  ),
                  onTap: () => _choosePayment(packages[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// First-load placeholder for the package list, shaped like [_PackageCard].
///
/// It reuses the real [GlassPanel] frame and the same 12px gap between cards,
/// so the panels are already drawn in their final position and only their
/// contents fill in — rather than a spinner vanishing and three cards
/// appearing at once.
class _PackageSkeleton extends StatelessWidget {
  const _PackageSkeleton();

  @override
  Widget build(BuildContext context) {
    final bone = AppThemeConfig.border(context);

    /// One bar of the card interior. Rounded to the bar's own height so the
    /// short ones read as pills rather than as cropped blocks.
    Widget bar(double height, {double? width, double radius = 0}) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: bone,
        borderRadius: BorderRadius.circular(radius > 0 ? radius : height / 2),
      ),
    );

    return AppSkeleton(
      child: ListView(
        // Same padding as the real list, so the first card lands where its
        // placeholder sat.
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Three cards: enough to fill a phone screen without implying a
          // specific catalogue size.
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon tile, package name, price — the card's header row.
                  Row(
                    children: [
                      bar(44, width: 44, radius: 14),
                      const SizedBox(width: 12),
                      Expanded(child: bar(15)),
                      const SizedBox(width: 12),
                      bar(13, width: 76),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Two lines of description, the second one short.
                  bar(11),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.55,
                    child: bar(11),
                  ),
                  const SizedBox(height: 14),
                  // The full-width Subscribe button.
                  bar(44, radius: 20),
                ],
              ),
            ),
          ],
        ],
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
              TileIcon(
                icon: Icons.workspace_premium_rounded,
                color: Colors.pinkAccent,
              ),
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
                '$formattedPrice ${localizedCurrency('IQD')}',
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
