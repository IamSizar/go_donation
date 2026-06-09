import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_orders_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class MarketplaceSection extends StatelessWidget {
  const MarketplaceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionScaffold(
      title: 'Marketplace',
      subtitle: 'Discover products from productive families and track orders.',
      child: _MarketplaceList(),
    );
  }
}

class _MarketplaceList extends StatelessWidget {
  const _MarketplaceList();

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MarketplaceController>()
        ? Get.find<MarketplaceController>()
        : Get.put(MarketplaceController());

    return Obx(() {
      final items = controller.products;
      final error = controller.errorMessage.value;

      return Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 220) {
                controller.loadMoreProducts();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: controller.refreshMarketplace,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
                children: [
                  _OrdersShortcut(controller: controller),
                  const SizedBox(height: 12),
                  if (controller.isLoading.value)
                    const Center(child: CircularProgressIndicator()),
                  if (error != null)
                    SectionTile(
                      icon: Icons.storefront_rounded,
                      title: 'Product Listings',
                      subtitle: error,
                      color: Colors.deepOrange,
                      onTap: () => controller.fetchProducts(reset: true),
                    ),
                  if (error == null &&
                      !controller.isLoading.value &&
                      items.isEmpty)
                    const SectionTile(
                      icon: Icons.storefront_rounded,
                      title: 'Product Listings',
                      subtitle: 'No approved products are available yet.',
                      color: Colors.deepOrange,
                    ),
                  for (var i = 0; i < items.length; i++) ...[
                    _AnimatedProductEntry(
                      index: i,
                      child: _MarketplaceProductTile(
                        item: items[i],
                        controller: controller,
                        quantity: controller.quantityFor(items[i]['id']),
                        onAdd: () => controller.addProduct(items[i]),
                        onRemove: () =>
                            controller.removeProduct(items[i]['id']),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _LoadMoreProductsFooter(controller: controller),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Obx(
              () => AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, 0.35),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: offset,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                  );
                },
                child: controller.totalQuantity > 0
                    ? _CartSummary(
                        key: const ValueKey('marketplace-cart'),
                        controller: controller,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('marketplace-cart-empty'),
                      ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _AnimatedProductEntry extends StatelessWidget {
  const _AnimatedProductEntry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(index),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index % 5) * 30),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _MarketplaceProductTile extends StatefulWidget {
  const _MarketplaceProductTile({
    required this.item,
    required this.controller,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, dynamic> item;
  final MarketplaceController controller;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  State<_MarketplaceProductTile> createState() =>
      _MarketplaceProductTileState();
}

class _MarketplaceProductTileState extends State<_MarketplaceProductTile> {
  bool _longPressSheetOpen = false;
  BuildContext? _detailsSheetContext;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      widget.item,
      'name',
      fallback: 'Product',
    );
    final category = (widget.item['category'] ?? 'Product').toString();
    final price = _amountFrom(widget.item['price']);
    final currency = (widget.item['currency'] ?? 'IQD').toString();
    final imageUrl = _marketplaceImageUrl(widget.item['image_path']);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showProductDetails(context),
      onLongPressStart: (_) =>
          _showProductDetails(context, closeOnRelease: true),
      onLongPressEnd: (_) => _closeLongPressDetails(context),
      onLongPressCancel: () => _closeLongPressDetails(context),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _ProductImage(imageUrl: imageUrl),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    category.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppThemeConfig.mutedText(context)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _formatMoney(price, currency),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _QuantityControl(
              quantity: widget.quantity,
              onAdd: widget.onAdd,
              onRemove: widget.onRemove,
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetails(
    BuildContext context, {
    bool closeOnRelease = false,
  }) {
    if (_longPressSheetOpen) return;
    _longPressSheetOpen = closeOnRelease;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _detailsSheetContext = sheetContext;
        return _ProductDetailsSheet(
          item: widget.item,
          controller: widget.controller,
        );
      },
    ).whenComplete(() {
      _longPressSheetOpen = false;
      _detailsSheetContext = null;
    });
  }

  void _closeLongPressDetails(BuildContext context) {
    if (!_longPressSheetOpen) return;
    final sheetContext = _detailsSheetContext;
    if (sheetContext == null) return;
    Navigator.of(sheetContext).pop();
  }
}

class _ProductDetailsSheet extends StatelessWidget {
  const _ProductDetailsSheet({required this.item, required this.controller});

  final Map<String, dynamic> item;
  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(item, 'name', fallback: 'Product');
    final category = (item['category'] ?? 'Product').toString();
    final description = localizedContentFromMap(item, 'description');
    final price = _amountFrom(item['price']);
    final currency = (item['currency'] ?? 'IQD').toString();
    final imageUrl = _marketplaceImageUrl(item['image_path']);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0, 1).toDouble(),
              child: Transform.scale(
                scale: value,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppThemeConfig.mutedText(
                        context,
                      ).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ProductLargeImage(imageUrl: imageUrl),
                const SizedBox(height: 16),
                Text(
                  title.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  category.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppThemeConfig.mutedText(context)),
                ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    description.tr,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      height: 1.35,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatMoney(price, currency),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                    ),
                    Obx(
                      () => _QuantityControl(
                        quantity: controller.quantityFor(item['id']),
                        onAdd: () => controller.addProduct(item),
                        onRemove: () => controller.removeProduct(item['id']),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: quantity <= 0
          ? FilledButton(
              key: const ValueKey('add'),
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Add'.tr),
            )
          : AnimatedContainer(
              key: ValueKey('quantity-$quantity'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.deepOrange.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.remove_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Text(
                      '$quantity',
                      key: ValueKey(quantity),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
    );
  }
}

class _LoadMoreProductsFooter extends StatelessWidget {
  const _LoadMoreProductsFooter({required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.products.isEmpty ||
          controller.errorMessage.value != null) {
        return const SizedBox.shrink();
      }

      if (controller.isLoadingMoreProducts.value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('Loading more products'.tr),
              ],
            ),
          ),
        );
      }

      if (!controller.hasMoreProducts.value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            'You reached the end.'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppThemeConfig.mutedText(context)),
          ),
        );
      }

      return const SizedBox(height: 24);
    });
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Obx(
        () => AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppThemeConfig.primary.withValues(alpha: 0.18),
                Colors.deepOrange.withValues(alpha: 0.14),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${controller.totalQuantity} ${'items'.tr}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatMoney(controller.totalAmount, controller.currency),
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
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
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: controller.isCheckingOut.value
                    ? null
                    : controller.checkoutCart,
                icon: controller.isCheckingOut.value
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        size: 18,
                      ),
                label: Text('Checkout'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersShortcut extends StatelessWidget {
  const _OrdersShortcut({required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final count = controller.orders.length;

      return SectionTile(
        icon: Icons.receipt_long_rounded,
        title: 'Your orders',
        subtitle: count == 0
            ? 'Track your marketplace order status.'
            : '$count ${'orders'.tr} • ${'Track your marketplace order status.'.tr}',
        color: Colors.deepOrange,
        onTap: () => Get.to(() => const MarketplaceOrdersScreen()),
      );
    });
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 92,
        height: 92,
        child: imageUrl == null
            ? const _ProductImageFallback()
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (context, url) => const _ProductImageLoading(),
                errorWidget: (context, url, error) =>
                    const _ProductImageFallback(),
              ),
      ),
    );
  }
}

class _ProductLargeImage extends StatelessWidget {
  const _ProductLargeImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: imageUrl == null
            ? const _ProductImageFallback()
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (context, url) => const _ProductImageLoading(),
                errorWidget: (context, url, error) =>
                    const _ProductImageFallback(),
              ),
      ),
    );
  }
}

class _ProductImageLoading extends StatelessWidget {
  const _ProductImageLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.deepOrange.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

class _ProductImageFallback extends StatelessWidget {
  const _ProductImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.deepOrange.withValues(alpha: 0.12),
      child: const Icon(
        Icons.storefront_rounded,
        color: Colors.deepOrange,
        size: 48,
      ),
    );
  }
}

String? _marketplaceImageUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;

  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;

  return Uri.parse(publicBaseUrl).resolve(path).toString();
}

double _amountFrom(dynamic value) {
  return double.tryParse((value ?? '0').toString()) ?? 0;
}

String _formatMoney(double amount, String currency) {
  final locale = Get.locale?.toLanguageTag() ?? 'en';
  final formatter = NumberFormat.decimalPattern(locale);
  return '${formatter.format(amount)} $currency';
}
