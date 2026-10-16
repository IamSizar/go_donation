// Step 1 of giving: "Make donation" → three ways to give (R2 #47, #53).
//
// ELECTRONIC PAYMENT IS NOT OFFERED. The client's list has a fourth way (cards
// and a gateway), but the app has no payment gateway: a card page could only
// record a "payment" nobody made. It comes back when a gateway exists (#48).
//
// WHY THIS SCREEN IS SO SHORT
// It used to be a long page — a hero, the featured campaigns, quick amounts, a
// summary card and a "why people choose this" card — followed by a second
// screen asking what KIND of donation it was, then a long checkout. The client
// called that cluttered and repetitive, and asked for two steps at most: this
// one (four plain options) and one fixed page per option.
//
// The campaigns list did not go away; it lives on [CampaignsScreen], reached
// from Home's "Featured campaigns". A campaign's own button comes back here
// with [initialCampaignId], and the gift is filed under that campaign.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/balance_transfer_contribution_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/cash_contribution_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/inkind_contribution_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

class DonationsSection extends StatelessWidget {
  const DonationsSection({super.key, this.initialCampaignId});

  /// Set when the donor arrived from a campaign. The gift is filed under it
  /// and the screen says so in one line.
  final int? initialCampaignId;

  void _open(Widget page) {
    AppHaptics.selection();
    Get.to<void>(() => page);
  }

