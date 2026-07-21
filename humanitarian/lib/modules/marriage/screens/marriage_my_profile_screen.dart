import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/marriage/controllers/marriage_my_profile_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

// Note #18 — shows the user their OWN submitted marriage profile and its
// review status (submitted/under_review/active/paused/matched/rejected/
// closed). Previously the app gave zero visibility after submitting — the
// user just got a one-time toast and had no way to check back. Mirrors
// BeneficiaryMyProjectsScreen's layout/pattern for consistency.
class MarriageMyProfileScreen extends StatelessWidget {
  const MarriageMyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<MarriageMyProfileController>()
        ? Get.find<MarriageMyProfileController>()
        : Get.put(MarriageMyProfileController());

    return SectionScaffold(
      title: 'marriage_my_profile'.tr,
      subtitle: 'marriage_my_profile_desc'.tr,
      child: Obx(() {
        final items = controller.profiles;
        return RefreshIndicator(
          onRefresh: controller.fetchProfiles,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              if (controller.isLoading.value)
                const Center(child: CircularProgressIndicator()),
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.refresh_rounded,
                  title: 'marriage_my_profile'.tr,
                  subtitle: controller.errorMessage.value!,
                  color: Colors.orange,
                  onTap: controller.fetchProfiles,
                ),
              if (!controller.isLoading.value &&
                  controller.errorMessage.value == null &&
                  items.isEmpty)
                SectionTile(
                  icon: Icons.favorite_outline_rounded,
                  title: 'marriage_my_profile_empty'.tr,
                  subtitle: 'marriage_my_profile_empty_desc'.tr,
                  color: Colors.pink,
                ),
              for (final item in items) ...[
                _ProfileStatusCard(item: item),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _ProfileStatusCard extends StatelessWidget {
  const _ProfileStatusCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final code = (item['profile_code'] ?? '').toString();
    final status = (item['status'] ?? 'submitted').toString();
    final city = (item['city'] ?? '').toString();
    final summary = (item['social_summary'] ?? '').toString();
    final createdAt = _dateLabel(item['created_at']);
    final color = _statusColor(status);

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileIcon(icon: Icons.favorite_rounded, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code.isNotEmpty ? code : 'marriage_title'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    if (city.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        city,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatusPill(status: status, color: color),
            ],
          ),
          if (summary.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.5,
              ),
            ),
          ],
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 14),
            _MetricPill(icon: Icons.schedule_rounded, label: createdAt),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppThemeConfig.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _dateLabel(dynamic raw) {
  final parsed = DateTime.tryParse((raw ?? '').toString());
  if (parsed == null) return '';
  return DateFormat.yMMMd().format(parsed);
}

// Dedicated status-label keys (marriage_status_*) rather than reusing raw
// status.replaceAll('_',' ').tr — that pattern silently falls back to
// untranslated English everywhere since no such keys exist in
// app_translations.dart; this one actually resolves per-language.
String _statusLabel(String status) {
  final key = 'marriage_status_$status';
  final label = key.tr;
  return label == key ? status.replaceAll('_', ' ') : label;
}

Color _statusColor(String status) {
  return switch (status) {
    'active' => Colors.green,
    'matched' => Colors.teal,
    'rejected' => Colors.redAccent,
    'closed' => Colors.grey,
    'under_review' => Colors.orange,
    'paused' => Colors.amber,
    _ => Colors.indigo, // submitted
  };
}
