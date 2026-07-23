import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// The cart, as its own screen. Previously a floating panel over the
/// product list — once payment method, totals, and actions all had to fit
/// in one small overlay bar it stayed cramped no matter how it was
/// arranged. The product list now shows only a slim tappable summary bar
/// (see `_CartTeaserBar` in marketplace_section.dart) that opens this
/// screen for everything else.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketplaceController>();

    return SectionScaffold(
      title: 'Your Cart',
      subtitle: 'Review your items, then choose how to pay.',
      child: Obx(() {
        final entries = controller.cartQuantities.entries
            .where((e) => e.value > 0)
            .toList();

        if (entries.isEmpty) {
          return const _EmptyCart();
        }

        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                itemCount: entries.length,
                separatorBuilder: (context, i) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final product = controller.productById(entries[i].key);
                  if (product == null) return const SizedBox.shrink();
                  return _CartLineItem(
                    product: product,
                    quantity: entries[i].value,
                    controller: controller,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: _CartCheckoutPanel(controller: controller),
            ),
          ],
        );
      }),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: AppThemeConfig.mutedText(context),
            ),
            const SizedBox(height: 14),
            Text(
              'Your cart is empty.'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add products to see them here.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppThemeConfig.mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineItem extends StatelessWidget {
  const _CartLineItem({
    required this.product,
    required this.quantity,
    required this.controller,
  });

  final Map<String, dynamic> product;
  final int quantity;
  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      product,
      'name',
      fallback: 'Product',
    );
    final price = double.tryParse((product['price'] ?? '0').toString()) ?? 0;
    final currency = (product['currency'] ?? 'IQD').toString();
    final imageUrl = _cartImageUrl(product['image_path']);

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 64,
              height: 64,
              child: imageUrl == null
                  ? const _CartThumbnailFallback()
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 180),
                      errorWidget: (context, url, error) =>
                          const _CartThumbnailFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMoney(price, currency),
                  style: TextStyle(color: AppThemeConfig.mutedText(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CartQuantityStepper(
            quantity: quantity,
            onAdd: () => controller.addProduct(product),
            onRemove: () => controller.removeProduct(product['id']),
          ),
        ],
      ),
    );
  }
}

class _CartThumbnailFallback extends StatelessWidget {
  const _CartThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.deepOrange.withValues(alpha: 0.12),
      child: const Icon(
        Icons.storefront_rounded,
        color: Colors.deepOrange,
        size: 26,
      ),
    );
  }
}

class _CartQuantityStepper extends StatelessWidget {
  const _CartQuantityStepper({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_rounded),
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '$quantity',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppThemeConfig.text(context),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _CartCheckoutPanel extends StatelessWidget {
  const _CartCheckoutPanel({required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment method'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 10),
            _CartPaymentCard(
              icon: Icons.payments_rounded,
              title: 'Cash'.tr,
              subtitle: 'Pay when your order arrives.'.tr,
              selected: !controller.payWithWallet.value,
              onTap: () => controller.payWithWallet.value = false,
            ),
            const SizedBox(height: 10),
            _CartPaymentCard(
              icon: Icons.account_balance_wallet_rounded,
              title: 'App Wallet'.tr,
              subtitle:
                  '${'Balance'.tr}: ${controller.walletBalanceIQD.value} IQD',
              selected: controller.payWithWallet.value,
              onTap: () => controller.payWithWallet.value = true,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${controller.totalQuantity} ${'items'.tr}',
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatMoney(
                          controller.totalAmount,
                          controller.currency,
                        ),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: controller.isCheckingOut.value
                      ? null
                      : controller.clearCart,
                  child: Text('Clear'.tr),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                // Note #40 — a marketplace order is a "purchase", restricted
                // for guests (also enforced server-side).
                onPressed: controller.isCheckingOut.value
                    ? null
                    : () async {
                        if (!await requireUpgrade(context)) return;
                        await controller.checkoutCart();
                        // Success clears the cart; a failed attempt leaves
                        // it in place so the user can retry from here.
                        if (context.mounted &&
                            controller.cartQuantities.isEmpty) {
                          Navigator.of(context).maybePop();
                        }
                      },
                icon: controller.isCheckingOut.value
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                label: Text('Checkout'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartPaymentCard extends StatelessWidget {
  const _CartPaymentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Colors.deepOrange;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? accent : AppThemeConfig.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                TileIcon(icon: icon, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppThemeConfig.text(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? accent : Colors.transparent,
                    border: Border.all(
                      color: selected ? accent : AppThemeConfig.border(context),
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _cartImageUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;

  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;

  return Uri.parse(publicBaseUrl).resolve(path).toString();
}

String _formatMoney(double amount, String currency) {
  final locale = Get.locale?.toLanguageTag() ?? 'en';
  final formatter = NumberFormat.decimalPattern(locale);
  return '${formatter.format(amount)} $currency';
}