  @override
  Widget build(BuildContext context) {
    // The campaign list is needed only to name the campaign; load it if the
    // donor came straight here (a notification, search) before Home did.
    if (initialCampaignId != null &&
        !Get.isRegistered<FeaturedCampaignsController>()) {
      Get.put(FeaturedCampaignsController());
    }
    final accent = AppThemeConfig.accent(context);
    final id = initialCampaignId;
    return AppScreen(
      // K28 — the AI icon for this section.
      assistantRoute: 'donate',
      title: 'Make donation',
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (id != null)
              Obx(() {
                final c = Get.isRegistered<FeaturedCampaignsController>()
                    ? Get.find<FeaturedCampaignsController>().campaigns
                          .firstWhereOrNull((x) => x.id == id)
                    : null;
                if (c == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_rounded, size: 20, color: accent),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          c.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: AppType.body,
                            color: AppThemeConfig.text(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            _WayTile(
              icon: Icons.smartphone_rounded,
              title: 'Balance transfer',
              onTap: () =>
                  _open(BalanceTransferContributionScreen(campaignsId: id)),
            ),
            const SizedBox(height: AppSpace.sm),
            _WayTile(
              icon: Icons.payments_rounded,
              title: 'Direct cash handover',
              onTap: () => _open(CashContributionScreen(campaignsId: id)),
            ),
            const SizedBox(height: AppSpace.sm),
            _WayTile(
              icon: Icons.inventory_2_rounded,
              title: 'In-kind contributions',
              // Goods are not filed under a campaign.
              onTap: () => _open(const InKindContributionScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// One way to give: an icon and a name. No sentence under it (R2 #53).
class _WayTile extends StatelessWidget {
  const _WayTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SectionTile(
      icon: icon,
      title: title,
      subtitle: '',
      color: AppThemeConfig.accent(context),
      onTap: onTap,
    );
  }
}

// Utility function for formatting numbers
String formatAmount(num amount) {
  // Falls back to en locale if the device locale cannot be determined
  return NumberFormat("#,##0", Intl.getCurrentLocale()).format(amount);
}

/// Soft, low-contrast chrome for featured cards (not bold / not saturated).
///
/// Resolves through the token layer rather than the two hardcoded blue-greys
/// this used to carry, so it tracks the palette instead of drifting from it.
Color _featuredCardSoftMist(BuildContext context) =>
    AppThemeConfig.borderStrong(context);

// task-3 — public (it was `_DonationFeaturedCampaignCard`) only so a
// widget test can pump it directly and assert what it renders, without
// standing up the network-backed DonationsSection screen; nothing else
// constructs it.
class DonationFeaturedCampaignCard extends StatelessWidget {
  const DonationFeaturedCampaignCard({
    super.key,
    required this.campaign,
    required this.isSelected,
    required this.onCardTap,
    required this.onDonatePressed,
  });

  final FeaturedCampaignData campaign;
  final bool isSelected;
  final VoidCallback onCardTap;
  final VoidCallback onDonatePressed;

  @override
  Widget build(BuildContext context) {
    final mist = _featuredCardSoftMist(context);
    final surface = AppThemeConfig.elevatedSurface(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          // Flat. This ramped from `surface` to `surface` tinted 4% — a step
          // far below the perceptual threshold, so it cost a gradient to
          // render something indistinguishable from a solid fill. The card's
          // selected state is carried by its border, which is visible.
          color: surface,
          border: Border.all(
            color: isSelected
                ? mist.withValues(alpha: 0.55)
                : AppThemeConfig.border(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppThemeConfig.shadow(context),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPressable(
              behavior: HitTestBehavior.opaque,
              onTap: onCardTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TileIcon(
                          icon: campaign.icon,
                          color: AppThemeConfig.accent(context),
                        ),
                        const SizedBox(width: 12),
                        // Card shows only the headline; the summary/description
                        // moved to CampaignDetailScreen (opened on tap) so the
                        // list stays scannable — see task-3-brief.md.
                        Expanded(
                          child: Text(
                            campaign.title,
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        _DonationTypeBadge(
                          label: campaign.category.trim().isNotEmpty
                              ? campaign.category
                              : 'Campaign'.tr,
                          color: mist,
                        ),
                      ],
                    ),
                    // A likes/comments row used to sit here; it's gone, but this
                    // single gap is what's left between the title and the
                    // location line — collapsed from two stacked spacers (14 +
                    // 16) that were sized to bracket a row which no longer
                    // exists, leaving a 30pt dead band for four short lines of
                    // content. 8 is the smallest step on the 4/8/12/16/24/32
                    // scale that still reads as a distinct gap between rows.
                    const SizedBox(height: 8),
                    Column(
                      children: [
                        _CampaignDetailLine(
                          icon: Icons.place_rounded,
                          label: campaign.location,
                          color: mist.withValues(alpha: 0.88),
                        ),
                        // The spacer is conditional too: the line below hides
                        // itself when it has nothing to say, and a gap left
                        // behind for an absent row is the same defect one
                        // pixel smaller.
                        if (campaign.impact.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _CampaignDetailLine(
                            icon: Icons.groups_rounded,
                            label: campaign.impact,
                            color: mist.withValues(alpha: 0.88),
                          ),
                        ],
                      ],
                    ),
                    // Gap before the progress bar, tightened from 16 to the
                    // 8pt floor used above the location line — the card is
                    // compact now, so every internal gap uses the smallest
                    // step on the 4/8/12/16/24/32 scale that still reads as a
                    // distinct section break.
                    const SizedBox(height: 8),
                    // The fill is the accent and the track a wash of it, which
                    // is what the identical bar on the Home card already does
                    // (widgets/dashboard.dart:1819). This one was drawing both
                    // halves from `mist` (borderStrong #CFC8B9) at two alphas —
                    // 0.5 for the fill over 0.12 for the track. Blended onto the
                    // white card that is #E7E4DC on #F9F8F7: a contrast of
                    // 1.2:1, against the 3:1 a non-text element needs to carry
                    // information.
                    //
                    // So the bar showed nothing. A campaign funded 100% and one
                    // funded 0% drew the same empty-looking strip, which is the
                    // one number a donor is scanning this card for. Found by
                    // looking at the screen: the 100% campaign's bar was bare.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        height: 8,
                        color: AppThemeConfig.accent(
                          context,
                        ).withValues(alpha: 0.14),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FractionallySizedBox(
                            widthFactor: campaign.fundedProgress,
                            child: Container(
                              color: AppThemeConfig.accent(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.trending_up_rounded,
                          size: 18,
                          color: AppThemeConfig.mutedText(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            campaign.fundingAmountsLine.isNotEmpty
                                ? '${campaign.fundedLabel} · ${campaign.fundingAmountsLine}'
                                : campaign.fundedLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppThemeConfig.mutedText(context),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Gap before the CTA, tightened from 18 (not on the spacing
            // scale) down to the 8pt floor — still a clear break from the
            // funded line above, without the extra dead band a
            // description-era card needed.
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDonatePressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: isSelected
                        ? AppThemeConfig.accent(context)
                        : AppThemeConfig.surface(context),
                    foregroundColor: isSelected
                        ? AppThemeConfig.onAccent(context)
                        : AppThemeConfig.text(context),
                    // 12pt vertical padding keeps the button's touch target
                    // at/above the 44pt minimum (12 + 12 + ~20pt text line).
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  // R2 #53 — one word, not «مساهمة لهذه الحملة».
                  child: Text(
                    isSelected ? 'Selected'.tr : 'Contribute'.tr,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignDetailLine extends StatelessWidget {
  const _CampaignDetailLine({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Nothing to say, nothing to draw. Both values this line renders are
    // optional: `impact` returns '' when a campaign records no affected count,
    // no community and no gender split, and `location` is empty when nobody
    // filled it in. Rendered unconditionally, that left a bare people-icon
    // floating on the card with empty space beside it — an icon captioning
    // nothing.
    //
    // The guard belongs here rather than at the two call sites because this
    // file already knows the rule and applies it in the other direction:
    // _DonationOptionData.fromCampaign filters exactly these two values with
    // `.where((value) => value.trim().isNotEmpty)` before joining them. One
    // half of the file dropped the empty ones and the other half drew them.
    //
    // Found by opening تبرّع and noticing an icon with nothing after it.
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _DonationTypeBadge extends StatelessWidget {
  const _DonationTypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.tr,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
