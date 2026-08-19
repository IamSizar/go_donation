import 'package:flutter/material.dart';

import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/marriage/controllers/marriage_my_profile_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/core/widgets/app_row.dart';

import 'package:flutter_application_1/modules/marriage/widgets/marriage_owner_actions.dart';

import 'marriage_field_privacy_screen.dart';
import 'marriage_form_screen.dart';

// Note #18 — shows the user their OWN submitted marriage profile and its
// review status (submitted/under_review/active/paused/matched/rejected/
// closed). Previously the app gave zero visibility after submitting — the
// user just got a one-time toast and had no way to check back. Mirrors
// BeneficiaryMyProjectsScreen's layout/pattern for consistency.
//
// Spec item 11 — this is now the SINGLE "my profile" entry in the marriage
// hub. It was one of two tiles sitting side by side, the other opening the
// submission form directly; the hub could not tell the two apart because it
// never fetches the profile, so it offered both to everyone regardless of
// state. This screen does fetch it, so it is the one place that can put the
// right action in front of the user: "create one" when there is no profile,
// and "submit a new one" when there is. The form stays a separate screen —
// it is ~1600 lines of field-rules-driven inputs and has nothing to gain
// from being inlined here.
//
// K14 — and it is now the one place the owner can ACT on the profile, not
// just look at it. Edit / stop showing / show again / remove live in
// MarriageOwnerActions, against the four owner-scoped routes commit 9f6ec79
// added. Until then this screen carried a written note that it deliberately
// avoided the word "edit" because POST /api/marriage only inserts another
// row; that note is gone because the reason for it is.
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
        // Three stacked `if` blocks replaced by AppAsync, which renders
        // exactly ONE state. The empty and error tiles here were SectionTiles
        // - the same card the app uses for navigation - so the error's retry
        // was an unlabelled onTap with nothing marking it as recoverable.
        return AppAsync<List<Map<String, dynamic>>>(
          // The gutter lives inside this screen's own list, so the skeleton
          // and the error banner would otherwise sit edge-to-edge while the
          // content that replaces them sits in a 20pt margin.
          gutter: const EdgeInsets.symmetric(horizontal: 20),
          loading: controller.isLoading.value,
          error: controller.errorMessage.value,
          onRetry: controller.fetchProfiles,
          data: items,
          isEmpty: (list) => list.isEmpty,
          // The empty state is where a first-time user lands, so it carries
          // the create action rather than just reporting that nothing is
          // here. AppAsync checks `error` before `isEmpty`, so a failed
          // fetch shows the retry banner and never this.
          empty: AppEmpty(
            title: 'marriage_my_profile_empty'.tr,
            message: 'marriage_my_profile_empty_desc'.tr,
            actionLabel: 'Create my profile',
            onAction: () => _openSubmissionForm(controller),
          ),
          builder: (list) => RefreshIndicator(
            onRefresh: controller.fetchProfiles,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                for (final item in list) ...[
                  _ProfileStatusCard(
                    item: item,
                    controller: controller,
                    onOpenPrivacy: () => _openFieldPrivacy(controller, item),
                  ),
                  const SizedBox(height: 14),
                ],
                _NewSubmissionCard(
                  onTap: () => _openSubmissionForm(controller),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// L19 — opens the per-field privacy picker for one profile, then refreshes so
/// the card reflects what was saved.
///
/// This screen is the only place the picker can live: the write is
/// POST /api/marriage/:id/privacy, so it needs a profile that already exists,
/// and the submission form has no id yet. The owner's current choices ride
/// along on the same GET /api/marriage/mine response that drew this card
/// (`field_privacy` is served to the owner and emptied for everybody else), so
/// the picker opens knowing them instead of defaulting to "nothing is hidden".
Future<void> _openFieldPrivacy(
  MarriageMyProfileController controller,
  Map<String, dynamic> item,
) async {
  final id = item['id'] is int
      ? item['id'] as int
      : int.tryParse(item['id']?.toString() ?? '');
  if (id == null || id <= 0) return;
  final raw = item['field_privacy'];
  final hidden = raw is List
      ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
      : <String>[];

  await Get.to(
    () => MarriageFieldPrivacyScreen(profileId: id, initialHidden: hidden),
  );
  await controller.fetchProfiles();
}

/// Opens the submission form, then refreshes the list on return.
///
/// The form pops back here after a successful submit (see
/// [MarriageFormScreen.openedFromStatusScreen]), but it can also be
/// abandoned with the back button — refreshing either way is cheap and
/// avoids the case where a just-submitted profile is missing until the user
/// pulls to refresh.
Future<void> _openSubmissionForm(MarriageMyProfileController controller) async {
  await Get.to(() => const MarriageFormScreen(openedFromStatusScreen: true));
  await controller.fetchProfiles();
}

/// The "submit another profile" affordance shown under the existing cards.
///
/// Still a NEW submission and not an edit — POST /api/marriage inserts a row
/// with a freshly generated profile_code, which is what this button does.
/// What changed with K14 is the caption: it used to send the reader to staff
/// for ANY change, because that was the only route there was. Editing is now
/// on the card above, so the caption points there and reserves staff for the
/// sections PATCH /api/marriage/:id does not accept.
class _NewSubmissionCard extends StatelessWidget {
  const _NewSubmissionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need to change something?'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'marriage_owner_new_submission_desc'.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Submit a new profile'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatusCard extends StatelessWidget {
  const _ProfileStatusCard({
    required this.item,
    required this.controller,
    required this.onOpenPrivacy,
  });

  final Map<String, dynamic> item;

  /// K14 — owns the four owner-scoped writes the action row fires.
  final MarriageMyProfileController controller;

  /// L19 — opens the per-field privacy picker for THIS profile.
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final code = (item['profile_code'] ?? '').toString();
    final status = (item['status'] ?? 'submitted').toString();
    final city = localizedCity(item['city']);
    final summary = (item['social_summary'] ?? '').toString();
    final createdAt = _dateLabel(item['created_at']);

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spec item 13 — the review status used to tint this mark as
              // well as fill the pill on the right of the same row: one
              // status, two renderings, side by side. The mark is now simply
              // the marriage section's icon in the accent colour, and the tag
              // is the single place the status is stated.
              TileIcon(
                icon: Icons.favorite_rounded,
                color: AppThemeConfig.accent(context),
              ),
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
              AppStatusTag(
                label: _statusLabel(status),
                tone: _statusTone(status),
              ),
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
          // L19 — the door to the per-field picker. On the card rather than in
          // the submission form because the write needs a profile that already
          // exists, and because this is where the owner comes to look at what
          // their profile says about them.
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenPrivacy,
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: Text('Field privacy'.tr),
            ),
          ),
          // K14 — the writes. Placed after the privacy door so the row reads
          // in escalating order: what it says about you, then what you can
          // change, then what removes it.
          const SizedBox(height: 10),
          MarriageOwnerActions(controller: controller, profile: item),
        ],
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

/// Maps a review status onto the design system's semantic tones.
///
/// Same three-way reading the bespoke colour switch had — settled / in flight
/// / needs attention — but expressed in tokens, so the tag matches every
/// other status word in the app. `closed` is neutral: it is an ended profile,
/// not a problem and not an achievement.
AppStatusTone _statusTone(String status) {
  return switch (status) {
    'active' || 'matched' => AppStatusTone.settled,
    'rejected' => AppStatusTone.attention,
    'closed' => AppStatusTone.neutral,
    'under_review' || 'paused' => AppStatusTone.pending,
    _ => AppStatusTone.settled, // submitted
  };
}
