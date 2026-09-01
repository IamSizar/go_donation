import 'package:flutter/material.dart';

import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/shared/widgets/operation_status_badge.dart';
import 'package:get/get.dart';

/// Full campaign details from the list API; opened when the user taps a featured card.
class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({super.key, required this.campaign});

  final FeaturedCampaignData campaign;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final accent = AppThemeConfig.accent(context);
    final summaryShort = c.summary.trim();
    final heroSummary = summaryShort.isNotEmpty
        ? summaryShort
        : c.descriptionLong;

    final hasLocationBlock =
        c.location.isNotEmpty ||
        c.beneficiaryCommunity.isNotEmpty ||
        c.peopleAffectedTotal > 0 ||
        c.maleCount > 0 ||
        c.femaleCount > 0;

    return GradientScreen(
      showBottomOrb: false,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: PageTopBar(title: 'Campaign details'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  _HeroSummaryCard(
                    campaign: c,
                    accent: accent,
                    summaryText: heroSummary,
                  ),
                  const SizedBox(height: 18),
                  if (c.descriptionLong.isNotEmpty &&
                      c.descriptionLong.trim() != heroSummary.trim()) ...[
                    _DetailSection(
                      title: 'About this project',
                      child: Text(
                        c.descriptionLong,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.55,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _DetailSection(
                    title: 'Funding',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          label: 'Goal',
                          value:
                              '${c.displayAmountNeeded} ${localizedCurrency(c.currency.trim().isEmpty ? 'IQD' : c.currency)}',
                        ),
                        _DetailRow(
                          label: 'Raised',
                          value:
                              '${c.displayRaisedAmount} ${localizedCurrency(c.currency.trim().isEmpty ? 'IQD' : c.currency)}',
                        ),
                        if (c.fundingAmountsLine.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              c.fundingAmountsLine,
                              style: TextStyle(
                                color: AppThemeConfig.mutedText(context),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        // Spec item 13 — a LinearProgressIndicator of
                        // c.fundedProgress used to sit here, drawing the exact
                        // same fraction the hero pill states as a percentage
                        // and a word, on the same scroll. The Goal and Raised
                        // rows above already give the amounts behind it, so
                        // the bar was the third rendering of one status and is
                        // gone; the pill is the one that says it in words.
                      ],
                    ),
                  ),
                  if (hasLocationBlock) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Location & community',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            label: 'Location',
                            value: c.location,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'Beneficiary community'.tr,
                            value: c.beneficiaryCommunity,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'People affected',
                            value: c.peopleAffectedTotal > 0
                                ? '@n people'.trParams({
                                    'n': '${c.peopleAffectedTotal}',
                                  })
                                : '',
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'Men / women',
                            value: (c.maleCount > 0 || c.femaleCount > 0)
                                ? '@m men · @f women'.trParams({
                                    'm': '${c.maleCount}',
                                    'f': '${c.femaleCount}',
                                  })
                                : '',
                            hideIfEmpty: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_hasVolunteerBlock(c)) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Volunteers',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            label: 'Age profile',
                            value: c.volunteerAgeProfile,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'Skills & knowledge',
                            value: c.volunteerSkillsKnowledge,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'How volunteers help',
                            value: c.volunteersExtraDescription,
                            hideIfEmpty: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (c.timelineTarget.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Timeline',
                      child: Text(
                        c.timelineTarget,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (_hasContactBlock(c)) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Contact',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            label: 'Contact person',
                            value: c.contactPersonName,
                            hideIfEmpty: true,
                          ),
                          if (c.contactPhone.trim().isNotEmpty)
                            _SelectableDetailRow(
                              label: 'Phone',
                              value: c.contactPhone.trim(),
                            ),
                          if (c.contactEmail.trim().isNotEmpty)
                            _SelectableDetailRow(
                              label: 'Email',
                              value: c.contactEmail.trim(),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (c.otherNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Notes',
                      child: Text(
                        c.otherNotes,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: 'Status & activity',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          label: 'Status',
                          value: c.status.trim().isNotEmpty ? c.status : '—',
                        ),
                        _DetailRow(label: 'Likes', value: '${c.likeCount}'),
                        _DetailRow(
                          label: 'Comments',
                          value: '${c.commentCount}',
                        ),
                        if (c.userId > 0)
                          _DetailRow(
                            label: 'Organizer user ID',
                            value: '${c.userId}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
            // EVERY signed-in role sees this, not only role 1.
            //
            // It used to read `if (role_id == '1')`, so a volunteer or an
            // eligible recipient opening a campaign got the whole page —
            // funding, location, timeline, contact — and no way to give. The
            // client's report was exactly that: "when I tap on a campaign I
            // want to see a button here to donate", from an account that had
            // one hidden from it.
            //
            // Nothing was enforcing the restriction anyway. POST /donations
            // checks that the caller is signed in and not a guest, and says
            // nothing about role, so the gate was a UI opinion rather than a
            // rule — and one no screen stated, since the button simply was
            // not there. Guests are still handled: this pops back to the
            // donate flow, whose own action runs the upgrade prompt (#44 /
            // Note #40) before anything is charged.
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: () {
                    AppHaptics.success();
                    Get.back(result: true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: AppThemeConfig.onAccent(context),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text('Donate to this campaign'.tr),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _hasVolunteerBlock(FeaturedCampaignData c) {
    return c.volunteerAgeProfile.isNotEmpty ||
        c.volunteerSkillsKnowledge.isNotEmpty ||
        c.volunteersExtraDescription.isNotEmpty;
  }

  static bool _hasContactBlock(FeaturedCampaignData c) {
    return c.contactPersonName.isNotEmpty ||
        c.contactPhone.trim().isNotEmpty ||
        c.contactEmail.trim().isNotEmpty;
  }
}

class _HeroSummaryCard extends StatelessWidget {
  const _HeroSummaryCard({
    required this.campaign,
    required this.accent,
    required this.summaryText,
  });

  final FeaturedCampaignData campaign;
  final Color accent;
  final String summaryText;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        // A flat, faintly accented surface. The 3-stop version washed an 18%
        // accent across the middle of the card, which fought the text sitting
        // on top of it for contrast.
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.06),
          AppThemeConfig.elevatedSurface(context),
        ),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileIcon(icon: c.icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Spec item 13 — this was OperationStatusBadge, a
                        // coloured disc whose state ("delivered in full" /
                        // "partially received" / "not received yet") lived
                        // only in a tooltip, so on screen the meaning was
                        // carried by the colour alone. The pill variant of the
                        // same shared badge shows the percentage AND the word,
                        // which survives greyscale and colour-blindness.
                        // K5 — `fundedProgress` is money raised ÷ goal, so the
                        // pill must say funding. It previously read
                        // "Complete" / "Not received", which is a claim about
                        // delivery that this number cannot support.
                        OperationStatusPill(
                          progress: c.fundedProgress,
                          kind: OperationStatusKind.funding,
                        ),
                      ],
                    ),
                    if (c.category.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          c.category,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summaryText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              summaryText,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.5,
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.hideIfEmpty = false,
  });

  final String label;
  final String value;
  final bool hideIfEmpty;

  @override
  Widget build(BuildContext context) {
    if (hideIfEmpty && value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableDetailRow extends StatelessWidget {
  const _SelectableDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
