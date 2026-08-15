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
      fallback: 'Eligible case',
    );
    final needs = (caseItem['actual_needs'] ?? '').toString();
    // The review outcome. `review_notes` is the reviewer's own words — the
    // reason behind an approval or a rejection — and reviewed_by_name /
    // reviewed_at say who decided and when. None of it used to reach this
    // screen: the applicant saw "rejected" and nothing else, and the rejection
    // notification told them to go and ask support for the reason a member of
    // staff had already typed.
    final reviewNotes = (caseItem['review_notes'] ?? '').toString().trim();
    final reviewedBy = (caseItem['reviewed_by_name'] ?? '').toString().trim();
    final reviewedAt = localizedDate(caseItem['reviewed_at']);
    final hasReview =
        reviewNotes.isNotEmpty || reviewedBy.isNotEmpty || reviewedAt.isNotEmpty;

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
                        // Both are backend enums ('high', 'under_review',
                        // 'needs_changes'). _DetailLine only does `.tr`, which
                        // returns the key unchanged when there is no entry —
                        // so an Arabic user was reading "needs_changes" in a
                        // right-to-left UI. localizedTag is the app's single
                        // mechanism for exactly this.
                        _DetailLine(
                          icon: Icons.priority_high_rounded,
                          label: 'Priority',
                          value: localizedTag(caseItem['priority_level']),
                        ),
                        _DetailLine(
                          icon: Icons.verified_rounded,
                          label: 'Status',
                          value: localizedTag(caseItem['verification_status']),
                        ),
                      ],
                    ),
                  ),
                  // The decision, in its own panel directly under the summary
                  // — an applicant who has been refused should not have to
                  // read past nine rows of their own data to find out why.
                  if (hasReview) ...[
                    const SizedBox(height: 14),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'case_review_title'.tr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (reviewNotes.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            // Free text a reviewer typed, so it is shown as
                            // written — NOT through `.tr`, which would try to
                            // look a whole sentence up as a translation key.
                            Text(reviewNotes),
                          ],
                          _DetailLine(
                            icon: Icons.person_rounded,
                            label: 'case_reviewed_by',
                            value: reviewedBy,
                            translateValue: false,
                          ),
                          _DetailLine(
                            icon: Icons.event_rounded,
                            label: 'case_reviewed_at',
                            value: reviewedAt,
                            translateValue: false,
                          ),
                        ],
                      ),
                    ),
                  ],
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
    this.translateValue = true,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Whether to run the value through `.tr`.
  ///
  /// True for the enum-ish columns most rows carry (`housing_status`,
  /// `work_status`, …), where the value IS a translation key. False for
  /// content that only looks like one — a person's name, a formatted date —
  /// which must never be silently swapped for a translation because it
  /// happened to collide with a key.
  final bool translateValue;

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
                Text(translateValue ? value.tr : value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
