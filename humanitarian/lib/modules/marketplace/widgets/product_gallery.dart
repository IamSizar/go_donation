// product_gallery.dart — a marketplace product's photos, cover and gallery
// together, in the detail sheet.
//
// WHAT THIS IS
// A product has one required cover (`image_path`) and, since migration 117,
// an optional `gallery` array of extra photos. [ProductPhotoStrip] draws BOTH
// as one horizontal scrollable strip — the cover first, then the gallery
// photos in the order staff arranged them — every one of them tappable to
// open full-screen with pinch-to-zoom.
//
// THE BUG THIS FIXES (redesign, not a tweak): the detail sheet used to draw
// the cover as a separate, non-tappable "hero" locked to a fixed 16:10 box
// with `BoxFit.cover`, and — only when a gallery existed — a SECOND, tiny
// 72px thumbnail strip underneath captioned "Photos". Two problems, one
// design: (1) a portrait photo (a T-shirt on a hanger, shot taller than
// wide) forced into that wide fixed box had most of its height cropped away
// — cover-fit crops to fill the box, so anything the box is narrower than
// gets cut off both edges, and for a tall photo in a WIDE box that means the
// top and bottom go, which the shirt's design was often in; the small
// square thumbnails cropped the same way, just less noticeably at 72px. (2)
// the cover wasn't part of "the photos" at all — a shopper had to already
// know the unlabelled big image up top and the labelled strip below it were
// the same kind of thing. One strip, one tap-to-zoom behaviour, and
// `BoxFit.contain` (never crops — letterboxes instead) for every photo
// fixes both at once.
//
// WHY IT LIVES HERE AND NOT IN marketplace_section.dart
// That screen is already over a thousand lines, well past the 500-line ceiling.
// Adding a widget to it would have made a known problem worse to fix a
// different one.
//
// THE EMPTY CASE IS THE COMMON CASE FOR THE GALLERY, NOT THE COVER
// Almost every product has no extra photos, only a cover. [marketplaceGalleryUrls]
// returns an empty list for absent, null, non-list and all-blank values alike,
// so a product with no gallery still gets a one-photo strip (just the cover) —
// never zero, since [ProductPhotoStrip] always includes the cover when there
// is one.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:get/get.dart';

// ─── URL resolution ─────────────────────────────────────────────────────

/// Resolves one stored image reference to a URL the app can actually load, or
/// null when there is nothing to load.
///
/// The backend stores either a relative upload path (`images/uploads/x.jpg`) or
/// an absolute URL, and both are legitimate — an admin can upload a file or
/// paste a link. A value that already carries a scheme is passed through
/// untouched; anything else is resolved against [publicBaseUrl].
///
/// Blank and null both mean "no image", which is a state the caller must draw
/// rather than an error: a product with no cover is ordinary.
///
/// Public because the gallery and the cover image must resolve paths
/// identically. When they did not, the two would eventually disagree about what
/// a relative path means and one of them would show a broken image.
String? marketplaceMediaUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;

  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;

  return Uri.parse(publicBaseUrl).resolve(path).toString();
}

/// Turns the API's `gallery` field into loadable URLs, in the order staff
/// arranged them.
///
/// Anything that is not a list — absent, null, or a response from a server
/// older than migration 117 — yields an empty list rather than throwing, so an
/// app build newer than its backend simply shows no gallery. Entries that
/// resolve to nothing are dropped instead of becoming broken-image tiles.
List<String> marketplaceGalleryUrls(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final entry in raw) {
    final url = marketplaceMediaUrl(entry);
    if (url != null) out.add(url);
  }
  return out;
}

// ─── The strip ──────────────────────────────────────────────────────────

/// A full-width, tap-to-zoom PROMOTION-BANNER-style carousel of a product's
/// photos — the cover first, then its gallery — one photo filling the width
/// at a time, swiped between rather than scrolled past as small tiles.
/// `BoxFit.contain` throughout: a photo is never cropped, only letterboxed
/// against [AppThemeConfig.softSurface] when its aspect ratio doesn't fill
/// the frame.
class ProductPhotoStrip extends StatefulWidget {
  const ProductPhotoStrip({
    super.key,
    required this.coverUrl,
    required this.galleryUrls,
  });

  /// The product's required cover photo, already resolved — or null for a
  /// product with no cover at all, in which case only the gallery (if any)
  /// shows.
  final String? coverUrl;

