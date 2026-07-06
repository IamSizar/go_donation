import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              // #22 — "Our Work" category filter chips.
              if (cats.isNotEmpty) ...[
                _CategoryChips(controller: controller),
                const SizedBox(height: 14),
              ],
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.article_rounded,
                  title: 'News and activities',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.orange,
                  onTap: controller.fetchPosts,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                const SectionTile(
                  icon: Icons.article_rounded,
                  title: 'News and activities',
                  subtitle: 'No published posts are available yet.',
                  color: Colors.orange,
                ),
              for (final item in items) ...[
                MediaPostCard(
                  item: item,
                  categoryLabel: controller.categoryLabelForSlug(
                    (item['category_slug'] ?? '').toString(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      }),
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
      color: active
          ? AppThemeConfig.primary
          : AppThemeConfig.surface(context),
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
  const MediaPostCard({super.key, required this.item, this.categoryLabel = ''});

  final Map<String, dynamic> item;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(item, 'title', fallback: 'Post');
    final body = localizedContentFromMap(item, 'body');
    final type = (item['post_type'] ?? 'news').toString();
    final date = (item['event_date'] ?? item['created_at'] ?? '').toString();
    final location = localizedContentFromMap(item, 'location'); // #23
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
                      _PostPill(icon: Icons.event_rounded, label: date),
                    if (location.trim().isNotEmpty)
                      _PostPill(icon: Icons.place_rounded, label: location),
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
                _EngagementBar(item: item),
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
  const _EngagementBar({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MediaPostsController>()
        ? Get.find<MediaPostsController>()
        : Get.put(MediaPostsController());
    final liked = item['liked_by_me'] == true;
    final likeCount = (item['like_count'] as num?)?.toInt() ?? 0;
    final commentCount = (item['comment_count'] as num?)?.toInt() ?? 0;
    final shareCount = (item['share_count'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        _EngageButton(
          icon: liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: liked ? Colors.red : null,
          label: likeCount > 0 ? '$likeCount' : 'Like'.tr,
          onTap: () => controller.toggleLike(item),
        ),
        _EngageButton(
          icon: Icons.mode_comment_outlined,
          label: commentCount > 0 ? '$commentCount' : 'Comment'.tr,
          onTap: () => _openComments(context, item, controller),
        ),
        const Spacer(),
        _EngageButton(
          icon: Icons.share_outlined,
          label: shareCount > 0 ? '$shareCount' : 'Share'.tr,
          onTap: () => _sharePost(item, controller),
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
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: tint,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _sharePost(
  Map<String, dynamic> item,
  MediaPostsController controller,
) async {
  final id = int.tryParse('${item['id']}') ?? 0;
  final title = localizedContentFromMap(item, 'title', fallback: 'Post');
  final body = localizedContentFromMap(item, 'body');
  final parts = <String>[title];
  if (body.trim().isNotEmpty) parts.add(body);
  await Share.share(parts.join('\n\n'));
  if (id > 0) {
    try {
      await const ModuleApi().shareMediaPost(id);
      controller.bumpShareCount(id);
    } catch (_) {}
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
    backgroundColor: AppThemeConfig.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
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
    try {
      final rows = await const ModuleApi().mediaComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
      Get.snackbar('Error'.tr, 'Could not post your comment.'.tr);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppThemeConfig.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'Comments'.tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                    ? Center(
                        child: Text(
                          'No comments yet.'.tr,
                          style: TextStyle(
                            color: AppThemeConfig.mutedText(context),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (_, i) =>
                            _CommentTile(comment: _comments[i]),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: 'Write a comment…'.tr,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        color: AppThemeConfig.primary,
                        onPressed: _sending ? null : _submit,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
            if (date.length >= 10)
              Text(
                date.substring(0, 10),
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
          style: TextStyle(
            color: AppThemeConfig.text(context),
            height: 1.4,
          ),
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
            return GestureDetector(
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
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.surface(context),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
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
  late final VideoPlayerController _controller;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _ready = _controller.initialize().then((_) {
      _controller
        ..setLooping(true)
        ..play();
      if (mounted) setState(() {});
    });
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
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
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
