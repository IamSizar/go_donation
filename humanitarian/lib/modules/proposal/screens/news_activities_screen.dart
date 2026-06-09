import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
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
        final items = controller.posts;
        return RefreshIndicator(
          onRefresh: controller.fetchPosts,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
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
                MediaPostCard(item: item),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class MediaPostCard extends StatelessWidget {
  const MediaPostCard({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(item, 'title', fallback: 'Post');
    final body = localizedContentFromMap(item, 'body');
    final type = (item['post_type'] ?? 'news').toString();
    final date = (item['event_date'] ?? item['created_at'] ?? '').toString();
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PostPill(icon: Icons.local_activity_rounded, label: type),
                    if (date.trim().isNotEmpty)
                      _PostPill(icon: Icons.event_rounded, label: date),
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
              ],
            ),
          ),
        ],
      ),
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
