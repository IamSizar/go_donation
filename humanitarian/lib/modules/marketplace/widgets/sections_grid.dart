// Store sections — admin-curated shelves with a cover image (e.g.
// "Clothing"), shown as a 2-column grid on the store's main page. Tapping a
// tile opens SectionProductsScreen, a list-style page of just that
// section's products. Replaces the horizontal SectionsRail per the client's
// explicit "grid style, like Beauty Lady Z" request — see backend migration
// 134 for the one-section-per-product model this assumes.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/localization/item_count.dart';
import 'package:flutter_application_1/modules/marketplace/controllers/marketplace_controller.dart';
import 'package:flutter_application_1/modules/marketplace/screens/section_products_screen.dart';
import 'package:flutter_application_1/modules/marketplace/widgets/product_gallery.dart';

class SectionsGrid extends StatelessWidget {
  const SectionsGrid({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Loading/empty just render nothing — the store's product list below
      // still works with no sections defined.
      if (controller.isLoadingSections.value) return const SizedBox.shrink();
      final sections = controller.sections;
      if (sections.isEmpty) return const SizedBox.shrink();

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: sections.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.3,
        ),
        itemBuilder: (context, i) {
          final sec = sections[i];
          return _SectionGridTile(
            label: controller.localizedSectionName(sec),
            subtitle: itemCountLabel(
              int.tryParse('${sec['product_count'] ?? 0}') ?? 0,
            ),
            imageUrl: marketplaceMediaUrl(sec['cover_image_path']),
            onTap: () {
              AppHaptics.selection();
              Get.to(
                () => SectionProductsScreen(
                  sectionSlug: (sec['slug'] ?? '').toString(),
                  title: controller.localizedSectionName(sec),
                ),
              );
            },
          );
        },
      );
    });
  }
}

class _SectionGridTile extends StatelessWidget {
  const _SectionGridTile({
    required this.label,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeConfig.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppThemeConfig.softSurface(context)),
              )
            else
              Container(color: AppThemeConfig.softSurface(context)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.4, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
