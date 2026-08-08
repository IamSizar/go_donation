import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Client spec, "Eleventh: Partners Section" — the dedicated Partner Page.
///
/// Opened by tapping a partner in the list. The list card already carries a
/// summary; this page is the full record the spec asks for: all partner
/// information, logo, short introduction, communication methods, website /
/// official page, social media accounts, contact information, the history of
/// activities carried out in cooperation with the partner, and the rating.
///
/// The partner map is handed in from the list rather than re-fetched — it is
/// the same payload `GET /api/partners` already returns, so the page opens
/// with no spinner. Only the activity history needs a request of its own.
class PartnerDetailScreen extends StatefulWidget {
  const PartnerDetailScreen({super.key, required this.partner});

  final Map<String, dynamic> partner;

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
  List<Map<String, dynamic>> _activities = const [];
  bool _loadingActivities = true;

  int get _partnerId => (widget.partner['id'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    final items = await ModuleApi().partnerActivities(_partnerId);
    if (!mounted) return;
    setState(() {
      _activities = items;
      _loadingActivities = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.partner;
    final name = localizedContentFromMap(item, 'name', fallback: 'Partner');
    final description = localizedContentFromMap(item, 'description');
    final type = (item['partner_type'] ?? '').toString();
    final phone = (item['contact_phone'] ?? '').toString();
    final email = (item['email'] ?? '').toString();
    final website = (item['website'] ?? '').toString();
    final location = localizedContentFromMap(item, 'location');
    final socials = partnerSocialLinks(item['social_links']);
    final logoUrl = partnerLogoUrl(item['logo_path']);

    return SectionScaffold(
      title: name,
      subtitle: type.trim(),
      child: RefreshIndicator(
        onRefresh: _loadActivities,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            // Logo + name + type.
            GlassPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PartnerLogo(logoUrl: logoUrl),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: AppThemeConfig.text(context),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        if (type.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          PartnerMiniPill(
                            icon: Icons.business_center_rounded,
                            label: type,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Short introduction.
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'About the partner'.tr,
                icon: Icons.info_outline_rounded,
                child: Text(
                  description,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    height: 1.55,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],

            // Communication methods, website and contact information.
            if (phone.trim().isNotEmpty ||
                email.trim().isNotEmpty ||
                website.trim().isNotEmpty ||
                location.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'Contact information'.tr,
                icon: Icons.contact_page_outlined,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (phone.trim().isNotEmpty)
                      PartnerActionChip(
                        icon: Icons.phone_rounded,
                        label: phone,
                        onTap: () => launchPartnerExternal('tel:$phone'),
                      ),
                    if (email.trim().isNotEmpty)
                      PartnerActionChip(
                        icon: Icons.email_rounded,
                        label: email,
                        onTap: () => launchPartnerExternal('mailto:$email'),
                      ),
                    if (website.trim().isNotEmpty)
                      PartnerActionChip(
                        icon: Icons.open_in_new_rounded,
                        label: 'Visit website'.tr,
                        onTap: () => openPartnerWebsite(website),
                      ),
                    if (location.trim().isNotEmpty)
                      PartnerActionChip(
                        icon: Icons.place_rounded,
                        label: location,
                        onTap: () => openPartnerMaps(location),
                      ),
                  ],
                ),
              ),
            ],

            // Social media accounts — their own section, as the spec lists
            // them separately from the contact methods.
            if (socials.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'Social media accounts'.tr,
                icon: Icons.public_rounded,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final link in socials)
                      PartnerActionChip(
                        icon: Icons.public_rounded,
                        label: partnerSocialLabel(link),
                        onTap: () => openPartnerWebsite(link),
                      ),
                  ],
                ),
              ),
            ],

            // Rating level — the crowd rating (with the viewer's own star
            // picker) and, when staff have assessed the partner, the
            // organization's own rating broken down by criterion.
            const SizedBox(height: 12),
            _Section(
              title: 'Rating'.tr,
              icon: Icons.star_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PartnerRating(item: item),
                  ..._adminRating(context, item),
                ],
              ),
            ),

            // History of activities implemented in cooperation with the
            // partner.
            const SizedBox(height: 12),
            _Section(
              title: 'Joint activities'.tr,
              icon: Icons.history_rounded,
              child: _loadingActivities
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _activities.isEmpty
                  ? Text(
                      'No joint activities recorded yet.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.5,
                      ),
                    )
                  : Column(
                      children: [
                        for (final a in _activities) _ActivityTile(activity: a),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The organization-assessed rating (migration 090). Kept separate from the
  /// crowd average so the two never read as the same number: this one is set
  /// by staff against the spec's criteria, and is simply absent until they
  /// score the partner.
  List<Widget> _adminRating(BuildContext context, Map<String, dynamic> item) {
    final rating = (item['admin_rating'] as num?)?.toDouble();
    final note = (item['admin_rating_note'] ?? '').toString();
    if (rating == null || rating <= 0) return const [];

    final criteria = <String, int?>{
      'Completed activities': (item['score_activities'] as num?)?.toInt(),
      'Value of donations': (item['score_donations'] as num?)?.toInt(),
      'Cooperation': (item['score_cooperation'] as num?)?.toInt(),
      'Continuity of support': (item['score_continuity'] as num?)?.toInt(),
    };

    return [
      const SizedBox(height: 12),
      Divider(color: AppThemeConfig.border(context), height: 1),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              'Organization assessment'.tr,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
          PartnerStarsRow(value: rating),
          const SizedBox(width: 6),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
      for (final entry in criteria.entries)
        if (entry.value != null && entry.value! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key.tr,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      fontSize: 13,
                    ),
                  ),
                ),
                PartnerStarsRow(value: entry.value!.toDouble()),
              ],
            ),
          ),
      if (note.trim().isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          note,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ];
  }
}

/// One activity carried out with this partner. Shows the activity code from
/// migration 089 so it can be quoted in correspondence.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final Map<String, dynamic> activity;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      activity,
      'title',
      fallback: 'Activity',
    );
    final date = (activity['event_date'] ?? '').toString();
    final code = (activity['activity_code'] ?? '').toString();
    final media = (activity['media_url'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: media.trim().isEmpty
                  ? Container(
                      color: AppThemeConfig.surface(context),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: media,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: AppThemeConfig.surface(context),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 20,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (date.trim().isNotEmpty) date,
                    if (code.trim().isNotEmpty) code,
                  ].join('  •  '),
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled panel, so each part of the spec's list reads as its own block.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppThemeConfig.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppThemeConfig.text(context),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
