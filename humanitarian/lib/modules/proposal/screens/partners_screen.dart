import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/proposal/controllers/partners_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:url_launcher/url_launcher.dart';

class PartnersScreen extends StatelessWidget {
  const PartnersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<PartnersController>()
        ? Get.find<PartnersController>()
        : Get.put(PartnersController());

    return SectionScaffold(
      title: 'Partners',
      subtitle: 'Browse partner and supporting entities.',
      child: Obx(() {
        final items = controller.partners;
        return RefreshIndicator(
          onRefresh: controller.fetchPartners,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.apartment_rounded,
                  title: 'Partners',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.blueAccent,
                  onTap: controller.fetchPartners,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                const SectionTile(
                  icon: Icons.apartment_rounded,
                  title: 'Partners',
                  subtitle: 'No partner records are available yet.',
                  color: Colors.blueAccent,
                ),
              for (final item in items) ...[
                _PartnerCard(item: item),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      }),
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
    final socials = _socialLinks(item['social_links']); // #26
    final logoUrl = _partnerLogoUrl(item['logo_path']);

    return GlassPanel(
      padding: EdgeInsets.zero,
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
                _PartnerLogo(logoUrl: logoUrl),
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
                        _PartnerMiniPill(
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
                      _PartnerActionChip(
                        icon: Icons.phone_rounded,
                        label: phone,
                        onTap: () => _launchExternal('tel:$phone'),
                      ),
                    if (email.trim().isNotEmpty)
                      _PartnerActionChip(
                        icon: Icons.email_rounded,
                        label: email,
                        onTap: () => _launchExternal('mailto:$email'),
                      ),
                    if (website.trim().isNotEmpty)
                      _PartnerActionChip(
                        icon: Icons.open_in_new_rounded,
                        label: 'Visit website',
                        onTap: () => _openPartnerWebsite(website),
                      ),
                    if (location.trim().isNotEmpty)
                      _PartnerActionChip(
                        icon: Icons.place_rounded,
                        label: location,
                        onTap: () => _openMaps(location),
                      ),
                    for (final link in socials)
                      _PartnerActionChip(
                        icon: Icons.public_rounded,
                        label: _socialLabel(link),
                        onTap: () => _openPartnerWebsite(link),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _PartnerRating(item: item), // #27
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerLogo extends StatelessWidget {
  const _PartnerLogo({required this.logoUrl});

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

class _PartnerMiniPill extends StatelessWidget {
  const _PartnerMiniPill({required this.icon, required this.label});

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

class _PartnerActionChip extends StatelessWidget {
  const _PartnerActionChip({
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
class _PartnerRating extends StatelessWidget {
  const _PartnerRating({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final avg = (item['avg_rating'] as num?)?.toDouble() ?? 0;
    final count = (item['rating_count'] as num?)?.toInt() ?? 0;
    final mine = (item['my_rating'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        _StarsRow(value: avg),
        const SizedBox(width: 8),
        Text(
          count > 0 ? '${avg.toStringAsFixed(1)} ($count)' : 'No ratings yet'.tr,
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

class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.value});

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
  final current = (item['my_rating'] as num?)?.toInt() ?? 0;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppThemeConfig.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rate this partner'.tr,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  iconSize: 42,
                  color: Colors.amber,
                  icon: Icon(
                    star <= current
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    controller.submitRating(item, star);
                  },
                );
              }),
            ),
          ],
        ),
      ),
    ),
  );
}

List<String> _socialLinks(dynamic raw) {
  final text = (raw ?? '').toString();
  if (text.trim().isEmpty) return const [];
  return text
      .split(RegExp(r'[\n,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

String _socialLabel(String url) {
  final u = url.toLowerCase();
  if (u.contains('facebook') || u.contains('fb.')) return 'Facebook';
  if (u.contains('instagram') || u.contains('instagr.am')) return 'Instagram';
  if (u.contains('wa.me') || u.contains('whatsapp')) return 'WhatsApp';
  if (u.contains('t.me') || u.contains('telegram')) return 'Telegram';
  if (u.contains('youtube') || u.contains('youtu.be')) return 'YouTube';
  if (u.contains('tiktok')) return 'TikTok';
  if (u.contains('twitter') || u.contains('x.com')) return 'X';
  if (u.contains('linkedin')) return 'LinkedIn';
  return 'Social';
}

Future<void> _launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> _openMaps(String location) async {
  final query = Uri.encodeComponent(location.trim());
  await _launchExternal(
    'https://www.google.com/maps/search/?api=1&query=$query',
  );
}

String? _partnerLogoUrl(dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) return path;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(path.replaceFirst(RegExp(r'^/+'), '')).toString();
}

Future<void> _openPartnerWebsite(String rawWebsite) async {
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
