// product_gallery.dart — a marketplace product's ADDITIONAL photos.
//
// WHAT THIS IS
// A product has always had exactly one photo: `image_path`, the cover, drawn by
// the list tile and the detail sheet's hero. Migration 117 adds `gallery`, a
// text array of extra photos, so a seller can show a second angle, the back of
// a garment, or what is actually in the box. This file draws that array — a
// horizontal strip of thumbnails under the hero, each tappable to open
// full-screen with pinch-to-zoom.
//
// WHY IT LIVES HERE AND NOT IN marketplace_section.dart
// That screen is already over a thousand lines, well past the 500-line ceiling.
// Adding a widget to it would have made a known problem worse to fix a
// different one.
//
// WHY IT MIRRORS news_activities_screen.dart RATHER THAN INVENTING A SHAPE
// media_posts has carried a gallery since migration 033 and the news feed has
// drawn it the same way ever since: a strip of square thumbnails, tap to open a
// zoomable full-screen viewer, tap anywhere (or the close button) to dismiss.
// A user who has met one gallery in this app should not have to learn a second.
//
// THE EMPTY CASE IS THE COMMON CASE
// Almost every product has no extra photos. [marketplaceGalleryUrls] returns an
// empty list for absent, null, non-list and all-blank values alike, and the
// detail sheet draws nothing at all when it is empty — so a product without a
// gallery renders exactly as it did before this file existed.
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

/// A horizontal strip of a product's additional photos, captioned and tappable.
///
/// Draws nothing when [urls] is empty, so the caller does not need its own
/// guard — but callers are still expected to skip the surrounding spacing, or
/// the sheet would carry a gap where nothing is.
class ProductGallery extends StatelessWidget {
  const ProductGallery({super.key, required this.urls});

  /// Already-resolved absolute URLs, from [marketplaceGalleryUrls].
  final List<String> urls;

  /// Thumbnail edge length. Square, because product photos arrive in every
  /// aspect ratio and a fixed square with `BoxFit.cover` is the only way the
  /// strip stays a straight line instead of a ragged one.
  static const double _thumbSize = 72;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'product_photos'.tr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppThemeConfig.text(context),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _thumbSize,
          child: ListView.separated(
            // Horizontal lists follow the ambient text direction, so this
            // starts at the right in Arabic and Kurdish without a flag.
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => AppPressable(
              onTap: () => showProductGalleryImage(context, urls[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  width: _thumbSize,
                  height: _thumbSize,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (context, _) => const _ThumbnailLoading(),
                  errorWidget: (context, _, __) => const _ThumbnailFallback(),
                ),
              ),
            ),
          ),
        ),
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
