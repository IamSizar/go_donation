// The featured campaigns list (R2 #47).
//
// This used to be the top of the Contribute tab, wrapped in an amount picker,
// a summary card and an explainer. The donation flow is now its own two steps
// (see donations_section.dart), so the campaigns are simply a list: tap a card
// for its details, tap its button to give to it.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/donations/screens/saved_campaigns_screen.dart';

class CampaignsScreen extends StatelessWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<FeaturedCampaignsController>()
        ? Get.find<FeaturedCampaignsController>()
        : Get.put(FeaturedCampaignsController());
    return AppScreen(
      title: 'Featured campaigns',
      trailing: IconButton.filledTonal(
        onPressed: () => Get.to(() => const SavedCampaignsScreen()),
        icon: const Icon(Icons.bookmark_rounded, size: 20),
        tooltip: 'Saved campaigns'.tr,
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      child: RefreshIndicator(
        onRefresh: controller.refreshCampaigns,
        child: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = controller.errorMessage.value;
          if (error != null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 48),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppThemeConfig.mutedText(context)),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ElevatedButton(
                    onPressed: controller.refreshCampaigns,
                    child: Text('Retry'.tr),
                  ),
                ),
              ],
            );
          }
          if (controller.campaigns.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 48),
                Text(
                  'No campaigns available.'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppThemeConfig.mutedText(context)),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: controller.campaigns.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final campaign = controller.campaigns[i];
              return DonationFeaturedCampaignCard(
                campaign: campaign,
                isSelected: false,
                onCardTap: () {
                  Get.to(() => CampaignDetailScreen(campaign: campaign))?.then((
                    donate,
                  ) {
                    if (donate == true) {
                      Get.to(
                        () => DonationsSection(initialCampaignId: campaign.id),
                      );
                    }
                  });
                },
                // Donating is a "purchase", so guests are prompted to upgrade
                // first (also enforced server-side).
                onDonatePressed: () async {
                  if (!await requireUpgrade(context)) return;
                  AppHaptics.selection();
                  Get.to(
                    () => DonationsSection(initialCampaignId: campaign.id),
                  );
                },
              );
            },
          );
        }),
      ),
    );
  }
}
