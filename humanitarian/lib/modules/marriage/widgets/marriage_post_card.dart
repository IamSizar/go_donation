import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/core/id_privacy.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

// Marriage Posts — resolve a stored photo path to a full URL. Uploads are
// saved as relative paths (e.g. images/uploads/x.png); Image.network needs
// an absolute URL. Same pattern as aid_receipts_screen/marriage_form_screen.
String resolveMarriagePhotoUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final uri = Uri.tryParse(p);
  if (uri != null && uri.hasScheme) return p;
  return Uri.parse(publicBaseUrl).resolve(p.replaceFirst(RegExp(r'^/+'), '')).toString();
}

/// Marriage Posts — the feed IS the approved profiles themselves (photo +
/// age/city/gender + bio), not admin-authored articles. This card is the
/// photo-forward, full-width version used by the continuous feed; the
/// filtered Search screen keeps its own compact `_ProfileCard` unchanged.
class MarriagePostCard extends StatelessWidget {
  const MarriagePostCard({
    super.key,
    required this.profile,
    required this.saved,
    required this.onSave,
    required this.onMeet,
  });

  final Map<String, dynamic> profile;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onMeet;

  @override
  Widget build(BuildContext context) {
    final code = maskId((profile['profile_code'] ?? '').toString());
    final gender = (profile['gender'] ?? '').toString();
    final age = (profile['age'] ?? '').toString();
    final city = (profile['city'] ?? '').toString();
    final summary = localizedContentFromMap(profile, 'social_summary');
    final photoUrl = (profile['photo_url'] ?? '').toString();
    final sub = [
      if (gender.isNotEmpty) gender.tr,
      if (age.isNotEmpty && age != '0') age,
      if (city.isNotEmpty) city,
    ].join(' · ');

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: photoUrl.isNotEmpty
                  ? Image.network(
                      resolveMarriagePhotoUrl(photoUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(context, gender),
                    )
                  : _placeholder(context, gender),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(code,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    IconButton(
                      icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          color: saved ? Colors.pink : null),
                      onPressed: onSave,
                    ),
                  ],
                ),
                if (sub.isNotEmpty)
                  Text(sub, style: TextStyle(color: AppThemeConfig.mutedText(context))),
                if (summary.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onMeet,
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text('request_meeting'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, String gender) {
    final icon = gender.toLowerCase() == 'female' ? Icons.face_3_rounded : Icons.face_6_rounded;
    return Container(
      color: AppThemeConfig.softSurface(context),
      alignment: Alignment.center,
      child: Icon(icon, size: 56, color: AppThemeConfig.mutedText(context)),
    );
  }
}
