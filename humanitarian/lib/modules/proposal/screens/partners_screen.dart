import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/partner_detail_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/shared/utils/social_links.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application_1/core/widgets/app_list_search_field.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

class PartnersScreen extends StatefulWidget {
  const PartnersScreen({super.key});

  @override
  State<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends State<PartnersScreen> {
  // WAS an `onlySupporting` constructor flag, set by a second drawer row
  // ("Supporting Organizations") that opened this same screen over the same
  // fetched list. Two menu entries for one list is the duplication the
  // redesign is removing — but the CAPABILITY is a client request and had to
  // survive, so the flag became a filter here instead of being deleted with
  // the menu row. One destination, the choice made inside it.
  static const _filters = <({String key, String label})>[
    (key: 'all', label: 'All partners'),
    // Capitalised to match the existing translated key rather than adding a
    // second one that differs only in case.
    (key: 'supporting', label: 'Supporting Organizations'),
  ];

  String _selected = 'all';

  // Client note — there is no separate category field for this in the data (a
  // partner is just a partner, with a free-text `partner_type`), so by request
  // this filters that existing field for anything an admin has labeled as a
  // supporting organization rather than adding a new column.
  static const List<String> _supportingKeywords = [
    'support',
    'داعم',
    'پشتیوان',
    'پشتگیر',
  ];

  bool _isSupporting(Map<String, dynamic> item) {
    final type = (item['partner_type'] ?? '').toString().toLowerCase();
    if (type.isEmpty) return false;
    return _supportingKeywords.any((k) => type.contains(k));
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<PartnersController>()
        ? Get.find<PartnersController>()
        : Get.put(PartnersController());

    return SectionScaffold(
      title: 'Partners',
      subtitle: 'Browse partner and supporting entities.',
      child: Column(
        children: [
          // Same chip row as the sponsorship schedule's filter, deliberately:
          // one convention for "narrow this list", not a second one.
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _filters[i];
                final active = f.key == _selected;
                return Material(
                  color: active
                      ? AppThemeConfig.primary
                      : AppThemeConfig.surface(context),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (f.key == _selected) return;
                      setState(() => _selected = f.key);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        f.label.tr,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: active
                              ? Colors.white
                              : AppThemeConfig.text(context),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // J8 — in-list search. Wired to the SERVER (`?q=`), not to the 50
          // partners already loaded: the register is capped per response, so a
          // local filter would report a partner as unlisted on the strength of
          // rows it had never fetched.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppListSearchField(onChanged: controller.setSearchQuery),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              final supporting = _selected == 'supporting';
              final searching = controller.hasActiveSearch;
              final items = supporting
                  ? controller.partners.where(_isSupporting).toList()
                  : controller.partners.toList();
              // AppAsync renders exactly ONE of loading / content / error /
              // empty. This screen previously stacked three `if` blocks inside
              // the same ListView, so a failed load could show the error tile
              // AND the empty tile at once, and the "error" was a SectionTile
              // whose retry was an unlabelled onTap - nothing told the user it
              // could be tapped.
              return AppAsync<List<Map<String, dynamic>>>(
                loading: controller.isLoading.value,
                error: controller.errorMessage.value,
                onRetry: controller.fetchPartners,
                data: items,
                isEmpty: (list) => list.isEmpty,
                // Per-filter empty copy: "no supporting organizations" is a
                // different fact from "no partners at all", and the filtered
                // view being empty says nothing about the full list.
                //
                // J8 adds a third case, and it is the one that matters most: a
                // SEARCH that matched nothing. "No partner records are
                // available yet" would then be a false statement about the
                // organization's register, made because the user typed a word.
                empty: searching
                    ? AppEmpty(
                        icon: Icons.search_off_rounded,
                        title: 'search_title',
                        message: 'search_no_results',
                      )
                    : AppEmpty(
                        title: supporting
                            ? 'Supporting Organizations'
                            : 'Partners',
                        message: supporting
                            ? 'No supporting organizations are listed yet.'
                            : 'No partner records are available yet.',
                      ),
                builder: (list) => RefreshIndicator(
                  onRefresh: controller.fetchPartners,
                  child: ListView(
                    // Scrolling the results puts the keyboard away, so it
                    // never covers the rows the search just found.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      for (final item in list) ...[
                        _PartnerCard(item: item),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = localizedContentFromMap(item, 'name', fallback: 'Partner');
    final description = localizedContentFromMap(item, 'description');
    final type = (item['partner_type'] ?? '').toString();
    final phone = (item['contact_phone'] ?? '').toString();
    final email = (item['email'] ?? '').toString(); // #26
    final website = (item['website'] ?? '').toString();
    final location = localizedContentFromMap(item, 'location'); // #26
    final socials = socialLinksFrom(item['social_links']); // #26
    final logoUrl = partnerLogoUrl(item['logo_path']);

    // "Eleventh: Partners Section" — the whole card opens the dedicated
    // Partner Page. The partner map goes straight across, so the page has
    // every field the list already loaded and only fetches the activity
    // history.
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Get.to(() => PartnerDetailScreen(partner: item)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppThemeConfig.primary.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(color: AppThemeConfig.border(context)),
                ),
              ),
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppThemeConfig.text(context),
                            fontSize: 19,
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (description.trim().isNotEmpty)
                    Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.5,
                        fontSize: 14.5,
                      ),
                    )
                  else
                    Text(
                      'Supporting partner'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
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
                          label: 'Visit website',
                          onTap: () => openPartnerWebsite(website),
                        ),
                      if (location.trim().isNotEmpty)
                        PartnerActionChip(
                          icon: Icons.place_rounded,
                          label: location,
                          onTap: () => openPartnerMaps(location),
                        ),
                      for (final link in socials)
                        PartnerActionChip(
                          icon: Icons.public_rounded,
                          label: socialNetworkLabel(link),
                          onTap: () => openPartnerWebsite(link),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  PartnerRating(item: item), // #27
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PartnerLogo extends StatelessWidget {
  const PartnerLogo({super.key, required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 78,
        height: 78,
        child: logoUrl == null
            ? const _PartnerLogoFallback()
            : CachedNetworkImage(
                imageUrl: logoUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (context, url) => const _PartnerLogoLoading(),
                errorWidget: (context, url, error) =>
                    const _PartnerLogoFallback(),
              ),
      ),
    );
  }
}

class _PartnerLogoLoading extends StatelessWidget {
  const _PartnerLogoLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.surface(context),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _PartnerLogoFallback extends StatelessWidget {
  const _PartnerLogoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppThemeConfig.surface(context),
      alignment: Alignment.center,
      child: Icon(
        Icons.apartment_rounded,
        color: AppThemeConfig.primary,
        size: 30,
      ),
    );
  }
}

class PartnerMiniPill extends StatelessWidget {
  const PartnerMiniPill({super.key, required this.icon, required this.label});

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
          Icon(icon, size: 16, color: AppThemeConfig.primary),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label.tr,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PartnerActionChip extends StatelessWidget {
  const PartnerActionChip({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onTap == null
            ? AppThemeConfig.surface(context)
            : AppThemeConfig.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppThemeConfig.primary),
          const SizedBox(width: 8),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: child,
    );
  }
}

// #27 — average-rating display + a "Rate" button opening a 1–5 star picker.
//
// K24 — renders NOTHING while the organization has ratings switched off. The
// server strips the scores in that state, so what stood here before was five
// empty stars over "No ratings yet" and a working Rate button: two lies and a
// dead end. The empty phrase is a claim about the partner ("nobody has rated
// this organization"); the truth is that the organization does not publish
// ratings, which is not the partner's business at all.
class PartnerRating extends StatelessWidget {
  const PartnerRating({super.key, required this.item});

  final Map<String, dynamic> item;

  /// The shared controller both the list and the Partner Page already use, so
  /// the visibility switch has ONE home rather than a copy per screen.
  static PartnersController _controller() =>
      Get.isRegistered<PartnersController>()
      ? Get.find<PartnersController>()
      : Get.put(PartnersController());

  @override
  Widget build(BuildContext context) {
    if (!_controller().ratingsVisible.value) return const SizedBox.shrink();
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['rating_count'] as num?)?.toInt() ?? 0;
    final mine = (item['my_rating'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        PartnerStarsRow(value: avg),
        const SizedBox(width: 8),
        Text(
          count > 0
              ? '${avg.toStringAsFixed(1)} ($count)'
              : 'No ratings yet'.tr,
          style: TextStyle(
            color: AppThemeConfig.mutedText(context),
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          // #44 — guests are prompted to sign in before acting.
          onPressed: () async {
            if (!await requireSignIn(context)) return;
            if (!context.mounted) return;
            _openRatePicker(context, item);
          },
          icon: Icon(
            mine > 0 ? Icons.star_rounded : Icons.star_border_rounded,
            size: 18,
          ),
          label: Text(mine > 0 ? '${'Your rating'.tr}: $mine' : 'Rate'.tr),
        ),
      ],
    );
  }
}

class PartnerStarsRow extends StatelessWidget {
  const PartnerStarsRow({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final filled = value.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: Colors.amber,
        ),
      ),
    );
  }
}

void _openRatePicker(BuildContext context, Map<String, dynamic> item) {
  final controller = Get.isRegistered<PartnersController>()
      ? Get.find<PartnersController>()
      : Get.put(PartnersController());
  showModalBottomSheet<void>(
    context: context,
    // Transparent so the sheet's own opaque container is the only background.
    backgroundColor: Colors.transparent,
    builder: (_) => _RatePickerSheet(item: item, controller: controller),
  );
}

/// #27 — star picker with an explicit Submit button. Tapping a star only
/// *selects* it (nothing is sent until Submit), and the sheet has a solid
/// opaque background so nothing shows through.
class _RatePickerSheet extends StatefulWidget {
  const _RatePickerSheet({required this.item, required this.controller});

  final Map<String, dynamic> item;
  final PartnersController controller;

  @override
  State<_RatePickerSheet> createState() => _RatePickerSheetState();
}

class _RatePickerSheetState extends State<_RatePickerSheet> {
  late int _selected = (widget.item['my_rating'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          // elevatedSurface = fully opaque (solid), unlike surface().
          color: AppThemeConfig.elevatedSurface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: AppThemeConfig.border(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppThemeConfig.mutedText(
                    context,
                  ).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Rate this partner'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    iconSize: 44,
                    color: Colors.amber,
                    icon: Icon(
                      star <= _selected
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                    ),
                    onPressed: () => setState(() => _selected = star),
                  );
                }),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected > 0
                      ? () {
                          widget.controller.submitRating(
                            widget.item,
                            _selected,
                          );
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Submit'.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// K17 — these two used to be defined here. The City Guide place page needs
// the same parsing for the same column shape (migration 100 says so in as many
// words), so they moved to shared/utils/social_links.dart and both screens now
// read one definition.

Future<void> launchPartnerExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> openPartnerMaps(String location) async {
  final query = Uri.encodeComponent(location.trim());
  await launchPartnerExternal(
    'https://www.google.com/maps/search/?api=1&query=$query',
  );
}

String? partnerLogoUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}

Future<void> openPartnerWebsite(String rawWebsite) async {
  final trimmed = rawWebsite.trim();
  if (trimmed.isEmpty) return;
  final normalized = trimmed.startsWith(RegExp(r'https?://'))
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    Get.snackbar('Error'.tr, 'Invalid website link.'.tr);
    return;
  }
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) {
    Get.snackbar('Error'.tr, 'Could not open website.'.tr);
  }
}
