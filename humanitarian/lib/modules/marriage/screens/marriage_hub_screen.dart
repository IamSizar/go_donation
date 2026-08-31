import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import 'marriage_event_group_screen.dart';
import '../widgets/event_hub_cards.dart';

/// Note #41 — the unified "Marriage" bottom-nav tab. Everyone (including a
/// guest, per Note #40's browsing scope) can browse profiles and read posts.
/// Note #43 — submitting/viewing "my profile" and Subscription used to be
/// restricted to the Beneficiary role only ("This action is not available
/// for your role" on submit); the client asked for every account category to
/// be able to use the Marriage section with no role-based restriction, so
/// these are now gated only on not-guest (guests still can't submit — POST
/// /marriage requires RequireNotGuest() same as Chats in the section grid).
///
/// CHUNK 5 REDESIGN — what used to be here
/// This screen was three flat, full-width tile lists: "Event services" (6
/// tiles), "Events section" (up to 6, guest-gated), and "About & contact" (2
/// tiles). The owner asked for the two service groups to collapse into one
/// top-level grid of two cards — tapping either opens that group as its own
/// grid, in marriage_event_group_screen.dart — and for "About & contact" to
/// be removed from this hub entirely.
///
/// "About My Engagement" (slug `marriage-about`) and "Contact My Engagement"
/// (slug `marriage-contact`) were NOT deleted — only their doors here were.
/// They are now unreachable from the Events tab; nothing else in the app
/// links to those two `ContentPageScreen` slugs either; see the report for
/// this chunk. "Message the staff team" is a different destination (the
/// support chat) and stays in the Events-section grid — do not confuse the
/// two when re-adding an about/contact entry in the future.
///
/// THE FEED BELOW THE GRID
/// The owner asked for the activity posts and news published from the admin
/// panel to appear on this screen, under the two cards. Both are `media_posts`
/// rows, so the feed is `GET /api/media?type=activity,news` — the server-side
/// filter, not a client-side one: the endpoint caps its result at 50 rows, so
/// fetching the general feed and dropping the other types here would hide
/// older activity posts behind newer articles and videos that never render.
class MarriageHubScreen extends StatelessWidget {
  const MarriageHubScreen({super.key});

  /// GetX tag for this screen's [MediaPostsController].
  ///
  /// The instance is type-filtered, and `Get.find<MediaPostsController>()` with
  /// no tag — what NewsActivitiesScreen does — must never resolve to it, or the
  /// full News & Activities feed would silently narrow to these two types.
  static const _feedTag = 'events-hub-feed';

  /// The post types the admin panel publishes that belong on the Events hub.
  /// Sent verbatim as `?type=`, which accepts a comma-separated list.
  static const _feedTypes = 'activity,news';

  @override
  Widget build(BuildContext context) {
    final feed = Get.isRegistered<MediaPostsController>(tag: _feedTag)
        ? Get.find<MediaPostsController>(tag: _feedTag)
        : Get.put(
            MediaPostsController(postType: _feedTypes),
            tag: _feedTag,
          );

    // Title moved to the persistent top bar (dashboard_screen.dart).
    return SectionScaffold(
      title: '',
      subtitle: '',
      child: RefreshIndicator(
        onRefresh: feed.fetchPosts,
        child: ListView(
          // Scaffold already reserves space above the bottom nav bar — this
          // only needs a small resting margin, not extra clearance for it.
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            CardGrid(
              children: [
                StaggeredEntrance(
                  index: 0,
                  child: EventHubCard(
                    heroTag: 'events-hub-services',
                    icon: Icons.celebration_outlined,
                    color: AppThemeConfig.accent(context),
                    title: 'Event services',
                    subtitle:
                        'Book halls, photographers, and everything your event needs',
                    onTap: () => Get.to(() => const EventServicesGroupScreen()),
                  ),
                ),
                StaggeredEntrance(
                  index: 1,
                  child: EventHubCard(
                    heroTag: 'events-hub-section',
                    icon: Icons.groups_outlined,
                    color: AppThemeConfig.accent(context),
                    title: 'Events section',
                    subtitle:
                        'Profiles, posts, and support for the events community',
                    onTap: () => Get.to(() => const EventsSectionGroupScreen()),
                  ),
                ),
              ],
            ),
            // "See all" opens the full News & Activities screen — this feed is
            // a preview capped by the endpoint, so a post that falls off the
            // end still has a reachable home.
            AppSectionHeader(
              label: 'News and activities',
              action: 'See all',
              onActionTap: () => Get.to(() => const NewsActivitiesScreen()),
            ),
            Obx(
              () => AppAsync<List<Map<String, dynamic>>>(
                loading: feed.isLoading.value,
                error: feed.errorMessage.value,
                onRetry: feed.fetchPosts,
                data: feed.posts.toList(growable: false),
                isEmpty: (list) => list.isEmpty,
                empty: const AppEmpty(
                  title: 'News and activities',
                  message: 'No published posts are available yet.',
                ),
                builder: (list) => Column(
                  children: [
                    for (final item in list) ...[
                      const SizedBox(height: 14),
                      MediaPostCard(
                        item: item,
                        categoryLabel: feed.categoryLabelForSlug(
                          (item['category_slug'] ?? '').toString(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
