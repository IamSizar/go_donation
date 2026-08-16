import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/shared/utils/social_links.dart';
import 'package:flutter_application_1/shared/utils/upload_urls.dart';

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

  /// User-facing reason the joint-activity history is missing, or null.
  ///
  /// Kept separate from `_activities.isEmpty` on purpose. A partner with no
  /// recorded joint activities and a partner whose history failed to load both
  /// leave the list empty, but they are opposite claims: the first says this
  /// partnership has produced nothing, which is a real and checkable statement
  /// about an organization's record. We must not make it on the strength of a
  /// dropped connection.
  String? _activitiesError;

  int get _partnerId => (widget.partner['id'] as num?)?.toInt() ?? 0;

  /// K24 — the organization's rating switch, read from the SAME controller the
  /// list uses. This page is handed its partner map by whoever opened it (the
  /// list, or a Home logo card), and both of those already read
  /// [PartnersController], so there is no second copy of the policy to drift.
  bool _ratingsVisible() => (Get.isRegistered<PartnersController>()
          ? Get.find<PartnersController>()
          : Get.put(PartnersController()))
      .ratingsVisible
      .value;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  /// Loads the activity history. Also the RefreshIndicator's callback, so it
  /// runs both as a first load and as a user-initiated refresh.
  Future<void> _loadActivities() async {
    // Cleared up front so a successful retry cannot leave the previous
    // failure's banner sitting above fresh, correct rows.
    if (_activitiesError != null) {
      setState(() => _activitiesError = null);
    }
    try {
      final items = await ModuleApi().partnerActivities(_partnerId);
      if (!mounted) return;
      setState(() {
        _activities = items;
        _loadingActivities = false;
      });
    } catch (e) {
      // partnerActivities now THROWS rather than returning `const []`. Without
      // this guard the rejected future would escape initState as an unhandled
      // async error — trading a wrong empty state for a crash, which is worse.
      if (!mounted) return;
      setState(() {
        _activitiesError = 'Could not load this partner\'s joint activities.';
        _loadingActivities = false;
      });
      debugPrint('partnerActivities($_partnerId) failed: $e');
    }
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
    final socials = socialLinksFrom(item['social_links']);
    final logoUrl = uploadedImageUrl(item['logo_path']);

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
                        label: socialNetworkLabel(link),
                        onTap: () => openPartnerWebsite(link),
                      ),
                  ],
                ),
              ),
            ],

            // Rating level — the crowd rating (with the viewer's own star
            // picker) and, when staff have assessed the partner, the
            // organization's own rating broken down by criterion.
            //
            // K24 — the whole SECTION goes when the organization has ratings
            // switched off, heading included. Hiding only the stars would
            // leave a "Rating" panel with nothing in it, which reads as a
            // partner nobody has assessed rather than as a feature the
            // organization does not publish. The server strips both numbers
            // together, so they belong behind one switch here too.
            Obx(() {
              if (!_ratingsVisible()) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                ],
              );
            }),

            // History of activities implemented in cooperation with the
            // partner.
            const SizedBox(height: 12),
            _Section(
              title: 'Joint activities'.tr,
              icon: Icons.history_rounded,
              child: _activitiesBody(context),
            ),
          ],
        ),
      ),
    );
  }

  /// The four states of the joint-activity history, in the one order that is
  /// correct: loading, then ERROR, then empty, then content.
  ///
  /// Error must be tested before empty. A failed fetch leaves `_activities`
  /// empty too, so an `isEmpty` check placed first would swallow every failure
  /// back into "No joint activities recorded yet." — the exact bug being fixed.
  ///
  /// This section is one child of the page's ListView, so it is laid out with
  /// UNBOUNDED height. That rules out the shared [AppAsync] switcher here:
  /// its empty state scrolls (AppEmpty wraps a SingleChildScrollView) and its
  /// stale-content error branch uses an Expanded, both of which throw under
  /// unbounded constraints. The same widgets are used directly instead, in the
  /// same order, choosing the shapes that size themselves.
  Widget _activitiesBody(BuildContext context) {
    if (_loadingActivities) {
      // A skeleton shaped like _ActivityTile — a title line and a date/code
      // line, no progress rule — so the rows fill in rather than pop in.
      return AppSkeleton.rows(count: 3, withProgress: false);
    }

    if (_activitiesError != null) {
      // AppErrorState's own `staleContent` slot is not used, because it lays
      // the kept content out with an Expanded — fine full-screen, fatal under
      // this section's unbounded height. The same idea is composed by hand: on
      // a failed REFRESH the rows already fetched stay readable beneath the
      // banner, dimmed to mark them as possibly out of date.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppErrorState(message: _activitiesError!, onRetry: _loadActivities),
          if (_activities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Opacity(
              opacity: 0.55,
              child: Column(
                children: [
                  for (final a in _activities) _ActivityTile(activity: a),
                ],
              ),
            ),
          ],
        ],
      );
    }

    if (_activities.isEmpty) {
      // Reached only on a load that genuinely succeeded and returned nothing.
      return Text(
        'No joint activities recorded yet.'.tr,
        style: TextStyle(color: AppThemeConfig.mutedText(context), height: 1.5),
      );
    }

    return Column(
      children: [for (final a in _activities) _ActivityTile(activity: a)],
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
