import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/media_posts_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

/// Portfolio-style presentation of the organization's work and achievements —
/// a two-column card grid (image, title, category) rather than the social
/// feed layout of News & Activities, reusing the same posts/categories so no
/// new backend work was needed. Tapping a card opens the full post via the
/// existing MediaPostCard (from news_activities_screen.dart).
class OurWorkScreen extends StatelessWidget {
  const OurWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MediaPostsController>()
        ? Get.find<MediaPostsController>()
        : Get.put(MediaPostsController());

    return SectionScaffold(
      title: 'Our Work',
      subtitle: 'A look at our projects, achievements, and impact.',
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
              // The category chips stay OUTSIDE AppAsync: the empty state is
              // usually "nothing in THIS category", so hiding the filter with
              // the results would leave no way out of it.
              if (cats.isNotEmpty) ...[
                _CategoryChips(controller: controller),
                const SizedBox(height: 14),
              ],
              // Previously three stacked `if` blocks plus an unconditional
              // GridView, so a failed load rendered an error tile AND an
              // empty grid beneath it, and the error's retry was an
              // unlabelled onTap on a card shaped like a nav row.
              AppAsync<List<Map<String, dynamic>>>(
                loading: controller.isLoading.value,
                error: controller.errorMessage.value,
                onRetry: controller.fetchPosts,
                data: items,
                isEmpty: (list) => list.isEmpty,
                empty: const AppEmpty(
                  title: 'Our Work',
                  message: 'No published work is available yet.',
                ),
                builder: (list) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, i) {
                    final item = list[i];
                    final categoryLabel = controller.categoryLabelForSlug(
                      (item['category_slug'] ?? '').toString(),
                    );
                    return _PortfolioCard(
                      item: item,
                      categoryLabel: categoryLabel,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.controller});

  final MediaPostsController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedCategory.value;

    // "Tenth: Details of the Our Work Section" — the activity list is split
    // into Humanitarian Assistance and Other Programs. Categories carry a
    // group_key; anything without one (or with an unrecognised value) falls
    // into Other Programs so a newly-added category is never hidden.
    List<Map<String, dynamic>> inGroup(String key) => controller.categories
        .where((c) {
          final slug = (c['slug'] ?? '').toString();
          if (slug.isEmpty) return false;
          final g = (c['group_key'] ?? '').toString();
          return key == 'humanitarian'
              ? g == 'humanitarian'
              : g != 'humanitarian';
        })
        .cast<Map<String, dynamic>>()
        .toList();

    Widget row(List<Widget> chips) => SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );

    Widget groupLabel(String key) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        key.tr,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: AppThemeConfig.mutedText(context),
        ),
      ),
    );

    List<Widget> chipsFor(List<Map<String, dynamic>> cats) => [
      for (final cat in cats)
        _FilterChip(
          label: controller.localizedCategoryName(cat),
          active: selected == (cat['slug'] ?? '').toString(),
          onTap: () =>
              controller.selectCategory((cat['slug'] ?? '').toString()),
        ),
    ];

    final humanitarian = inGroup('humanitarian');
    final programs = inGroup('programs');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([
          _FilterChip(
            label: 'All'.tr,
            active: selected == null || selected.isEmpty,
            onTap: () => controller.selectCategory(null),
          ),
        ]),
        if (humanitarian.isNotEmpty) ...[
          groupLabel('ourwork_humanitarian'),
          row(chipsFor(humanitarian)),
        ],
        if (programs.isNotEmpty) ...[
          groupLabel('ourwork_programs'),
          row(chipsFor(programs)),
        ],
      ],
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

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({required this.item, required this.categoryLabel});

  final Map<String, dynamic> item;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(item, 'title', fallback: 'Post');
    final mediaUrl = _resolveMediaUrl(item['media_url']);

    return Material(
      color: AppThemeConfig.surface(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.to(
          () => OurWorkDetailScreen(item: item, categoryLabel: categoryLabel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mediaUrl != null)
                    CachedNetworkImage(
                      imageUrl: mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppThemeConfig.softSurface(context)),
                      errorWidget: (_, __, ___) => _PortfolioFallback(),
                    )
                  else
                    _PortfolioFallback(),
                  if (categoryLabel.trim().isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          categoryLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.25,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(
        Icons.emoji_events_outlined,
        color: AppThemeConfig.primary,
        size: 34,
      ),
    );
  }
}

String? _resolveMediaUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}

/// Full detail for a single portfolio item — reuses the existing, already
/// polished MediaPostCard (image/gallery, body, date, engagement bar).
class OurWorkDetailScreen extends StatelessWidget {
  const OurWorkDetailScreen({
    super.key,
    required this.item,
    required this.categoryLabel,
  });

  final Map<String, dynamic> item;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: '',
      subtitle: '',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [MediaPostCard(item: item, categoryLabel: categoryLabel)],
      ),
    );
  }
}
