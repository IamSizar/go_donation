// feed_pagination_footer.dart — the tail of a paginated feed.
//
// WHY IT IS ITS OWN FILE: news_activities_screen.dart is already ~1450 lines,
// well past the 500-line rule, so nothing new goes into it.
//
// WHY IT IS NOT A LOAD STATE: this sits UNDER content the reader is already
// reading, so it must never replace it. The first-load skeleton
// (_PostFeedSkeleton) and this footer are two different things and both exist:
// one says "there is nothing yet", the other "there is more coming".
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Spinner while a page is being appended, an explicit "load older posts"
/// button while there is more to fetch, and nothing at all at the end of the
/// archive.
///
/// The button is not redundant with the scroll trigger. A category chip
/// filters the loaded posts client-side, so a narrow category can leave the
/// list too SHORT TO SCROLL while the archive still holds matching posts
/// further back — with only a scroll trigger that is a dead end. It doubles as
/// the guidance surface for the archive (rule 5.9): it tells the reader older
/// posts exist rather than leaving them to discover it by scrolling.
class FeedPaginationFooter extends StatelessWidget {
  const FeedPaginationFooter({
    super.key,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  /// A page append is in flight.
  final bool isLoadingMore;

  /// The server says there is another page after the ones already loaded.
  final bool hasMore;

  /// Fetches the next page. Safe to call twice — the controller guards it.
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        // .adaptive: a Cupertino spinner on iOS, Material on Android.
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (!hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: OutlinedButton.icon(
          // 48pt tall, comfortably over the 44pt minimum touch target.
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          onPressed: onLoadMore,
          // A downward chevron: older posts are further DOWN the feed, which
          // is the same direction in every locale — nothing here mirrors, so
          // no start/end handling is needed.
          icon: const Icon(Icons.expand_more_rounded),
          label: Text('feed_load_older'.tr),
        ),
      ),
    );
  }
}
