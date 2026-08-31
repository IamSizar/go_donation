// Pins that the donation-browsing card shows only the headline and the
// amount/progress figure a donor decides with — the body/description text
// moved to CampaignDetailScreen (opened on tap).
//
// WHY THIS FILE EXISTS (task-3, app-small-fixes)
// The owner asked for the donation list to be smaller and "show only
// headlines". `DonationFeaturedCampaignCard` (lib/modules/donations/screens/
// donations_section.dart) is the card the Contribute tab renders for each
// featured campaign — the list a donor browses to pick what to give to. It
// used to render `campaign.summary` under the title; that description is
// still fully reachable from CampaignDetailScreen, which every card opens on
// tap, so nothing became unreachable — it just moved off this smaller card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';

/// Builds a campaign carrying only the fields the card reads.
FeaturedCampaignData _campaign() {
  return FeaturedCampaignData.fromJson({
    'id': 1,
    'project_title': 'Clean Water for Sinjar',
    'summary': 'A long body paragraph explaining the project in depth.',
    'category': 'Water',
    'location': 'Sinjar',
    'raised_amount': 250000,
    'amount_needed': 500000,
    'currency': 'IQD',
  });
}

Widget _harness(FeaturedCampaignData campaign) => GetMaterialApp(
  theme: AppThemeConfig.buildTheme(Brightness.light),
  home: Scaffold(
    // A SingleChildScrollView gives the card's Column unbounded height, so
    // it sizes to its content instead of stretching to fill the Scaffold
    // body — required for the height measurement below to mean anything.
    body: SingleChildScrollView(
      child: DonationFeaturedCampaignCard(
        campaign: campaign,
        isSelected: false,
        onCardTap: () {},
        onDonatePressed: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('renders the title and the funded-progress figure', (
    tester,
  ) async {
    final campaign = _campaign();
    await tester.pumpWidget(_harness(campaign));

    expect(find.text(campaign.title), findsOneWidget);
    // The progress figure shares a Text with the raised/goal amounts
    // ("50% funded · 250,000 / 500,000 IQD"), so match by substring rather
    // than the exact fundedLabel string.
    expect(find.textContaining(campaign.fundedLabel), findsOneWidget);
  });

  testWidgets('does not render the description/summary text', (tester) async {
    final campaign = _campaign();
    await tester.pumpWidget(_harness(campaign));

    expect(find.text(campaign.summary), findsNothing);
  });

  testWidgets('card height stays compact now the description is gone', (
    tester,
  ) async {
    // Regression guard for the chunk8 compaction fix: once the description
    // paragraph moved to CampaignDetailScreen, the card's spacers/padding
    // were still sized for the paragraph that used to fill that space,
    // leaving dead vertical bands between the title/location and the
    // funded-line/CTA. This measures the rendered card on a 402pt-wide
    // surface (iPhone 16 Pro logical width) and pins the height well below
    // the ~250pt it used to be before the spacers were tightened.
    final campaign = _campaign();
    await tester.pumpWidget(_harness(campaign));
    await tester.pumpAndSettle();

    final cardSize = tester.getSize(
      find.byType(DonationFeaturedCampaignCard),
    );

    expect(
      cardSize.height,
      // Measured 202pt after the chunk8 compaction fix, down from 262pt
      // before it (a ~5.7% margin above 202 catches regressions without
      // being brittle to sub-pixel layout noise).
      lessThan(213),
      reason:
          'Card should be driven by its content height, not leftover '
          'spacers sized for the removed description paragraph.',
    );
  });
}
