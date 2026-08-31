import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/item_count.dart';
import 'package:flutter_application_1/core/design/directional_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/cart_screen.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_orders_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/widgets/app_list_search_field.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/marketplace/models/catalogue_query.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/catalogue_filter_bar.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/product_gallery.dart';

/// Identifies the catalogue's own scrollable — the search field, filter
/// bar, and product list all live inside this one `ListView`. Exposed so
/// tests can target it directly rather than `find.byType(ListView).first`,
/// which would silently start matching the wrong list the day a second
/// `ListView` is added anywhere in this screen's subtree.
const marketplaceResultsListKey = Key('marketplace-results-list');

class MarketplaceSection extends StatelessWidget {
  const MarketplaceSection({super.key, this.title = ''});

  /// The heading this screen draws for itself, or '' to draw none.
  ///
  /// Empty is right in exactly one place: inside the dashboard's المتجر tab,
  /// where dashboard_screen.dart's persistent top bar already names the screen
  /// and a second heading would repeat it.
  ///
  /// It was hardcoded to '' for that case, but three of the four call sites
  /// PUSH this widget as its own route — the Home quick action
  /// (dashboard.dart) and both global-search results — and a pushed route has
  /// no persistent bar to inherit from. Tapping "منتجاتنا" therefore opened a
  /// screen with an empty app bar: no name, no context, and a back chevron as
  /// the only clue to where you were.
  ///
  /// Defaulting to '' keeps the embedded case correct without the tab having
  /// to say so, while letting the pushed callers name themselves.
  final String title;

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: title,
      subtitle: '',
      child: const _MarketplaceList(),
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
                key: marketplaceResultsListKey,
                // Scrolling the catalogue puts the keyboard away, so it never
                // covers the products the search just found.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                // Scaffold already reserves space above the bottom nav bar —
                // this only needs a small resting margin, not extra
                // clearance for it.
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // The orders shortcut is a standing entry point, not
                  // content: a shopper must still be able to reach their
                  // existing orders when the product fetch fails.
                  _OrdersShortcut(controller: controller),
                  const SizedBox(height: 12),
                  // J8 — catalogue search. This is the list where a local
                  // filter would be most obviously wrong: products arrive ten
                  // at a time, so a box over the loaded rows would search page
                  // one and tell the shopper the item is not sold. Sent as
                  // `?q=`, which the server matches against name, name_ar,
                  // description, sku and brand — so an SKU off a receipt finds
                  // the product.
                  AppListSearchField(onChanged: controller.setProductSearch),
                  const SizedBox(height: 12),
                  // K15 — the client's six functional labels. Every one of them
                  // is a parameter on GET /api/marketplace, never a re-sort of
                  // the ten rows below: `Store.ListCatalogue` ranks the whole
                  // catalogue in SQL, and a chip that ranked this page would
                  // reinstate the exact defect b59c357 removed.
                  CatalogueFilterBar(controller: controller),
                  const SizedBox(height: 12),
                  // Three stacked `if` blocks replaced by one state. Before,
                  // a failed load rendered the error tile AND whatever
                  // products were already cached beneath it, and the error
                  // was a SectionTile whose retry was an unlabelled onTap.
                  AppAsync<List<Map<String, dynamic>>>(
                    loading: controller.isLoading.value,
                    error: error,
                    onRetry: () => controller.fetchProducts(reset: true),
                    data: items,
                    isEmpty: (list) => list.isEmpty,
                    // J8 — a search that matched nothing is not an empty
                    // shop. "No approved products are available yet" would be
                    // a claim about the whole catalogue, made because one word
                    // did not match. K15 extends the same reasoning to the
                    // filter chips, which can empty the list just as easily
                    // and are just as much the user's own doing.
                    empty: controller.isCatalogueNarrowed
                        ? AppEmpty(
                            icon: Icons.search_off_rounded,
                            title: controller.hasActiveSearch
                                ? 'search_title'
                                : 'catalogue_no_results',
                            message: controller.hasActiveSearch
                                ? 'search_no_results'
                                : 'catalogue_no_results_desc',
                            actionLabel: 'All',
                            onAction: controller.clearCatalogueFilters,
                          )
                        : const AppEmpty(
                            title: 'Product Listings',
                            message: 'No approved products are available yet.',
                          ),
                    builder: (list) => Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          _AnimatedProductEntry(
                            index: i,
                            child: _MarketplaceProductTile(
                              item: list[i],
                              controller: controller,
                              quantity: controller.quantityFor(list[i]['id']),
                              onAdd: () => controller.addProduct(list[i]),
                              onRemove: () =>
                                  controller.removeProduct(list[i]['id']),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        // Pagination footer stays with the content: it is
                        // "load MORE", which only means anything once there
                        // is a first page.
                        _LoadMoreProductsFooter(controller: controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            // The floating bottom nav bar (its own Positioned pill, ~118pt
            // tall including its safe-area bottom padding) sits below the
            // body when `extendBody: true` — this needs enough clearance to
            // sit above it rather than being covered by it.
            bottom: 130,
            child: Obx(
              () => AnimatedSwitcher(
                duration: AppMotion.resolve(context, AppMotion.settleDuration),
                switchInCurve: AppMotion.resolveCurve(
                  context,
                  Curves.easeOutBack,
                ),
                switchOutCurve: AppMotion.resolveCurve(
                  context,
                  Curves.easeInCubic,
                ),
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
                    ? _CartTeaserBar(
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
      curve: AppMotion.resolveCurve(context, Curves.easeOutCubic),
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
    final category = widget.controller.categoryLabel(widget.item); // #28
    final labels = _productLabels(widget.item['labels']); // #28
    // Price and currency are read inside _ProductPrice now — it has to weigh
    // `price` against `price_after_discount`, and pulling one of the pair out
    // here is how the two could drift apart.
    final imageUrl = marketplaceMediaUrl(widget.item['image_path']);

    // Deliberately NOT AppPressable: this card's press IS a peek-preview
    // (hold to open, release to close), so a press-scale would fight the
    // sheet animation and AppPressable models tap only.
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
                  if (category.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      category.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                  if (labels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ProductLabelChips(labels: labels),
                  ],
                  const SizedBox(height: 10),
                  _ProductPrice(item: widget.item),
                  // K15 — the figure الأكثر مبيعاً is actually ranked by,
                  // shown only while that chip is lit. A claim of "best
                  // selling" with nothing behind it is unverifiable by the
                  // person reading it; off that sort the number is noise.
                  if (widget.controller.catalogueQuery.value.sort ==
                      CatalogueSort.bestSelling) ...[
                    const SizedBox(height: 6),
                    _SoldCount(item: widget.item),
                  ],
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
    final category = controller.categoryLabel(item); // #28
    final labels = _productLabels(item['labels']); // #28
    final sku = (item['sku'] ?? '').toString(); // #28
    final specs = _productSpecs(item['specs']); // #28
    final description = localizedContentFromMap(item, 'description');
    final imageUrl = marketplaceMediaUrl(item['image_path']);
    // Migration 117 — the product's ADDITIONAL photos. Empty for almost every
    // product, and empty is drawn as nothing at all, so a product without a
    // gallery looks exactly as it did before this existed.
    final gallery = marketplaceGalleryUrls(item['gallery']);

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
          duration: AppMotion.resolve(context, AppMotion.settleDuration),
          curve: AppMotion.resolveCurve(context, Curves.easeOutBack),
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
            // The sheet was an unscrollable Column sized to its contents: a
            // product with a long description, specs AND a photo strip could
            // grow past the screen and overflow. Capping it and letting it
            // scroll means extra content is reachable rather than clipped,
            // while a short product still gets a sheet only as tall as it
            // needs — MainAxisSize.min below is what keeps that true.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
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
                    if (gallery.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ProductGallery(urls: gallery),
                    ],
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
                    if (category.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        category.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                    if (labels.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ProductLabelChips(labels: labels),
                    ],
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
                    if (sku.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${'SKU'.tr}: $sku',
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (specs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ProductSpecs(specs: specs),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // The same discounted/original pair the card shows. Two
                        // renderings of one price is how a sheet ends up quoting
                        // the pre-discount figure under an العروض والخصومات chip.
                        Expanded(child: _ProductPrice(item: item)),
                        Obx(
                          () => _QuantityControl(
                            quantity: controller.quantityFor(item['id']),
                            onAdd: () => controller.addProduct(item),
                            onRemove: () =>
                                controller.removeProduct(item['id']),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// K15 — the price a shopper actually pays, and the one they are saving from.
///
/// `price_after_discount` is computed by the server (price × (100 −
/// discount_percent), already rounded) and equals `price` when there is no
/// offer, so this has one field to print rather than a rounding rule to get
/// wrong in a fourth place. The original is struck through ONLY when the two
/// differ — showing a struck-through price identical to the live one would
/// invent a discount.
class _ProductPrice extends StatelessWidget {
  const _ProductPrice({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final currency = (item['currency'] ?? 'IQD').toString();
    final price = _amountFrom(item['price']);
    final payable = item.containsKey('price_after_discount')
        ? _amountFrom(item['price_after_discount'])
        : price;
    final discounted = payable > 0 && payable < price;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            formatMoney(discounted ? payable : price, currency),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: discounted
                  ? AppThemeConfig.consequence(context)
                  : AppThemeConfig.text(context),
            ),
          ),
        ),
        if (discounted) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              formatMoney(price, currency),
              style: TextStyle(
                fontSize: 12.5,
                decoration: TextDecoration.lineThrough,
                color: AppThemeConfig.mutedText(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// How many of this product have sold, under the الأكثر مبيعاً ranking.
///
/// `sold_count` is SUM(quantity) over approved/processing/completed orders —
/// a cancelled order is not a sale. Absent (an older response) renders
/// nothing rather than a confident zero.
class _SoldCount extends StatelessWidget {
  const _SoldCount({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final sold = int.tryParse((item['sold_count'] ?? '').toString());
    if (sold == null) return const SizedBox.shrink();
    return Text(
      // The numeral is isolated LTR (U+2066 … U+2069) before it is dropped
      // into an Arabic sentence, like every other number-in-text in this app.
      'catalogue_sold_count'.trParams({'count': '\u2066$sold\u2069'}),
      style: TextStyle(
        color: AppThemeConfig.mutedText(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// #28 — product labels (fixed enum) rendered as colored badges.
List<String> _productLabels(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }
  return const [];
}

// #28 — parse the free-text specs sheet ("Key: Value" per line) into rows.
List<MapEntry<String, String>> _productSpecs(dynamic raw) {
  final text = (raw ?? '').toString();
  if (text.trim().isEmpty) return const [];
  final out = <MapEntry<String, String>>[];
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final idx = t.indexOf(':');
    if (idx > 0) {
      out.add(
        MapEntry(t.substring(0, idx).trim(), t.substring(idx + 1).trim()),
      );
    } else {
      out.add(MapEntry(t, ''));
    }
  }
  return out;
}

class _ProductLabelChips extends StatelessWidget {
  const _ProductLabelChips({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final l in labels) _LabelChip(label: l)],
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.label});

  final String label;

  Color _color(BuildContext context) {
    switch (label) {
      case 'new':
        return AppThemeConfig.accent(context);
      case 'sale':
        return AppThemeConfig.consequence(context);
      case 'featured':
        return AppThemeConfig.pending(context);
      case 'used':
        return AppThemeConfig.subtleText(context);
      case 'in_stock':
        return AppThemeConfig.accent(context);
      default:
        return AppThemeConfig.subtleText(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ('label_$label').tr,
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5),
      ),
    );
  }
}

class _ProductSpecs extends StatelessWidget {
  const _ProductSpecs({required this.specs});

  final List<MapEntry<String, String>> specs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in specs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.value.isNotEmpty) ...[
                  Text(
                    '${s.key}: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppThemeConfig.text(context),
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.value,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      s.key,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
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
      duration: AppMotion.resolve(context, AppMotion.settleDuration),
      switchInCurve: AppMotion.resolveCurve(context, Curves.easeOutBack),
      switchOutCurve: AppMotion.resolveCurve(context, Curves.easeIn),
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
              duration: AppMotion.resolve(context, AppMotion.settleDuration),
              curve: AppMotion.resolveCurve(context, Curves.easeOutCubic),
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
                    duration: AppMotion.resolve(
                      context,
                      AppMotion.snapDuration,
                    ),
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

/// Note — the cart used to render its full summary (payment method, totals,
/// clear/checkout) as a floating panel right here, but everything having to
/// fit in one small overlay bar kept it cramped no matter how it was laid
/// out. Now it's just a tappable teaser showing item count + total; tapping
/// it opens the dedicated `CartScreen` for everything else.
class _CartTeaserBar extends StatelessWidget {
  const _CartTeaserBar({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => Get.to(() => const CartScreen()),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Obx(
            () => Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.shopping_cart_rounded,
                    color: AppThemeConfig.pending(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemCountLabel(controller.totalQuantity),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(
                          controller.totalAmount,
                          controller.currency,
                        ),
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  AppIcons.chevronForward(context),
                  color: AppThemeConfig.mutedText(context),
                ),
              ],
            ),
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
        color: AppThemeConfig.pending(context),
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
      child: Icon(
        Icons.storefront_rounded,
        color: AppThemeConfig.pending(context),
        size: 48,
      ),
    );
  }
}

double _amountFrom(dynamic value) {
  return double.tryParse((value ?? '0').toString()) ?? 0;
}
