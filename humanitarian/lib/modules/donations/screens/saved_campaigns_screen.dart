// Client report — "where can I see the campaigns I've saved?" The bookmark
// button on the campaign detail screen (campaign_detail_screen.dart's
// _EngagementBar) saved a campaign, but nothing ever showed the saved list —
// same gap the marriage feed had before marriage_saved_screen.dart. This is
// that screen's sibling: same shape (SectionScaffold, AppAsync, optimistic
// unsave), backed by GET /campaigns?saved=1&user_id= instead of GET
// /marriage/saved. Renders with the same DonationFeaturedCampaignCard the
// Contribute screen's own campaign list already uses, so a saved campaign
// looks and behaves identically here.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class SavedCampaignsScreen extends StatefulWidget {
  const SavedCampaignsScreen({super.key, this.api = const ModuleApi()});

  final ModuleApi api;

  @override
  State<SavedCampaignsScreen> createState() => _SavedCampaignsScreenState();
}

class _SavedCampaignsScreenState extends State<SavedCampaignsScreen> {
  List<FeaturedCampaignData> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _userId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = Get.isRegistered<FeaturedCampaignsController>()
          ? Get.find<FeaturedCampaignsController>()
          : Get.put(FeaturedCampaignsController());
      final items = await controller.fetchSavedCampaigns(_userId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your saved campaigns.'.tr;
        _loading = false;
      });
    }
  }

  /// Optimistic unsave — mirrors MarriageSavedScreen._unsave exactly: the
  /// row leaves at once (this list IS "things I saved"), restored if the
  /// server refuses.
  Future<void> _unsave(FeaturedCampaignData campaign) async {
    final index = _items.indexOf(campaign);
    setState(
      () => _items = _items.where((c) => c.id != campaign.id).toList(),
    );
    try {
      await widget.api.saveCampaign(campaign.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final restored = [..._items];
        restored.insert(index.clamp(0, restored.length), campaign);
        _items = restored;
      });
      Get.snackbar('Saved'.tr, 'Could not remove this campaign.'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Saved campaigns'.tr,
      subtitle: 'Campaigns you bookmarked to give to later.'.tr,
      child: AppAsync<List<FeaturedCampaignData>>(
        gutter: const EdgeInsets.symmetric(horizontal: 20),
        loading: _loading,
        error: _error,
        onRetry: _load,
        data: _items,
        isEmpty: (list) => list.isEmpty,
        empty: const AppEmpty(
          icon: Icons.bookmark_border_rounded,
          title: 'No saved campaigns yet.',
          message: 'Tap the bookmark on any campaign to save it here for later.',
        ),
        builder: (list) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final campaign = list[i];
              // DonationFeaturedCampaignCard (unlike MarriagePostCard) has
              // no bookmark button of its own to unsave from, so this list
              // gets the standard "saved list" affordance instead: swipe to
              // remove.
              return Dismissible(
                key: ValueKey('saved-campaign-${campaign.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: AlignmentDirectional.centerEnd,
                  padding: const EdgeInsetsDirectional.only(end: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.bookmark_remove_rounded,
                    color: Colors.white,
                  ),
                ),
                onDismissed: (_) => _unsave(campaign),
                child: DonationFeaturedCampaignCard(
                  campaign: campaign,
                  isSelected: false,
                  onCardTap: () =>
                      Get.to(() => CampaignDetailScreen(campaign: campaign)),
                  onDonatePressed: () => Get.to(
                    () => DonationsSection(initialCampaignId: campaign.id),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
