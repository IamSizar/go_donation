import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';
import 'package:flutter_application_1/modules/community/screens/community_detail_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class CommunityServicesSection extends StatelessWidget {
  const CommunityServicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionScaffold(
      title: 'Community Services',
      subtitle:
          'Browse local support programs by category, region, and urgency.',
      child: _CommunityServicesList(),
    );
  }
}

class _CommunityServicesList extends StatelessWidget {
  const _CommunityServicesList();

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<CommunityController>()
        ? Get.find<CommunityController>()
        : Get.put(CommunityController());

    return Obx(() {
      final items = controller.entries;
      final error = controller.errorMessage.value;

      return RefreshIndicator(
        onRefresh: controller.fetchEntries,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            if (controller.isLoading.value)
              const Center(child: CircularProgressIndicator()),
            if (error != null)
              SectionTile(
                icon: Icons.local_library_rounded,
                title: 'Services Directory',
                subtitle: error,
                color: Colors.indigo,
                onTap: controller.fetchEntries,
              ),
            if (error == null && !controller.isLoading.value && items.isEmpty)
              const SectionTile(
                icon: Icons.local_library_rounded,
                title: 'Services Directory',
                subtitle: 'No approved city services are available yet.',
                color: Colors.indigo,
              ),
            for (final item in items) ...[
              SectionTile(
                icon: Icons.local_library_rounded,
                title: localizedContentFromMap(
                  item,
                  'name',
                  fallback: 'Service',
                ),
                subtitle:
                    '${item['category'] ?? 'Service'} • ${item['city'] ?? ''} • ${item['phone'] ?? ''}',
                color: Colors.indigo,
                onTap: () => Get.to(() => CommunityDetailScreen(entry: item)),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      );
    });
  }
}
