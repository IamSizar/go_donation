import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/campaign_detail_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/continue_donation_screen.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:intl/intl.dart'; // Added for number formatting

class DonationsSection extends StatelessWidget {
  const DonationsSection({super.key});

  static const List<_DonationOptionData> _options = [
    _DonationOptionData(
      title: 'Comprehensive Giving',
      summary:
          'One simple donation that can be used wherever support is needed most.',
      typeLabel: 'One-time',
      supportNote: 'A flexible way to help the most urgent needs right away.',
      icon: Icons.all_inclusive,
      color: Colors.teal,
    ),
  ];

  static const List<int> _quickAmounts = [10000, 20000, 50000, 100000];

  @override
  Widget build(BuildContext context) {
    return _DonationsSectionBody();
  }
}

// Utility function for formatting numbers
String formatAmount(num amount) {
  // Falls back to en locale if the device locale cannot be determined
  return NumberFormat("#,##0", Intl.getCurrentLocale()).format(amount);
}

class _DonationsSectionBody extends StatefulWidget {
  const _DonationsSectionBody();

  @override
  State<_DonationsSectionBody> createState() => _DonationsSectionBodyState();
}

class _DonationsSectionBodyState extends State<_DonationsSectionBody> {
  int _selectedAmount = DonationsSection._quickAmounts[1];
  int? _selectedCampaignId;
  String _selectedPaymentMethod = '';
  final List<String> _paymentMethods = [];
  String? donorName;

  final ScrollController _listScrollController = ScrollController();
  final GlobalKey _quickAmountKey = GlobalKey();

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  FeaturedCampaignData? _findSelectedCampaign(
    List<FeaturedCampaignData> campaigns,
  ) {
    if (_selectedCampaignId == null) return null;
    for (final campaign in campaigns) {
      if (campaign.id == _selectedCampaignId) {
        return campaign;
      }
    }
    return null;
  }

  void _resetDonationSelectionToDefaults() {
    setState(() {
      _selectedAmount = DonationsSection._quickAmounts[1];
      _selectedCampaignId = null;
      _selectedPaymentMethod = '';
    });
  }

  // #18 — "Give Now": jump straight into comprehensive (unrestricted) giving.
  // Select it (campaign = null) and scroll the donor to the amount picker so
  // they can complete a general donation fast.
  void _giveNow() {
    AppHaptics.selection();
    setState(() => _selectedCampaignId = null);
    _scrollToQuickAmount();
  }

