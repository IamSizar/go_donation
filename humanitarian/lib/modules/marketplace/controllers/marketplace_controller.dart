import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_sound.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/realtime_polling.dart';
import 'package:get/get.dart';

class MarketplaceController extends GetxController
    with RealtimePollingMixin {
  static const int _productsPerPage = 10;
  static const int _ordersPerPage = 100;

  final isLoading = false.obs;
  final isLoadingMoreProducts = false.obs;
  final isLoadingOrders = false.obs;
  final isCheckingOut = false.obs;
  final hasMoreProducts = true.obs;
  final products = <Map<String, dynamic>>[].obs;
  final orders = <Map<String, dynamic>>[].obs;
  final cartQuantities = <int, int>{}.obs;
  final errorMessage = RxnString();
  final ordersErrorMessage = RxnString();
  var _productsPage = 1;

  // Status snapshot per order id, for diff detection between polls.
  Map<String, String> _lastOrderStatusSnapshot = {};

  @override
  void onInit() {
    super.onInit();
    fetchProducts(reset: true);
    fetchOrders();
    // Only orders need real-time updates; products refresh on manual
    // pull-to-refresh. Polling orders alone keeps the request volume low.
    startPolling();
  }

  @override
  Future<void> realtimePoll() => fetchOrders(silent: true);

  Future<void> fetchProducts({bool reset = false}) async {
    if (reset) {
      _productsPage = 1;
      hasMoreProducts.value = true;
    }

    isLoading.value = true;
    errorMessage.value = null;

    try {
      final rows = await _fetchProductsPage(_productsPage);
      products.assignAll(rows);
      hasMoreProducts.value = rows.length == _productsPerPage;
    } catch (_) {
      products.clear();
      errorMessage.value = 'Unable to load products from the server.'.tr;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMoreProducts() async {
    if (isLoading.value ||
        isLoadingMoreProducts.value ||
        !hasMoreProducts.value ||
        errorMessage.value != null) {
      return;
    }

    isLoadingMoreProducts.value = true;
    try {
      final nextPage = _productsPage + 1;
      final rows = await _fetchProductsPage(nextPage);
      _productsPage = nextPage;
      products.addAll(rows);
      hasMoreProducts.value = rows.length == _productsPerPage;
    } catch (_) {
      Get.snackbar('Marketplace'.tr, 'Unable to load more products.'.tr);
    } finally {
      isLoadingMoreProducts.value = false;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchProductsPage(int page) {
    final uri = Uri.parse(
      marketplaceProductsUrl,
    ).replace(queryParameters: {'page': '$page', 'limit': '$_productsPerPage'});
    return const ModuleApi().getItems(uri.toString());
  }

  Future<void> refreshMarketplace() async {
    await Future.wait([fetchProducts(reset: true), fetchOrders()]);
  }

  Future<void> fetchOrders({bool silent = false}) async {
    final userId = sharedPreferences.getString('id_user') ?? '';
    if (userId.isEmpty) {
      orders.clear();
      return;
    }

    if (!silent) {
      isLoadingOrders.value = true;
      ordersErrorMessage.value = null;
    }

    try {
      final uri = Uri.parse(marketplaceProductsUrl).replace(
        queryParameters: {
          'view': 'orders',
          'user_id': userId,
          'limit': '$_ordersPerPage',
        },
      );
      final rows = await const ModuleApi().getItems(uri.toString());
      orders.assignAll(rows);
      _detectAndAnnounceOrderTransitions();
    } catch (_) {
      if (!silent) {
        orders.clear();
        ordersErrorMessage.value = 'Unable to load your orders.'.tr;
      }
      // Silent mode keeps the previous order list on screen so a
      // dropped poll doesn't make orders disappear briefly.
    } finally {
      if (!silent) isLoadingOrders.value = false;
    }
  }

  /// Diff order statuses between polls; snackbar + haptic on transitions.
  void _detectAndAnnounceOrderTransitions() {
    final transitions = detectStatusTransitions<Map<String, dynamic>>(
      items: orders,
      keyOf: (m) => (m['id'] ?? '').toString(),
      statusOf: (m) => (m['status'] ?? '').toString().toLowerCase(),
      previous: _lastOrderStatusSnapshot,
    );
    _lastOrderStatusSnapshot = {
      for (final m in orders)
        (m['id'] ?? '').toString():
            (m['status'] ?? '').toString().toLowerCase(),
    };
    for (final t in transitions) {
      final msg = _messageForOrderTransition(t.toStatus);
      if (msg == null) continue;
      AppSound.notification();
      AppHaptics.gentle();
      Get.snackbar(
        'Order update'.tr,
        msg,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(12),
        borderRadius: 12,
      );
    }
  }

  String? _messageForOrderTransition(String to) {
    switch (to) {
      case 'confirmed':
      case 'approved':
        return 'Your order was confirmed.'.tr;
      case 'shipped':
      case 'dispatched':
        return 'Your order is on its way.'.tr;
      case 'delivered':
      case 'completed':
        return 'Your order was delivered.'.tr;
      case 'cancelled':
      case 'refunded':
        return 'Your order was cancelled.'.tr;
      default:
        return null;
    }
  }

  int quantityFor(dynamic productId) {
    final id = _productId(productId);
    if (id == null) return 0;
    return cartQuantities[id] ?? 0;
  }

  void addProduct(Map<String, dynamic> product) {
    final id = _productId(product['id']);
    if (id == null) return;

    final nextQuantity = quantityFor(id) + 1;
    final stockQuantity = int.tryParse(
      (product['stock_quantity'] ?? '').toString(),
    );
    if (stockQuantity != null &&
        stockQuantity > 0 &&
        nextQuantity > stockQuantity) {
      Get.snackbar(
        'Marketplace'.tr,
        'Only @count available.'.trParams({'count': '$stockQuantity'}),
      );
      return;
    }

    cartQuantities[id] = nextQuantity;
  }

  void removeProduct(dynamic productId) {
    final id = _productId(productId);
    if (id == null) return;

    final nextQuantity = quantityFor(id) - 1;
    if (nextQuantity <= 0) {
      cartQuantities.remove(id);
      return;
    }
    cartQuantities[id] = nextQuantity;
  }

  void clearCart() {
    cartQuantities.clear();
  }

  int get totalQuantity =>
      cartQuantities.values.fold(0, (sum, quantity) => sum + quantity);

  double get totalAmount {
    var total = 0.0;
    for (final product in products) {
      final id = _productId(product['id']);
      if (id == null) continue;
      final quantity = cartQuantities[id] ?? 0;
      final price = double.tryParse((product['price'] ?? '0').toString()) ?? 0;
      total += price * quantity;
    }
    return total;
  }

  String get currency {
    for (final product in products) {
      final id = _productId(product['id']);
      if (id != null && (cartQuantities[id] ?? 0) > 0) {
        return (product['currency'] ?? 'IQD').toString();
      }
    }
    return 'IQD';
  }

  Future<void> checkoutCart() async {
    if (cartQuantities.isEmpty) {
      Get.snackbar('Marketplace'.tr, 'Add products to the cart first.'.tr);
      return;
    }
    if (isCheckingOut.value) return;

    isCheckingOut.value = true;
    final entries = Map<int, int>.from(cartQuantities);
    final userId = sharedPreferences.getString('id_user') ?? '';

    try {
      for (final entry in entries.entries) {
        if (entry.value <= 0) continue;
        await const ModuleApi().postJson(marketplaceProductsUrl, {
          'product_id': entry.key,
          'user_id': userId,
          'quantity': entry.value,
        });
      }
      clearCart();
      await fetchOrders();
      Get.snackbar('Submitted'.tr, 'Order request saved.'.tr);
    } catch (e) {
      Get.snackbar('Error'.tr, e.toString());
    } finally {
      isCheckingOut.value = false;
    }
  }

  int? _productId(dynamic value) {
    final id = int.tryParse((value ?? '').toString());
    if (id == null || id <= 0) return null;
    return id;
  }
}
