import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class BeneficiaryCaseDetailScreen extends StatelessWidget {
  const BeneficiaryCaseDetailScreen({super.key, required this.caseItem});

  final Map<String, dynamic> caseItem;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      caseItem,
      'public_title',
      fallback: 'Recipient case',
    );
    final needs = (caseItem['actual_needs'] ?? '').toString();

    return GradientScreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: title),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                children: [
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.tr,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _DetailLine(
                          icon: Icons.qr_code_rounded,
                          label: 'Case code',
                          value: (caseItem['case_code'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.location_city_rounded,
                          label: 'City',
                          value: (caseItem['city'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.map_rounded,
                          label: 'District',
                          value: (caseItem['district'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.place_rounded,
                          label: 'Address',
                          value: (caseItem['address'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.family_restroom_rounded,
                          label: 'Family members',
                          value: (caseItem['family_members_count'] ?? '')
                              .toString(),
                        ),
                        _DetailLine(
                          icon: Icons.home_work_rounded,
                          label: 'Housing status',
                          value: (caseItem['housing_status'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.work_rounded,
                          label: 'Work status',
                          value: (caseItem['work_status'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.health_and_safety_rounded,
                          label: 'Health status',
                          value: (caseItem['health_status'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.school_rounded,
                          label: 'Education status',
                          value: (caseItem['education_status'] ?? '')
                              .toString(),
                        ),
                        _DetailLine(
                          icon: Icons.priority_high_rounded,
                          label: 'Priority',
                          value: (caseItem['priority_level'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.verified_rounded,
                          label: 'Status',
                          value: (caseItem['verification_status'] ?? '')
                              .toString(),
                        ),
                      ],
                    ),
                  ),
                  if (needs.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Actual needs'.tr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(needs.tr),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.tr,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(value.tr),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