  /// Already-resolved absolute URLs, from [marketplaceGalleryUrls].
  final List<String> galleryUrls;

  /// Banner height. Full card width at this height reads as a promo
  /// banner rather than a thumbnail row — the whole point of this being a
  /// PageView instead of a ListView.
  static const double _bannerHeight = 240;

  @override
  State<ProductPhotoStrip> createState() => _ProductPhotoStripState();
}

class _ProductPhotoStripState extends State<ProductPhotoStrip> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = [
      if (widget.coverUrl != null) widget.coverUrl!,
      ...widget.galleryUrls,
    ];
    if (urls.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: const SizedBox(
          height: ProductPhotoStrip._bannerHeight,
          width: double.infinity,
          child: _ThumbnailFallback(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: ProductPhotoStrip._bannerHeight,
            width: double.infinity,
            child: PageView.builder(
              controller: _controller,
              // Follows the ambient text direction, same reason the old
              // ListView did — swiping "forward" is toward the end edge in
              // Arabic and Kurdish, not always to the physical right.
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => AppPressable(
                onTap: () => showProductGalleryImage(context, urls[i]),
                child: Container(
                  color: AppThemeConfig.softSurface(context),
                  child: CachedNetworkImage(
                    imageUrl: urls[i],
                    fit: BoxFit.contain,
                    fadeInDuration: const Duration(milliseconds: 180),
                    placeholder: (context, _) => const _ThumbnailLoading(),
                    errorWidget: (context, _, __) => const _ThumbnailFallback(),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The "which photo am I on" dots a promo banner is expected to
        // have. Only worth drawing once there is more than one photo to
        // flip between — a single-photo product doesn't need a solitary
        // dot telling it so.
        if (urls.length > 1) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < urls.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppThemeConfig.primary
                          : AppThemeConfig.border(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── The full-screen viewer ─────────────────────────────────────────────

/// Opens one gallery photo full-screen, zoomable, over a near-black scrim.
///
/// Deliberately NOT the app's `showAdaptiveConfirm` helper: that wraps
/// `AlertDialog.adaptive`, which is for a titled question with buttons. This is
/// a photo viewer — it has no platform-divergent furniture to get wrong, and
/// both existing galleries in this app (news posts, city places) present it the
/// same way. Dismissal is by tapping anywhere or the close button, plus the
/// platform's own back gesture, which the route handles for free.
///
/// Public so a test can drive it, and so a future caller showing a single
/// product photo does not reimplement it.
void showProductGalleryImage(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (context) => GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (context, _) => const _ThumbnailLoading(),
                errorWidget: (context, _, __) => const _ThumbnailFallback(),
              ),
            ),
          ),
          // Anchored to the end edge so it sits under the thumb in both LTR
          // and RTL rather than reaching across the screen in Arabic.
          PositionedDirectional(
            top: 40,
            end: 16,
            child: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 30,
              ),
              // The scrim is already tappable; this exists because "tap the
              // photo to close" is not discoverable, and a viewer with no
              // visible way out is a dead end.
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close'.tr,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Loading and error states ───────────────────────────────────────────

/// The bone a thumbnail occupies while its photo is fetched.
///
/// A filled block rather than a centred spinner, for the same reason the news
/// feed's is: a photo is a solid rectangle, so the honest placeholder is a
/// solid rectangle that the image fades into — not a small ring spinning in
/// empty space that the image then replaces with something a different shape.
class _ThumbnailLoading extends StatelessWidget {
  const _ThumbnailLoading();

  @override
  Widget build(BuildContext context) {
    // No radius of its own: the thumbnail's ClipRRect already rounds this, and
    // a second radius here would round twice and leave a visible notch.
    return AppSkeleton(child: Container(color: AppThemeConfig.border(context)));
  }
}

/// What a thumbnail shows when its photo will not load — a deleted upload, a
/// dead external link, or no connection.
///
/// It stays a filled tile with the marketplace's own storefront mark rather
/// than collapsing, so the strip keeps its shape and the reader can see that a
/// photo was meant to be there. Silently dropping it would make a five-photo
/// gallery quietly look like a four-photo one.
class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.pending(context).withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(
        Icons.storefront_rounded,
        color: AppThemeConfig.pending(context),
        size: 28,
      ),
    );
  }
}
