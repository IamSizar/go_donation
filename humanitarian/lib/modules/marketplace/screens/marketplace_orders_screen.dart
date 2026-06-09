import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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
                final error = controller.ordersErrorMessage.value;
                final orders = controller.orders;

                return RefreshIndicator(
                  onRefresh: controller.fetchOrders,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      if (controller.isLoadingOrders.value)
                        const Center(child: CircularProgressIndicator()),
                      if (error != null)
                        SectionTile(
                          icon: Icons.receipt_long_rounded,
                          title: 'Your orders',
                          subtitle: error,
                          color: Colors.deepOrange,
                          onTap: controller.fetchOrders,
                        ),
                      if (error == null &&
                          !controller.isLoadingOrders.value &&
                          orders.isEmpty)
                        SectionTile(
                          icon: Icons.receipt_long_rounded,
                          title: 'Your orders',
                          subtitle: 'Your marketplace orders will appear here.',
                          color: Colors.deepOrange,
                          onTap: controller.fetchOrders,
                        ),
                      for (final order in orders) ...[
                        _MarketplaceOrderCard(order: order),
                        const SizedBox(height: 12),
                      ],
                    ],
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
          TileIcon(icon: _statusIcon(status), color: _statusColor(status)),
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
                    _StatusPill(status: status),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        status.tr,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

Color _statusColor(String status) {
  return switch (status) {
    'approved' => Colors.green,
    'processing' => Colors.blueAccent,
    'completed' => Colors.teal,
    'cancelled' => Colors.redAccent,
    _ => Colors.orange,
  };
}

IconData _statusIcon(String status) {
  return switch (status) {
    'approved' => Icons.verified_rounded,
    'processing' => Icons.local_shipping_rounded,
    'completed' => Icons.check_circle_rounded,
    'cancelled' => Icons.cancel_rounded,
    _ => Icons.hourglass_bottom_rounded,
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
