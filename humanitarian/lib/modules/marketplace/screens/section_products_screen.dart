// SectionProductsScreen — the page a SectionsGrid tile opens: one store
// section's products, list style (per the client's explicit spec, unlike
// Beauty Lady Z's own 2-column product grid). Its own independent paged
// fetch (?section=<slug>), separate from MarketplaceController.products
// (the main store screen's unassigned-only feed) — but cart operations
// (add/remove/quantity) go through the SAME MarketplaceController singleton
// so the cart stays one cart regardless of which screen added to it.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

class SectionProductsScreen extends StatefulWidget {
  const SectionProductsScreen({
    super.key,
    required this.sectionSlug,
    required this.title,
  });

  final String sectionSlug;
  final String title;

  @override
  State<SectionProductsScreen> createState() => _SectionProductsScreenState();
}

class _SectionProductsScreenState extends State<SectionProductsScreen> {
  static const _perPage = 20;

  final MarketplaceController _controller = Get.isRegistered<MarketplaceController>()
      ? Get.find<MarketplaceController>()
      : Get.put(MarketplaceController());

  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final uri = Uri.parse(marketplaceProductsUrl).replace(
        queryParameters: {
          'page': '$_page',
          'limit': '$_perPage',
          'section': widget.sectionSlug,
        },
      );
      final page = await const ModuleApi().getListPage(
        uri.toString(),
        perPage: _perPage,
      );
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (reset) {
        setState(() => _error = 'Unable to load products.');
      }
    } finally {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _page += 1;
    await _load(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: widget.title,
      subtitle: '',
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 220) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (_loading || _error != null || _items.isEmpty)
                      SliverToBoxAdapter(
                        child: AppAsync<List<Map<String, dynamic>>>(
                          loading: _loading,
                          error: _error,
                          onRetry: () => _load(reset: true),
                          data: _items,
                          isEmpty: (list) => list.isEmpty,
                          empty: const AppEmpty(
                            title: 'No products yet',
                            message: 'Nothing has been added to this section yet.',
                          ),
                          builder: (list) => const SizedBox.shrink(),
                        ),
                      )
                    else ...[
                      SliverList.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AnimatedProductEntry(
                            index: i,
                            child: MarketplaceProductTile(
                              item: _items[i],
                              controller: _controller,
                              quantity: _controller.quantityFor(_items[i]['id']),
                              onAdd: () => _controller.addProduct(_items[i]),
                              onRemove: () =>
                                  _controller.removeProduct(_items[i]['id']),
                            ),
                          ),
                        ),
                      ),
                      if (_loadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        ),
                    ],
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
