// K15 — the six functional labels the client's product-list spec names:
// الأكثر مبيعاً · وصل حديثاً · العروض والخصومات · الفئات · العلامات التجارية · التصفية.
//
// EVERY ONE OF THESE IS A SERVER QUERY. NONE OF THEM TOUCHES THE LOADED PAGE.
// Products arrive ten at a time. A chip that re-sorted `controller.products`
// would rank ten rows while calling itself "الأكثر مبيعاً", which is precisely
// the lie commit b59c357 removed from the backend — ListProducts took no sort
// and no filter, so the only thing an app-side chip COULD have done was
// re-order what it was already holding. `Store.ListCatalogue` answers all six
// in SQL over the whole table, so this file's entire job is to build a query
// and hand it to the controller.
//
// There is deliberately no list-sorting code here to copy from later.
//
// WHY THREE OF THE SIX OPEN A SHEET
// الأكثر مبيعاً, وصل حديثاً and العروض والخصومات are single choices, so they are
// toggles. الفئات and العلامات التجارية are pickers over a server-supplied list —
// which can fail, and so carry all four states rather than vanishing. التصفية
// holds the compound controls (price range, availability, price ordering) that
// have no honest one-tap form.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/models/catalogue_query.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/catalogue_filter_sheets.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// The chip row above the product list.
class CatalogueFilterBar extends StatelessWidget {
  const CatalogueFilterBar({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final query = controller.catalogueQuery.value;

      return SizedBox(
        // See pillRowHeight's doc comment — this used to be a hardcoded 40.
        height: pillRowHeight(context),
        // Cancels the list's 20px side padding so a chip dragged toward the
        // edge does not disappear early — the same reason
        // case_category_capsules wraps its row.
        child: FullBleedHorizontal(
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              // No separate "All" clear chip — removed per explicit request:
              // every chip it could clear (best selling, newest, on sale) is
              // itself a toggle, so tapping the already-active chip again
              // clears it just as directly. Category/brand/refine are the
              // one case that chip also cleared and a re-tap doesn't (they
              // reopen their sheet rather than toggling), but that sheet has
              // its own way to reset, so nothing here goes unreachable.
              _Chip(
                chipKey: 'catalogue_chip_best_selling',
                label: 'catalogue_sort_best_selling'.tr,
                active: query.sort == CatalogueSort.bestSelling,
                onTap: () => _toggleSort(query, CatalogueSort.bestSelling),
              ),
              const SizedBox(width: 8),
              _Chip(
                chipKey: 'catalogue_chip_newest',
                label: 'catalogue_sort_newest'.tr,
                active: query.sort == CatalogueSort.newest,
                onTap: () => _toggleSort(query, CatalogueSort.newest),
              ),
              const SizedBox(width: 8),
              _Chip(
                chipKey: 'catalogue_chip_on_sale',
                label: 'catalogue_on_sale'.tr,
                active: query.onSale,
                onTap: () => controller.setCatalogueQuery(
                  query.copyWith(onSale: !query.onSale),
                ),
              ),
              // Store-sections overhaul — the الفئات chip is archived along
              // with marketplace_categories: sections (grid + own screen)
              // replaced it as how a shopper drills into a group of
              // products. See _categoryLabel's old doc comment history if
              // this ever needs restoring.
              const SizedBox(width: 8),
              _Chip(
                chipKey: 'catalogue_chip_brands',
                // THE BUG THIS FIXES: a brand name is free text a staff
                // member typed in whatever script they used, independent of
                // the app's own current locale — an Arabic brand name shows
                // up here even on an English-locale device. Dropped in raw,
                // its words got visibly reordered: the chip's ambient
                // Directionality is whatever the surrounding UI chrome
                // uses, and the Unicode bidi algorithm reorders a run of
                // RTL text relative to THAT base direction unless the run
                // is explicitly isolated. Wrapping it in RLI…PDI (U+2067…
                // U+2069) is the same fix this app already applies to a
                // number dropped into an Arabic sentence elsewhere
                // (_SoldCount) — isolate the foreign-direction span so its
                // own internal word order stays put no matter what
                // surrounds it.
                label: query.brand.isEmpty
                    ? 'catalogue_brands'.tr
                    : '\u2067${query.brand}\u2069',
                icon: Icons.expand_more_rounded,
                active: query.brand.isNotEmpty,
                onTap: () => openBrandSheet(context, controller),
              ),
              const SizedBox(width: 8),
              _Chip(
                chipKey: 'catalogue_chip_refine',
                label: 'catalogue_filters'.tr,
                icon: Icons.tune_rounded,
                active: _refineActive(query),
                onTap: () => openRefineSheet(context, controller),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Tapping the lit sort chip turns it off rather than doing nothing.
  ///
  /// A chip with no way back would leave the catalogue permanently ranked with
  /// no control to undo it, and tapping an already-active control and seeing no
  /// response reads as a broken button.
  Future<void> _toggleSort(CatalogueQuery query, String sort) {
    return controller.setCatalogueQuery(
      query.copyWith(sort: query.sort == sort ? CatalogueSort.none : sort),
    );
  }

  /// Whether التصفية's own controls — not the chips beside it — are doing
  /// anything. Without this the chip would sit unlit while a price range was
  /// quietly removing half the shop.
  bool _refineActive(CatalogueQuery query) =>
      query.inStockOnly ||
      query.minPrice != null ||
      query.maxPrice != null ||
      query.sort == CatalogueSort.priceAsc ||
      query.sort == CatalogueSort.priceDesc;
}

/// One capsule. Same geometry as the case-category capsules so the two rows
/// read as one system.
class _Chip extends StatefulWidget {
  const _Chip({
    required this.chipKey,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String chipKey;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // THE BUG THIS FIXES: this chip used to be a plain StatelessWidget that
    // read `active` straight into `Material.color`/text `color` — selecting
    // or deselecting a chip repainted it in the new colour on the very next
    // frame, with nothing in between. Swapping the raw values for their
    // Animated* counterparts is enough on its own: Flutter tweens from
    // whatever the widget's OLD color/style/scale was to the new one across
    // every rebuild, which is what "morphing" means here — no
    // AnimationController or extra state to manage for a chip that has none.
    final duration = AppMotion.resolve(context, AppMotion.settleDuration);
    const curve = Curves.easeOutCubic;
    final foreground = widget.active ? Colors.white : AppThemeConfig.text(context);
    // GestureDetector + a press-scale dip, not InkWell's ripple — matches
    // the tab bar's own tap feedback (dashboard_screen.dart's
    // _NavTapTarget) instead of the generic Material splash, now that this
    // row already carries a colour/text/icon morph of its own; a ripple on
    // top of that morph was two different kinds of feedback firing for one
    // tap.
    return GestureDetector(
      key: Key(widget.chipKey),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.selection();
        widget.onTap();
      },
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: AppMotion.resolve(context, AppMotion.snapDuration),
        curve: AppMotion.resolveCurve(context, Curves.easeOut),
        // A quick overshoot pop whenever this SPECIFIC chip flips into the
        // active state — keyed on `active` so the tween restarts from a
        // slightly-shrunk begin value only on the transition into
        // selection, not on every rebuild this row gets (e.g. a sibling
        // chip toggling). Deselecting just rides the colour/text morph
        // below with no extra pop; only gaining the selection earns one.
        child: TweenAnimationBuilder<double>(
          key: ValueKey(widget.active),
          tween: Tween(begin: widget.active ? 0.9 : 1.0, end: 1.0),
          duration: AppMotion.resolve(context, AppMotion.settleDuration),
          curve: AppMotion.resolveCurve(context, Curves.easeOutBack),
          builder: (context, pop, child) =>
              Transform.scale(scale: pop, child: child),
          child: AnimatedContainer(
            duration: duration,
            curve: curve,
            decoration: BoxDecoration(
              color: widget.active
                  ? AppThemeConfig.primary
                  : AppThemeConfig.surface(context),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: curve,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  // THE BUG THIS FIXES: same clipping as the Home category
                  // capsules (case_category_capsules.dart) — this chip's
                  // horizontal-scroll row sizes itself to the Text's
                  // measured width, which can land a hair narrower than
                  // what the glyphs actually paint (a joined Arabic letter
                  // pair in particular), silently clipping the tail.
                  // softWrap: false + overflow: visible always paints the
                  // label in full regardless of that measurement.
                  child: Text(
                    widget.label,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
                if (widget.icon != null) ...[
                  const SizedBox(width: 5),
                  AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: curve,
                    switchOutCurve: curve,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    // Keyed on `active` too, not just the icon identity: the
                    // colour is baked into the Icon widget itself (Icon has
                    // no separate animated-color path the way Text does via
                    // AnimatedDefaultTextStyle), so without this key
                    // AnimatedSwitcher would see "same IconData, same widget
                    // type" and skip the transition — the one thing that
                    // actually changes on toggle.
                    child: Icon(
                      widget.icon,
                      key: ValueKey(widget.active),
                      size: 15,
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A picker row inside one of the sheets: a label, an optional count, and a
/// check when it is the current choice.
///
/// Shared by the category and brand sheets, which differ only in where their
/// rows come from.
class CatalogueOptionTile extends StatelessWidget {
  const CatalogueOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// How many products sit behind this option, when the server says. Wrapped
  /// in an LTR isolate at render time — a bare numeral beside Arabic text
  /// reorders against neighbouring punctuation.
  final int? count;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          color: AppThemeConfig.text(context),
        ),
      ),
      subtitle: count == null
          ? null
          : Text(
              'catalogue_product_count'.trParams({
                'count': '\u2066$count\u2069',
              }),
              style: TextStyle(color: AppThemeConfig.mutedText(context)),
            ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppThemeConfig.primary)
          : null,
    );
  }
}

/// The shell every filter sheet uses: a grab handle, a title, and the content.
class CatalogueSheet extends StatelessWidget {
  const CatalogueSheet({
    super.key,
    required this.titleKey,
    required this.child,
  });

  final String titleKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          // Lifts the sheet clear of the keyboard, so a price field is never
          // typed into from behind it.
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
              Text(
                titleKey.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 12),
              // Bounded so a long taxonomy scrolls inside the sheet instead of
              // pushing it past the top of the screen.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four-state wrapper for a sheet whose options come from the server.
///
/// Exists so the category and brand sheets cannot disagree about what a failed
/// facet looks like — both show the cause and a retry, in place, rather than an
/// empty sheet the user reads as "there are none".
class CatalogueFacet extends StatelessWidget {
  const CatalogueFacet({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.rows,
    required this.emptyTitleKey,
    required this.builder,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final List<Map<String, dynamic>> rows;
  final String emptyTitleKey;
  final Widget Function(List<Map<String, dynamic>> rows) builder;

  @override
  Widget build(BuildContext context) {
    return AppAsync<List<Map<String, dynamic>>>(
      loading: loading,
      error: error,
      onRetry: onRetry,
      data: rows,
      isEmpty: (list) => list.isEmpty,
      skeleton: AppSkeleton.rows(count: 4, withProgress: false),
      empty: AppEmpty(
        title: emptyTitleKey,
        message: 'catalogue_facet_empty_desc',
        icon: Icons.sell_outlined,
      ),
      builder: builder,
    );
  }
}