  void _scrollToQuickAmount({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetContext = _quickAmountKey.currentContext;
        if (targetContext == null || !targetContext.mounted) return;

        Scrollable.ensureVisible(
          targetContext,
          duration: animated
              ? const Duration(milliseconds: 400)
              : Duration.zero,
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final campaignsController = Get.isRegistered<FeaturedCampaignsController>()
        ? Get.find<FeaturedCampaignsController>()
        : Get.put(FeaturedCampaignsController());
    final selectedCampaign = _findSelectedCampaign(
      campaignsController.campaigns,
    );
    final selectedOption = selectedCampaign != null
        ? _DonationOptionData.fromCampaign(selectedCampaign)
        : DonationsSection._options.first;

    return SectionScaffold(
      title: 'Contribute',
      subtitle:
          'Choose an amount, pick general support or a featured campaign, and make your support count.',
      trailing: GestureDetector(
        onTap: () => Get.to(() => const MyDonationsPage()),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal[600]!, Colors.teal[300]!],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withValues(alpha: 0.13),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 7),
              Text(
                'See all'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white60,
                size: 16,
              ),
            ],
          ),
        ),
      ),
      child: RefreshIndicator(
        onRefresh: campaignsController.refreshCampaigns,
        child: SingleChildScrollView(
          controller: _listScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GiveNowCard(onTap: _giveNow),
              const SizedBox(height: 20),
              const SectionLabel(title: 'Featured campaigns'),
              const SizedBox(height: 12),
              Obx(() {
                if (campaignsController.isLoading.value) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (campaignsController.errorMessage.value != null) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GlassPanel(
                      child: Column(
                        children: [
                          Text(
                            campaignsController.errorMessage.value!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: campaignsController.refreshCampaigns,
                            child: Text('Retry'.tr),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (campaignsController.campaigns.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      'No campaigns available.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  );
                }
                return Column(
                  children: campaignsController.campaigns
                      .map(
                        (campaign) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _DonationFeaturedCampaignCard(
                            campaign: campaign,
                            isSelected: campaign.id == _selectedCampaignId,
                            onCardTap: () {
                              Get.to(
                                () => CampaignDetailScreen(campaign: campaign),
                              )?.then((donate) {
                                if (!mounted) return;
                                if (donate == true) {
                                  setState(
                                    () => _selectedCampaignId = campaign.id,
                                  );
                                  _scrollToQuickAmount(animated: true);
                                }
                              });
                            },
                            // #44 / Note #40 — donating is a "purchase", so
                            // guests are prompted to upgrade their account
                            // before acting (also enforced server-side).
                            onDonatePressed: () async {
                              if (!await requireUpgrade(context)) return;
                              AppHaptics.selection();
                              setState(() => _selectedCampaignId = campaign.id);
                              _scrollToQuickAmount(animated: true);
                            },
                          ),
                        ),
                      )
                      .toList(),
                );
              }),
              const SizedBox(height: 22),
              const SectionLabel(title: 'Quick amount', key: null),
              const SizedBox(height: 12),
              Container(
                key: _quickAmountKey,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: DonationsSection._quickAmounts.map((amount) {
                    final isSelected = amount == _selectedAmount;
                    return _DonationAmountChip(
                      label: '${formatAmount(amount)} IQD',
                      isSelected: isSelected,
                      onTap: () {
                        AppHaptics.selection();
                        setState(() => _selectedAmount = amount);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 22),
              const SectionLabel(title: 'Payment method'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: _paymentMethods.map((method) {
                  final isSelected = _selectedPaymentMethod == method;
                  return ChoiceChip(
                    label: Text(method),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        AppHaptics.selection();
                        setState(() {
                          _selectedPaymentMethod = method;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              _SelectedDonationCard(
                option: selectedOption,
                selectedAmount: _selectedAmount,
                paymentMethod: _selectedPaymentMethod,
                onContinue: () {
                  AppHaptics.selection();
                  Get.to(
                    () => ContinueDonationScreen(
                      amount: _selectedAmount,
                      campaignsId: _selectedCampaignId,
                      optionTitle: selectedOption.title,
                      optionSummary: selectedOption.summary,
                      optionTypeLabel: selectedOption.typeLabel,
                      optionSupportNote: selectedOption.supportNote,
                      optionIcon: selectedOption.icon,
                      optionColor: selectedOption.color,
                      paymentMethod: _selectedPaymentMethod,
                    ),
                  )?.then((submitted) {
                    if (!mounted) return;
                    if (submitted == true) {
                      _resetDonationSelectionToDefaults();
                    }
                  });
                },
                donorName: donorName,
              ),
              const SizedBox(height: 22),
              const SectionLabel(title: 'Comprehensive Giving'),
              const SizedBox(height: 12),
              _DonationOptionCard(
                option: DonationsSection._options.first,
                isSelected: _selectedCampaignId == null,
                onTap: () {
                  AppHaptics.selection();
                  setState(() => _selectedCampaignId = null);
                },
              ),
              const _SimpleDonationInfoCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// #18 — prominent "Give Now" hero CTA at the top of the Contribute tab: a fast
// entry into comprehensive (unrestricted) giving.
class _GiveNowCard extends StatelessWidget {
  const _GiveNowCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.all_inclusive,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Give Now'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DonationsSection._options.first.summary.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonationOptionData {
  const _DonationOptionData({
    required this.title,
    required this.summary,
    required this.typeLabel,
    required this.supportNote,
    required this.icon,
    required this.color,
  });

  factory _DonationOptionData.fromCampaign(FeaturedCampaignData campaign) {
    final details = [
      campaign.location,
      campaign.impact,
    ].where((value) => value.trim().isNotEmpty).join(' • ');

    return _DonationOptionData(
      title: campaign.title,
      summary: campaign.summary,
      typeLabel: campaign.category.trim().isNotEmpty
          ? campaign.category
          : 'Campaign'.tr,
      supportNote: details.isNotEmpty ? details : campaign.fundedLabel,
      icon: campaign.icon,
      color: campaign.color,
    );
  }

  final String title;
  final String summary;
  final String typeLabel;
  final String supportNote;
  final IconData icon;
  final Color color;
}

/// Soft, low-contrast chrome for featured cards (not bold / not saturated).
Color _featuredCardSoftMist(BuildContext context) =>
    AppThemeConfig.isDark(context)
    ? const Color(0xFF8B95A8)
    : const Color(0xFFB4BDC8);

class _DonationFeaturedCampaignCard extends StatelessWidget {
  const _DonationFeaturedCampaignCard({
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
          gradient: LinearGradient(
            colors: [
              surface,
              Color.alphaBlend(
                mist.withValues(
                  alpha: AppThemeConfig.isDark(context) ? 0.05 : 0.04,
                ),
                surface,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCardTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TileIcon(icon: campaign.icon, color: campaign.color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                campaign.title,
                                style: TextStyle(
                                  color: AppThemeConfig.text(context),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                campaign.summary,
                                style: TextStyle(
                                  color: AppThemeConfig.mutedText(context),
                                  height: 1.5,
                                ),
                              ),
                            ],
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
                    const SizedBox(height: 14),
                    // Likes/comments row removed
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        _CampaignDetailLine(
                          icon: Icons.place_rounded,
                          label: campaign.location,
                          color: mist.withValues(alpha: 0.88),
                        ),
                        const SizedBox(height: 10),
                        _CampaignDetailLine(
                          icon: Icons.groups_rounded,
                          label: campaign.impact,
                          color: mist.withValues(alpha: 0.88),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        height: 8,
                        color: mist.withValues(alpha: 0.12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: campaign.fundedProgress,
                            child: Container(
                              color: mist.withValues(alpha: 0.5),
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
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDonatePressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: isSelected
                        ? campaign.color
                        : AppThemeConfig.surface(context),
                    foregroundColor: isSelected
                        ? Colors.white
                        : AppThemeConfig.text(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isSelected
                        ? 'Selected for donation'.tr
                        : 'Donate to this campaign'.tr,
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

class _DonationAmountChip extends StatelessWidget {
  const _DonationAmountChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0F766E)
              : AppThemeConfig.surface(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0F766E)
                : AppThemeConfig.border(context),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppThemeConfig.text(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SelectedDonationCard extends StatelessWidget {
  const _SelectedDonationCard({
    required this.option,
    required this.selectedAmount,
    required this.paymentMethod,
    required this.onContinue,
    this.donorName,
  });

  final _DonationOptionData option;
  final int selectedAmount;
  final String paymentMethod;
  final VoidCallback onContinue;
  final String? donorName;

  @override
  Widget build(BuildContext context) {
    final showDonorDetails = (donorName ?? '').isEmpty;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            AppThemeConfig.elevatedSurface(context),
            option.color.withValues(alpha: 0.20),
            option.color.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: option.color.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TileIcon(icon: option.icon, color: option.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current selection'.tr,
                      style: TextStyle(
                        color: option.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.title.tr,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              _DonationTypeBadge(label: option.typeLabel, color: option.color),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            option.summary.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.55,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DonationInfoPill(
                icon: Icons.payments_rounded,
                label: 'Amount: @amount IQD'.trParams({
                  'amount': formatAmount(selectedAmount),
                }),
              ),
              _DonationInfoPill(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Payment: @method'.trParams({
                  'method': paymentMethod.tr,
                }),
              ),
              const _DonationInfoPill(
                icon: Icons.favorite_border_rounded,
                label: 'Easy giving',
              ),
              const _DonationInfoPill(
                icon: Icons.check_circle_rounded,
                label: 'Simple checkout',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            option.supportNote.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          if (showDonorDetails)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.favorite_rounded),
                label: Text('Continue donation'.tr),
                style: FilledButton.styleFrom(
                  backgroundColor: option.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DonationOptionCard extends StatelessWidget {
  const _DonationOptionCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _DonationOptionData option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileIcon(icon: option.icon, color: option.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.title.tr,
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const _DonationTypeBadge(
                            label: 'Selected',
                            color: Color(0xFF0F766E),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      option.summary.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DonationInfoPill(
                icon: Icons.label_rounded,
                label: option.typeLabel,
              ),
              const _DonationInfoPill(
                icon: Icons.volunteer_activism_rounded,
                label: 'Made to help',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            option.supportNote.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: isSelected
                    ? option.color
                    : AppThemeConfig.surface(context),
                foregroundColor: isSelected
                    ? Colors.white
                    : AppThemeConfig.text(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                isSelected ? 'Selected option'.tr : 'Choose option'.tr,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonationInfoPill extends StatelessWidget {
  const _DonationInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppThemeConfig.mutedText(context)),
          const SizedBox(width: 8),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

class _SimpleDonationInfoCard extends StatelessWidget {
  const _SimpleDonationInfoCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why people choose this'.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A clean donation flow helps supporters act quickly and stay focused on helping others.'
                .tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StaticDonationFieldChip(label: 'Fast to choose'),
              _StaticDonationFieldChip(label: 'Clear options'),
              _StaticDonationFieldChip(label: 'Trusted feeling'),
              _StaticDonationFieldChip(label: 'Simple checkout'),
              _StaticDonationFieldChip(label: 'Featured campaigns'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaticDonationFieldChip extends StatelessWidget {
  const _StaticDonationFieldChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppThemeConfig.text(context),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
