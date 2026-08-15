import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/core/widgets/app_row.dart';

class MarketplaceOrdersScreen extends StatelessWidget {
  const MarketplaceOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MarketplaceController>()
        ? Get.find<MarketplaceController>()
        : Get.put(MarketplaceController());

    return GradientScreen(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: 'Your orders'),
            ),
            Expanded(
              child: Obx(() {
                // Three stacked `if` blocks replaced by one state. Before, a
                // failed load drew the error tile AND any cached orders under
                // it, and both the error and the empty tile were SectionTiles
                // whose onTap was the retry - unlabelled, and identical in
                // shape to the order cards below them.
                return AppAsync<List<dynamic>>(
                  loading: controller.isLoadingOrders.value,
                  error: controller.ordersErrorMessage.value,
                  onRetry: controller.fetchOrders,
                  data: controller.orders,
                  isEmpty: (list) => list.isEmpty,
                  empty: const AppEmpty(
                    icon: Icons.receipt_long_rounded,
                    title: 'Your orders',
                    message: 'Your marketplace orders will appear here.',
                  ),
                  builder: (list) => RefreshIndicator(
                    onRefresh: controller.fetchOrders,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      children: [
                        for (final order in list) ...[
                          _MarketplaceOrderCard(order: order),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketplaceOrderCard extends StatelessWidget {
  const _MarketplaceOrderCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(order, 'name', fallback: 'Product');
    final quantity = (order['quantity'] ?? '1').toString();
    final total = _amountFrom(order['total_amount']);
    final currency = (order['currency'] ?? 'IQD').toString();
    final status = (order['status'] ?? 'pending').toString();
    final createdAt = (order['created_at'] ?? '').toString();

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spec item 13 — the order status used to be drawn three times on
          // this one card: as the leading glyph, as that glyph's colour, and
          // as the pill next to the title. The leading mark is now a plain
          // "this is an order" icon in the accent colour, so the status is
          // stated exactly once, in words, by the tag.
          TileIcon(
            icon: Icons.receipt_long_rounded,
            color: AppThemeConfig.accent(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.tr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppStatusTag(label: status, tone: _statusTone(status)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('${'Quantity'.tr}: $quantity'),
                const SizedBox(height: 4),
                Text('${'Total'.tr}: ${_formatMoney(total, currency)}'),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${'Submitted'.tr}: $createdAt'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps an order status onto the design system's semantic tones.
///
/// The local pill and its bespoke colour switch are gone: [AppStatusTag] is
/// the app-wide status word, so orders now look like every other status in
/// the app and the word — not the colour — carries the meaning.
AppStatusTone _statusTone(String status) {
  return switch (status) {
    // Approved, shipped and delivered are all "settled" as far as the donor
    // is concerned: nothing is outstanding on their side.
    'approved' || 'processing' || 'completed' => AppStatusTone.settled,
    'cancelled' => AppStatusTone.attention,
    _ => AppStatusTone.pending,
  };
}

double _amountFrom(dynamic value) {
  return double.tryParse((value ?? '0').toString()) ?? 0;
}

String _formatMoney(double amount, String currency) {
  final locale = Get.locale?.toLanguageTag() ?? 'en';
  final formatter = NumberFormat.decimalPattern(locale);
  return '${formatter.format(amount)} $currency';
}
