import 'package:flutter/material.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/proposal/widgets/feed_pagination_footer.dart';
import 'package:flutter_application_1/core/widgets/app_list_search_field.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:get/get.dart';

/// OPOS #25272 — "Community Services" used to just duplicate the City Guide
/// place directory (same table, same controller, same list, reached from a
/// second entry point). This is its replacement: a real, distinct feed of
/// community events/announcements staff post from the admin panel, reusing
/// `media_posts` the exact way the marriage module already carved out its own
/// `type=activity,news` feed — a new `post_type` value ('community') rather
/// than a new table. See `backend/migrations/121_community_media_type.sql`.
///
/// GetX tag mirrors `MarriageHubScreen._feedTag`: an untagged
/// `Get.find<MediaPostsController>()` (what the News & Activities screen
/// does) must never resolve to this narrower feed.
const _communityFeedTag = 'community-events-feed';

class CommunityEventsFeed extends StatelessWidget {
  const CommunityEventsFeed({super.key});

  @override
  Widget build(BuildContext context) {
    final feed = Get.isRegistered<MediaPostsController>(tag: _communityFeedTag)
        ? Get.find<MediaPostsController>(tag: _communityFeedTag)
        : Get.put(
            MediaPostsController(postType: 'community'),
            tag: _communityFeedTag,
          );

    return Obx(() {
      final items = feed.posts.toList(growable: false);
      return RefreshIndicator(
        onRefresh: feed.fetchPosts,
        // Same 400px-runway infinite scroll as NewsActivitiesScreen — this
        // feed has no separate archive screen to defer older posts to, so it
        // has to be able to page through all of them itself.
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >
                notification.metrics.maxScrollExtent - 400) {
              feed.loadMorePosts();
            }
            return false;
          },
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            children: [
              AppListSearchField(onChanged: feed.setSearchQuery),
              const SizedBox(height: 14),
              AppAsync<List<Map<String, dynamic>>>(
                loading: feed.isLoading.value,
                error: feed.errorMessage.value,
                onRetry: feed.fetchPosts,
                data: items,
                isEmpty: (list) => list.isEmpty,
                empty: feed.hasActiveSearch
                    ? const AppEmpty(
                        icon: Icons.search_off_rounded,
                        title: 'search_title',
                        message: 'search_no_results',
                      )
                    : const AppEmpty(
                        title: 'Community events',
                        message:
                            'No community events or announcements yet. '
                            'Check back soon.',
                      ),
                builder: (list) => Column(
                  children: [
                    for (final item in list) ...[
                      MediaPostCard(item: item, controller: feed),
                      const SizedBox(height: 14),
                    ],
                    FeedPaginationFooter(
                      isLoadingMore: feed.isLoadingMore.value,
                      hasMore: feed.hasMorePosts.value,
                      onLoadMore: feed.loadMorePosts,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
