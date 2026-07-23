import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/community/screens/community_detail_screen.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #33 — route a tapped search result to the right place. `place` and
/// `campaign` open their own detail screen (the search payload only has
/// id + name, so the full entry is fetched first); `partner`, `media` and
/// `product` still open their section screen instead, since it only has
/// id + name.
Future<void> _openSearchResult(Map<String, dynamic> result) async {
  switch ((result['type'] ?? '').toString()) {
    case 'place':
      final entry = await _fetchPlaceEntry(result);
      Get.to(() => CommunityDetailScreen(entry: entry));
      break;
    case 'partner':
      Get.to(() => const PartnersScreen());
      break;
    case 'media':
      Get.to(() => const NewsActivitiesScreen());
      break;
    case 'product':
      Get.to(() => const MarketplaceSection());
      break;
    case 'campaign':
      final campaign = await _fetchCampaignEntry(result);
      if (campaign != null) {
        Get.to(() => CampaignDetailScreen(campaign: campaign));
      } else {
        Get.to(() => const DonationsSection());
      }
      break;
  }
}

// #33 — the search `campaign` result only has id + name; the donor-facing
// campaigns list caps at FeaturedCampaignsController's first page, so look
// the id up via the same paginated endpoint (bounded) before falling back
// to the generic, page-1-only campaigns section.
Future<FeaturedCampaignData?> _fetchCampaignEntry(
  Map<String, dynamic> result,
) async {
  final id = int.tryParse('${result['id']}');
  if (id == null) return null;
  final controller = Get.isRegistered<FeaturedCampaignsController>()
      ? Get.find<FeaturedCampaignsController>()
      : Get.put(FeaturedCampaignsController());
  try {
    return await controller.fetchCampaignById(id);
  } catch (_) {
    return null;
  }
}

// #33 — the search `place` result only has id + name; look up the full
// directory entry so CommunityDetailScreen has category/address/phone/map/
// etc. Falls back to the thin result if the fetch fails or finds no match.
Future<Map<String, dynamic>> _fetchPlaceEntry(Map<String, dynamic> result) async {
  try {
    final entries = await const ModuleApi().communityDirectory();
    for (final entry in entries) {
      if (entry['id'] == result['id']) return entry;
    }
  } catch (_) {
    // fall through to the thin search result
  }
  return result;
}

/// #33 — Global search: one box that queries the whole app (campaigns, news,
/// products, partners, city places) and lists typed, localized results.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;

  static const _typeMeta = <String, ({IconData icon, String labelKey, Color color})>{
    'campaign': (icon: Icons.volunteer_activism_rounded, labelKey: 'search_campaigns', color: Colors.pink),
    'media': (icon: Icons.article_rounded, labelKey: 'search_media', color: Colors.indigo),
    'product': (icon: Icons.storefront_rounded, labelKey: 'search_products', color: Colors.teal),
    'partner': (icon: Icons.handshake_rounded, labelKey: 'search_partners', color: Colors.orange),
    'place': (icon: Icons.location_city_rounded, labelKey: 'search_places', color: Colors.blue),
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final rows = await const ModuleApi().globalSearch(q);
      if (mounted) setState(() => _results = rows);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'search_title'.tr,
      subtitle: 'search_subtitle'.tr,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'search_hint'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _searched && _results.isEmpty && !_loading
                ? Center(child: Text('search_no_results'.tr))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ResultTile(result: _results[i], meta: _typeMeta),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.meta});
  final Map<String, dynamic> result;
  final Map<String, ({IconData icon, String labelKey, Color color})> meta;

  @override
  Widget build(BuildContext context) {
    final type = (result['type'] ?? '').toString();
    final m = meta[type];
    final name = localizedContentFromMap(result, 'name', fallback: '—');
    return GestureDetector(
      onTap: () => _openSearchResult(result),
      child: GlassPanel(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (m?.color ?? Colors.grey).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(m?.icon ?? Icons.search_rounded, color: m?.color ?? Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (m?.labelKey ?? type).tr,
                    style: TextStyle(fontSize: 12, color: m?.color ?? Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppThemeConfig.mutedText(context),
            ),
          ],
        ),
      ),
    );
  }
}
