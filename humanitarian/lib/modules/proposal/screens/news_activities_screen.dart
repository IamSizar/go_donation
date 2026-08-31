import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/widgets/feed_pagination_footer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_list_search_field.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

class NewsActivitiesScreen extends StatelessWidget {
  const NewsActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MediaPostsController>()
        ? Get.find<MediaPostsController>()
        : Get.put(MediaPostsController());

    return SectionScaffold(
      title: 'News and activities',
      subtitle: 'See activities, news, articles, events, and short videos.',
      child: Obx(() {
        final items = controller.visiblePosts;
        final cats = controller.categories;
        return RefreshIndicator(
          onRefresh: () async {
            await controller.fetchPosts();
            await controller.fetchCategories();
          },
          // ARCHIVE BROWSING — WHY INFINITE SCROLL AND NOT A SEPARATE ARCHIVE
          // SCREEN. The feed used to end at the newest 50 posts, so older work
          // was reachable only by searching for a word inside it. Both a
          // year/month archive view and endless scrolling fix that; scrolling
          // wins here because the reader never has to leave the feed, learn a
          // second navigation, or know WHEN something happened to find it —
          // and because the app already does exactly this on
          // marriage_posts_screen.dart, so this is one pattern rather than a
          // second one. A grouped archive would also have to re-implement the
          // search box and the category chips to stay useful.
          //
          // NotificationListener rather than a ScrollController: this screen is
          // stateless and the controller lives in GetX, so there is nothing
          // here that should own a disposable listener.
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // 400px of runway, so the next page is usually already in when
              // the reader arrives at the tail.
              if (notification.metrics.pixels >
                  notification.metrics.maxScrollExtent - 400) {
                controller.loadMorePosts();
              }
              // false: this is an observer, not a consumer — RefreshIndicator
              // and the scrollbar must keep seeing these notifications.
              return false;
            },
            child: ListView(
              // Scrolling the feed puts the keyboard away, so it never covers
              // the posts the search just found.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                // J8 — in-list search. Server-side (`?q=`): it searches every
                // published post rather than the pages loaded so far, and the
                // server also matches the post BODY, so a word from inside a
                // write-up finds the activity. A filter over the loaded posts
                // could do neither. Changing it restarts paging from the
                // newest post (see MediaPostsController.fetchPosts).
                AppListSearchField(onChanged: controller.setSearchQuery),
                const SizedBox(height: 14),
                // #22 — "Our Work" category filter chips. Kept OUTSIDE AppAsync:
                // the empty state is usually "nothing in THIS category", so
                // hiding the chips with the results would leave no way to undo
                // the selection that emptied the screen.
                if (cats.isNotEmpty) ...[
                  _CategoryChips(controller: controller),
                  const SizedBox(height: 14),
                ],
                // Three stacked `if` blocks replaced by one state. Previously a
                // failed load drew the error tile AND the post list beneath it,
                // and the error was a SectionTile whose retry was an unlabelled
                // onTap on a card shaped like every nav row in the app.
                AppAsync<List<Map<String, dynamic>>>(
                  loading: controller.isLoading.value,
                  error: controller.errorMessage.value,
                  onRetry: controller.fetchPosts,
                  data: items,
                  isEmpty: (list) => list.isEmpty,
                  // The default AppSkeleton.rows() was wrong for this screen: a
                  // MediaPostCard leads with a 16:9 image, so title/meta/progress
                  // text bones would have jumped into a big picture rather than
                  // filled into one.
                  skeleton: const _PostFeedSkeleton(),
                  // J8 — a search that matched nothing is not an empty feed.
                  // "No published posts are available yet" would be a false
                  // claim about the organization's work, made because the user
                  // typed a word that happens not to appear in it.
                  empty: controller.hasActiveSearch
                      ? const AppEmpty(
                          icon: Icons.search_off_rounded,
                          title: 'search_title',
                          message: 'search_no_results',
                        )
                      : const AppEmpty(
                          title: 'News and activities',
                          message: 'No published posts are available yet.',
                        ),
                  builder: (list) => Column(
                    children: [
                      for (final item in list) ...[
                        MediaPostCard(
                          item: item,
                          categoryLabel: controller.categoryLabelForSlug(
                            (item['category_slug'] ?? '').toString(),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // The tail of the archive walk. Inside `builder`, so it
                      // shows only under real content — never beside the
                      // skeleton, the error state or the empty state.
                      FeedPaginationFooter(
                        isLoadingMore: controller.isLoadingMore.value,
                        hasMore: controller.hasMorePosts.value,
                        onLoadMore: controller.loadMorePosts,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// First-load placeholder for the post feed, shaped like the [MediaPostCard]s
/// it is replaced by rather than like generic text rows.
///
/// It is built inside a real [GlassPanel] with the same `EdgeInsets.zero`
/// padding the card uses, so the panel radius, border, blur and shadow are the
/// card's own geometry rather than a second guess at it — only the contents are
/// bones. Two cards is enough to read as a feed without filling the screen with
/// grey before there is anything to show.
class _PostFeedSkeleton extends StatelessWidget {
  const _PostFeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: Column(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            const _PostCardBones(),
          ],
        ],
      ),
    );
  }
}

/// The bones of a single post card: hero, pill row, headline, body, action.
class _PostCardBones extends StatelessWidget {
  const _PostCardBones();

  @override
  Widget build(BuildContext context) {
    // One neutral bone colour from the theme so it holds in both modes.
    final bone = AppThemeConfig.border(context);
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The hero. A solid block, like _MediaLoading and for the same
          // reason: an image's honest placeholder is a block of pixels, not
          // lines of text. No radius of its own — GlassPanel already clips the
          // top corners, and rounding twice would notch them.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: bone),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The Wrap of _PostPills: small rounded tablets of varying
                // width, drawn as containers rather than AppSkeleton.bone
                // because bone() rounds to height/2 and a 30px tablet would
                // come out as a stadium pill instead of a chip.
                Row(
                  children: [
                    for (final width in const <double>[86, 64, 104]) ...[
                      Container(
                        width: width,
                        height: 30,
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        decoration: BoxDecoration(
                          color: bone,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // The headline — fontSize 20, so a taller, wider bar than the
                // body lines beneath it.
                AppSkeleton.bone(height: 14, widthFactor: 0.82),
                const SizedBox(height: 6),
                // Body copy, ragged so it reads as prose rather than a slab.
                AppSkeleton.bone(height: 9, widthFactor: 0.95),
                AppSkeleton.bone(height: 9, widthFactor: 0.88),
                AppSkeleton.bone(height: 9, widthFactor: 0.55),
                const SizedBox(height: 14),
                // The full-width "Watch video" / "Open media" button. Height
                // and radius come from the theme's ElevatedButton
                // (minimumSize 48, AppRadius.sm), not from a guess.
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: bone,
                    borderRadius: AppRadius.smAll,
                  ),
                ),
                const SizedBox(height: 10),
                // The rule above the engagement bar is a real Divider in the
                // card, so it is a real Divider here too — it is already a
                // hairline and needs no bone of its own.
                const Divider(height: 1),
                const SizedBox(height: 4),
                // Like / Comment / Share / Save: four evenly-weighted actions
                // across the full width. Included so the card does not GROW
                // when the real bar arrives underneath the loaded content.
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Container(
                          height: 20,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: bone,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// #22 — horizontal "Our Work" category filter chips.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.controller});

  final MediaPostsController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedCategory.value;
    final chips = <Widget>[
      _FilterChip(
        label: 'All'.tr,
        active: selected == null || selected.isEmpty,
        onTap: () => controller.selectCategory(null),
      ),
    ];
    for (final cat in controller.categories) {
      final slug = (cat['slug'] ?? '').toString();
      if (slug.isEmpty) continue;
      chips.add(
        _FilterChip(
          label: controller.localizedCategoryName(cat),
          active: selected == slug,
          onTap: () => controller.selectCategory(slug),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppThemeConfig.primary : AppThemeConfig.surface(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppThemeConfig.text(context),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MediaPostCard extends StatelessWidget {
  const MediaPostCard({
    super.key,
    required this.item,
    this.categoryLabel = '',
    this.controller,
  });

  final Map<String, dynamic> item;
  final String categoryLabel;

  /// The controller whose `posts` list contains [item].
  ///
  /// MUST be passed by any screen that registers its own MediaPostsController
  /// under a GetX tag (the Events hub does). The engagement bar mutates the
  /// post map and then calls `posts.refresh()` to redraw; refreshing a
  /// DIFFERENT controller than the one the screen is observing updates nothing
  /// on screen, so like/save appear completely dead even though the request
  /// went out. Null falls back to the untagged instance, which is what the
  /// News & Activities and Our Work screens share.
  final MediaPostsController? controller;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(item, 'title', fallback: 'Post');
    final body = localizedContentFromMap(item, 'body');
    // localizedTag: post_type is a backend enum (activity/event/news/
    // article) and was printed raw, so the Arabic UI showed the English
    // word on every card.
    final type = localizedTag(item['post_type'] ?? 'news');
    final date = (item['event_date'] ?? item['created_at'] ?? '').toString();
    final location = localizedContentFromMap(item, 'location'); // #23
    // "Post Information" — the Activity Code identifying the post and the
    // category it belongs to (HUM-000123). It was being generated and served
    // by the API but never shown, so nobody could quote it.
    final activityCode = (item['activity_code'] ?? '').toString().trim();
    final gallery = _galleryUrls(item['gallery']); // #23
    final mediaUrl = _mediaUrl(item['media_url']);
    final linkUrl = _mediaUrl(item['link_url']);
    final actionUrl = linkUrl ?? mediaUrl;
    final isDirectVideo = _isVideoUrl(actionUrl);
    final isVideo =
        _isVideoUrl(mediaUrl) || isDirectVideo || type.toLowerCase() == 'video';

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MediaHero(mediaUrl: mediaUrl, isVideo: isVideo),
          if (gallery.isNotEmpty) _MediaGallery(urls: gallery), // #23
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (categoryLabel.trim().isNotEmpty)
                      _PostPill(
                        icon: Icons.folder_special_rounded,
                        label: categoryLabel,
                      ),
                    _PostPill(icon: Icons.local_activity_rounded, label: type),
                    if (date.trim().isNotEmpty)
                      _PostPill(
                        icon: Icons.event_rounded,
                        label: localizedDate(date),
                      ),
                    if (location.trim().isNotEmpty)
                      _PostPill(icon: Icons.place_rounded, label: location),
                    if (activityCode.isNotEmpty)
                      _PostPill(icon: Icons.tag_rounded, label: activityCode),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      height: 1.5,
                    ),
                  ),
                ],
                if (actionUrl != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (isDirectVideo) {
                          Get.to(
                            () => MediaVideoScreen(
                              title: title,
                              videoUrl: actionUrl,
                            ),
                          );
                          return;
                        }
                        _openMediaLink(actionUrl);
                      },
                      icon: Icon(
                        isDirectVideo
                            ? Icons.play_arrow_rounded
                            : Icons.open_in_new_rounded,
                      ),
                      label: Text(isVideo ? 'Watch video'.tr : 'Open media'.tr),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 4),
                _EngagementBar(item: item, controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// #24 — like / comment / share bar at the bottom of each post card.
class _EngagementBar extends StatelessWidget {
  const _EngagementBar({required this.item, this.controller});

  final Map<String, dynamic> item;

  /// See [MediaPostCard.controller] — null means the shared untagged instance.
  final MediaPostsController? controller;

  @override
  Widget build(BuildContext context) {
    // Named apart from the `controller` field on purpose: a local of the same
    // name does not shadow the field inside the onTap closures below, so the
    // nullable field would be the one they captured.
    final MediaPostsController feed =
        controller ??
        (Get.isRegistered<MediaPostsController>()
            ? Get.find<MediaPostsController>()
            : Get.put(MediaPostsController()));
    final liked = item['liked_by_me'] == true;
    final likeCount = (item['like_count'] as num?)?.toInt() ?? 0;
    final commentCount = (item['comment_count'] as num?)?.toInt() ?? 0;
    final shareCount = (item['share_count'] as num?)?.toInt() ?? 0;
    final saved = item['saved_by_me'] == true;
    // Four evenly-weighted actions across the full width — clear, balanced,
    // and each with a comfortable tap target. Save carries no count: it is
    // private to the user, unlike likes/comments/shares.
    return Row(
      children: [
        Expanded(
          child: _EngageButton(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: liked ? Colors.red : null,
            label: likeCount > 0 ? '$likeCount' : 'Like'.tr,
            // #44 — guests are prompted to sign in before acting.
            onTap: () async {
              if (await requireSignIn(context)) feed.toggleLike(item);
            },
          ),
        ),
        Expanded(
          child: _EngageButton(
            icon: Icons.mode_comment_outlined,
            label: commentCount > 0 ? '$commentCount' : 'Comment'.tr,
            onTap: () => _openComments(context, item, feed),
          ),
        ),
        Expanded(
          child: _EngageButton(
            icon: Icons.share_outlined,
            label: shareCount > 0 ? '$shareCount' : 'Share'.tr,
            onTap: () => _sharePost(context, item, feed),
          ),
        ),
        Expanded(
          child: _EngageButton(
            icon: saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: saved ? AppThemeConfig.primary : null,
            label: 'Save'.tr,
            onTap: () async {
              if (await requireSignIn(context)) feed.toggleSaved(item);
            },
          ),
        ),
      ],
    );
  }
}

class _EngageButton extends StatelessWidget {
  const _EngageButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppThemeConfig.mutedText(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tint,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _sharePost(
  BuildContext context,
  Map<String, dynamic> item,
  MediaPostsController controller,
) async {
  final id = int.tryParse('${item['id']}') ?? 0;
  final title = localizedContentFromMap(item, 'title', fallback: 'Post');
  final body = localizedContentFromMap(item, 'body');
  final parts = <String>[title];
  if (body.trim().isNotEmpty) parts.add(body);
  // #49 — include the app link so recipients can find the app.
  //
  // sharePositionOrigin is required, not cosmetic: without it iOS throws
  // "sharePositionOrigin: argument must be set" and this function never
  // reaches the shareMediaPost call below, so the share count went unrecorded
  // as well as the sheet never opening. See [shareAnchor].
  await Share.share(
    withAppLink(parts.join('\n\n')),
    sharePositionOrigin: shareAnchor(context),
  );
  if (id > 0) {
    try {
      await const ModuleApi().shareMediaPost(id);
      controller.bumpShareCount(id);
    } catch (_) {
      // Deliberately silent: the share itself already happened in the system
      // sheet above. This call only records the share count, so a failure has
      // nothing the user can act on and no surface to report it in.
    }
  }
}

void _openComments(
  BuildContext context,
  Map<String, dynamic> item,
  MediaPostsController controller,
) {
  final id = int.tryParse('${item['id']}') ?? 0;
  if (id == 0) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Transparent here so the sheet's own opaque Container (below) is the ONLY
    // background — otherwise the DraggableScrollableSheet content had no solid
    // surface of its own and showed through as transparent.
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentsSheet(postId: id, controller: controller),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId, required this.controller});

  final int postId;
  final MediaPostsController controller;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _input = TextEditingController();
  final _comments = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _sending = false;
  // Set when the comment FETCH fails. Without it the sheet rendered "No
  // comments yet." after a failed load — telling the user the post had no
  // discussion when the request had simply errored, with no way to retry.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Clear any previous failure so a retry starts from the loading state
    // rather than leaving the error banner up while the refetch runs.
    if (mounted && _error != null) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final rows = await const ModuleApi().mediaComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (e) {
      // Was `catch (_) { _loading = false; }` — the failure was swallowed and
      // the sheet fell through to its "No comments yet." copy.
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the comments.';
        _loading = false;
      });
      debugPrint('mediaComments(${widget.postId}) failed: $e');
    }
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await const ModuleApi().postMediaComment(widget.postId, text);
      _input.clear();
      if (res['held'] == true) {
        Get.snackbar('Thanks'.tr, 'Your comment is awaiting review.'.tr);
      } else {
        final cmt = res['comment'];
        if (cmt is Map) {
          setState(() => _comments.insert(0, Map<String, dynamic>.from(cmt)));
        }
        widget.controller.bumpCommentCount(widget.postId);
      }
    } catch (_) {
      // Not swallowed: a failed SEND is reported here as a snackbar. It stays
      // a snackbar rather than an error state because the comment list behind
      // it loaded fine and must keep rendering.
      Get.snackbar('Error'.tr, 'Could not post your comment.'.tr);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          // Solid, self-contained surface with a rounded top. clipBehavior keeps
          // the list + rounded corners tidy so nothing bleeds past the edge.
          return Container(
            decoration: BoxDecoration(
              // elevatedSurface is fully OPAQUE (solid white in light mode,
              // solid dark in dark mode). surface() is translucent by design
              // (glassmorphism), which is what made this sheet see-through.
              color: AppThemeConfig.elevatedSurface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Grab handle.
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.mutedText(
                      context,
                    ).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Header: title + live count pill + close.
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 8, 12),
                  child: Row(
                    children: [
                      Text(
                        'Comments'.tr,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      if (_comments.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppThemeConfig.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_comments.length}',
                            style: TextStyle(
                              color: AppThemeConfig.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppThemeConfig.border(context)),
                Expanded(
                  // Error is checked BEFORE empty: a failed fetch leaves
                  // _comments empty, so without this the empty state would win
                  // and claim the post has no comments.
                  child: _error != null
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          child: AppErrorState(
                            message: _error!,
                            onRetry: _load,
                          ),
                        )
                      : _loading
                      // A spinner here made the sheet jump: it sat centred in
                      // an empty pane and the comment list then appeared from
                      // the top. The skeleton stands in the list's own place
                      // so the comments fill in rather than pop in.
                      ? const _CommentsSkeleton()
                      : _comments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mode_comment_outlined,
                                size: 40,
                                color: AppThemeConfig.mutedText(
                                  context,
                                ).withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No comments yet.'.tr,
                                style: TextStyle(
                                  color: AppThemeConfig.mutedText(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          itemCount: _comments.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 20),
                          itemBuilder: (_, i) =>
                              _CommentTile(comment: _comments[i]),
                        ),
                ),
                Divider(height: 1, color: AppThemeConfig.border(context)),
                // Composer: filled pill field + circular send button.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submit(),
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Write a comment…'.tr,
                              filled: true,
                              fillColor: AppThemeConfig.softSurface(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(
                                  color: AppThemeConfig.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: _sending
                              ? AppThemeConfig.primary.withValues(alpha: 0.5)
                              : AppThemeConfig.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _sending ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// First-load placeholder for the comments sheet, shaped like the
/// [_CommentTile] rows it is replaced by: a round avatar with a name bar and a
/// short date beside it, then two body lines underneath.
///
/// [AppSkeleton.rows] would be the wrong shape here — it draws a title, a meta
/// line and a progress rule, and has no avatar, so the round mark would appear
/// out of nowhere when the comments landed. Same padding and separator spacing
/// as the real ListView.separated, so nothing shifts on arrival.
class _CommentsSkeleton extends StatelessWidget {
  const _CommentsSkeleton();

  // Body lines are ragged rather than uniform so the block reads as text.
  static const _bodyWidths = <double>[0.92, 0.64, 0.86, 0.5];

  @override
  Widget build(BuildContext context) {
    // One neutral bone colour taken from the theme, so it holds up in both
    // light and dark mode.
    final bone = AppThemeConfig.border(context);
    return AppSkeleton(
      child: ListView.separated(
        // Never scrolled: the sheet's real list owns the scroll controller, and
        // handing a placeholder its own scroll position would fight it.
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        itemCount: 4,
        separatorBuilder: (_, __) => const Divider(height: 20),
        itemBuilder: (_, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Matches the CircleAvatar(radius: 14) in _CommentTile.
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: bone,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                // The author name — a short bar, not a full-width one.
                Expanded(
                  child: AppSkeleton.bone(
                    height: 11,
                    widthFactor: i.isEven ? 0.42 : 0.34,
                    margin: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
                // The trailing yyyy-mm-dd stamp.
                Container(
                  width: 54,
                  height: 9,
                  decoration: BoxDecoration(
                    color: bone,
                    borderRadius: BorderRadius.circular(4.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppSkeleton.bone(height: 9, widthFactor: _bodyWidths[i % 4]),
            AppSkeleton.bone(
              height: 9,
              widthFactor: _bodyWidths[(i + 1) % 4],
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final name = (comment['user_name'] ?? 'User').toString();
    final body = (comment['body'] ?? '').toString();
    final date = (comment['created_at'] ?? '').toString();
    final initial = name.trim().isNotEmpty
        ? name.trim().substring(0, 1).toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppThemeConfig.primary.withValues(alpha: 0.15),
              child: Text(
                initial,
                style: TextStyle(
                  color: AppThemeConfig.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ),
            if (date.trim().isNotEmpty)
              Text(
                localizedDate(date),
                style: TextStyle(
                  fontSize: 11,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: TextStyle(color: AppThemeConfig.text(context), height: 1.4),
        ),
      ],
    );
  }
}

class _MediaHero extends StatelessWidget {
  const _MediaHero({required this.mediaUrl, required this.isVideo});

  final String? mediaUrl;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (mediaUrl != null && !isVideo)
            CachedNetworkImage(
              imageUrl: mediaUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => const _MediaLoading(),
              errorWidget: (context, url, error) => const _MediaFallback(),
            )
          else
            const _MediaFallback(),
          if (isVideo)
            Container(
              color: Colors.black.withValues(alpha: 0.32),
              alignment: Alignment.center,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 38,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// #23 — a horizontal strip of the post's additional gallery images. Tapping a
// thumbnail opens it full-screen (pinch-to-zoom).
class _MediaGallery extends StatelessWidget {
  const _MediaGallery({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final url = urls[i];
            return AppPressable(
              onTap: () => _openGalleryImage(context, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 78,
                  height: 78,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => const _MediaLoading(),
                  errorWidget: (context, _, __) => const _MediaFallback(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

void _openGalleryImage(BuildContext context, String url) {
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
                errorWidget: (context, _, __) => const _MediaFallback(),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Placeholder while a post image is fetched — used for both the 16:9 hero and
/// the 78px gallery thumbnails.
///
/// It fills its slot rather than centring a spinner in it. An image is a solid
/// block of pixels, so the honest placeholder is a solid block: the photo fades
/// into the same rectangle the bone occupied, instead of replacing a small
/// spinning ring floating in the middle of an empty panel. Text bones would be
/// wrong for the same reason the City Guide needed a map-shaped one.
class _MediaLoading extends StatelessWidget {
  const _MediaLoading();

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      // No radius of its own: the hero is already clipped by the GlassPanel and
      // the thumbnails by their own ClipRRect, so a corner here would round
      // twice and leave a visible notch.
      child: Container(color: AppThemeConfig.border(context)),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(
        Icons.article_rounded,
        color: AppThemeConfig.primary,
        size: 46,
      ),
    );
  }
}

class _PostPill extends StatelessWidget {
  const _PostPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppThemeConfig.primary),
          const SizedBox(width: 7),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class MediaVideoScreen extends StatefulWidget {
  const MediaVideoScreen({
    super.key,
    required this.title,
    required this.videoUrl,
  });

  final String title;
  final String videoUrl;

  @override
  State<MediaVideoScreen> createState() => _MediaVideoScreenState();
}

class _MediaVideoScreenState extends State<MediaVideoScreen> {
  // Not `late final`: a retry has to throw the failed controller away and
  // build a fresh one, because a VideoPlayerController that failed to
  // initialize cannot be re-initialized.
  late VideoPlayerController _controller;
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Create the player and begin loading. Also the retry path.
  void _start() {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _ready = _controller.initialize().then((_) {
      _controller
        ..setLooping(true)
        ..play();
      if (mounted) setState(() {});
    });
  }

  /// Discard the dead controller and start over, so the FutureBuilder is
  /// handed a genuinely new future rather than the already-failed one.
  void _retry() {
    final dead = _controller;
    setState(_start);
    dead.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: widget.title,
      subtitle: 'Watch video',
      child: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          // snapshot.hasError was never read. A video that failed to
          // initialize (dead link, unsupported codec, no connection) still
          // fell through to the player, which rendered a blank box with a
          // Pause button and no explanation or way to try again.
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                AppErrorState(
                  message: 'Could not play this video.',
                  onRetry: _retry,
                ),
              ],
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            // Shaped like the player that replaces it — a 16:9 rounded frame
            // with the play/pause button below — rather than a spinner floating
            // in the middle of the page. The real aspect ratio isn't known
            // until the video initializes, so this uses the same 16/9 the
            // player itself falls back to; content fills the frame in place.
            return const _VideoSkeleton();
          }
          final aspectRatio = _controller.value.aspectRatio <= 0
              ? 16 / 9
              : _controller.value.aspectRatio;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                },
                icon: Icon(
                  _controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  _controller.value.isPlaying ? 'Pause'.tr : 'Play'.tr,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// First-load placeholder for [MediaVideoScreen]: the video frame and the
/// control beneath it, in the same list padding the loaded screen uses.
class _VideoSkeleton extends StatelessWidget {
  const _VideoSkeleton();

  @override
  Widget build(BuildContext context) {
    final bone = AppThemeConfig.border(context);
    return AppSkeleton(
      child: ListView(
        // Static placeholder — nothing to scroll to yet.
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          // The video frame, matching the ClipRRect(8) + AspectRatio below it.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: bone,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // The Play/Pause button. Height and radius are taken from the theme's
          // ElevatedButton (minimumSize 48, AppRadius.sm) rather than guessed,
          // so the real control lands on exactly this footprint.
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: bone,
              borderRadius: AppRadius.smAll,
            ),
          ),
        ],
      ),
    );
  }
}

String? _mediaUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  if (RegExp(
    r'^(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-zA-Z]{2,}\b',
  ).hasMatch(path)) {
    return 'https://$path';
  }
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}

// #23 — resolve a post's gallery (a JSON array of paths/URLs) into displayable
// image URLs, dropping anything blank/unresolvable.
List<String> _galleryUrls(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final entry in raw) {
    final url = _mediaUrl(entry);
    if (url != null) out.add(url);
  }
  return out;
}

bool _isVideoUrl(String? url) {
  if (url == null) return false;
  return RegExp(
    r'\.(mp4|mov|m4v|webm)(\?.*)?$',
    caseSensitive: false,
  ).hasMatch(url);
}

Future<void> _openMediaLink(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) {
    Get.snackbar('Error'.tr, 'Invalid media link.'.tr);
    return;
  }
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) {
    Get.snackbar('Error'.tr, 'Could not open media link.'.tr);
  }
}
