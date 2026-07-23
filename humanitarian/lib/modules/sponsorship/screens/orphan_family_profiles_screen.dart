import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/beneficiary_cases_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/beneficiary_case_detail_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class OrphanFamilyProfilesScreen extends StatelessWidget {
  const OrphanFamilyProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Reuses the same public-cases feed as "Beneficiary cases" in Services —
    // real approved records instead of hardcoded placeholder people.
    final controller = Get.isRegistered<BeneficiaryCasesController>()
        ? Get.find<BeneficiaryCasesController>()
        : Get.put(BeneficiaryCasesController());

    return SectionScaffold(
      title: 'Orphan & Family Profiles',
      subtitle: 'See updates, family needs, and sponsorship history.',
      child: Obx(() {
        final items = controller.cases;
        return RefreshIndicator(
          onRefresh: controller.fetchCases,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              const _ProfilesIntroCard(),
              const SizedBox(height: 22),
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.child_care_rounded,
                  title: 'Orphan & Family Profiles',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.amber,
                  onTap: controller.fetchCases,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                SectionTile(
                  icon: Icons.child_care_rounded,
                  title: 'Orphan & Family Profiles',
                  subtitle: 'No approved profiles are available yet.',
                  color: Colors.amber,
                ),
              for (final item in items) ...[
                _ProfileCard(item: item),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _ProfilesIntroCard extends StatelessWidget {
  const _ProfilesIntroCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile directory'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Each profile gives donors a clearer understanding of who is being supported, what needs are active, and what progress has been shared recently.'
                .tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      item,
      'public_title',
      fallback: 'Eligible profile',
    );
    final priority = (item['priority_level'] ?? '').toString();
    final color = _profileColor(priority);

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () =>
              Get.to(() => BeneficiaryCaseDetailScreen(caseItem: item)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TileIcon(icon: _profileIcon(item), color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _profileSubtitle(item),
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _profileTag(priority).tr,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _profileNote(item).tr,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Get.to(() => const SponsorshipFormScreen()),
                    icon: const Icon(Icons.favorite_rounded, size: 18),
                    label: Text('Sponsor'.tr),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _profileSubtitle(Map<String, dynamic> item) {
  final familyCount = item['family_members_count'];
  final familyLabel = familyCount == null
      ? ''
      : (familyCount == 1 ? 'Individual' : 'Family of $familyCount');
  final city = (item['city'] ?? '').toString().trim();
  return [familyLabel, city].where((value) => value.isNotEmpty).join(' • ');
}

String _profileNote(Map<String, dynamic> item) {
  final needs = (item['actual_needs'] ?? '').toString().trim();
  return needs.isEmpty ? 'No needs update has been shared yet.' : needs;
}

String _profileTag(String priority) {
  return switch (priority) {
    'urgent' => 'Urgent need',
    'high' => 'High priority',
    'low' => 'Stable support',
    _ => 'Ongoing support',
  };
}

Color _profileColor(String priority) {
  return switch (priority) {
    'urgent' => Colors.redAccent,
    'high' => Colors.amber,
    'low' => Colors.teal,
    _ => Colors.blueAccent,
  };
}

IconData _profileIcon(Map<String, dynamic> item) {
  final familyCount = item['family_members_count'];
  if (familyCount is num && familyCount > 1) {
    return Icons.family_restroom_rounded;
  }
  return Icons.child_care_rounded;
}
