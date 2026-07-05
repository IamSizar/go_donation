import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_campaign_donations_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class BeneficiaryCampaignDonationsScreen extends StatelessWidget {
  const BeneficiaryCampaignDonationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.isRegistered<BeneficiaryCampaignDonationsController>()
        ? Get.find<BeneficiaryCampaignDonationsController>()
        : Get.put(BeneficiaryCampaignDonationsController());

    return SectionScaffold(
      title: 'Campaign Contributions',
      subtitle: 'All donations received for your published campaigns.',
      child: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (ctrl.errorMessage.value != null) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SectionTile(
                icon: Icons.refresh_rounded,
                title: 'Campaign Contributions',
                subtitle: ctrl.errorMessage.value!,
                color: Colors.orange,
                onTap: ctrl.fetch,
              ),
            ],
          );
        }

        if (ctrl.campaigns.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SectionTile(
                icon: Icons.campaign_rounded,
                title: 'No campaigns yet',
                subtitle:
                    'Once your project request is approved and published, donations will appear here.',
                color: Colors.indigo,
              ),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: ctrl.fetch,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              // ── Summary band ───────────────────────────────────────
              _SummaryBand(ctrl: ctrl),
              const SizedBox(height: 16),

              // ── One card per campaign ───────────────────────────────
              for (final camp in ctrl.campaigns) ...[
                _CampaignDonationsCard(campaign: camp),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      }),
    );
  }
}

// ── Summary band ────────────────────────────────────────────────────────────

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.ctrl});
  final BeneficiaryCampaignDonationsController ctrl;

  @override
  Widget build(BuildContext context) {
    final totalDonations = ctrl.totalDonations;
    final totalRaised = ctrl.totalRaised;
    final campaigns = ctrl.campaigns.length;

    return GlassPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          InfoChip(
            icon: Icons.campaign_rounded,
            label: '$campaigns ${'campaigns'.tr}',
          ),
          InfoChip(
            icon: Icons.volunteer_activism_rounded,
            label: '$totalDonations ${'donations'.tr}',
          ),
          InfoChip(
            icon: Icons.savings_rounded,
            label: '${_fmtMoney(totalRaised)} IQD ${'raised'.tr}',
          ),
        ],
      ),
    );
  }
}

// ── Campaign card with donations list ───────────────────────────────────────

class _CampaignDonationsCard extends StatefulWidget {
  const _CampaignDonationsCard({required this.campaign});
  final Map<String, dynamic> campaign;

  @override
  State<_CampaignDonationsCard> createState() =>
      _CampaignDonationsCardState();
}

class _CampaignDonationsCardState extends State<_CampaignDonationsCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final camp = widget.campaign;
    final title = localizedContentFromMap(camp, 'title', fallback: 'Campaign');
    final donations = (camp['donations'] as List? ?? [])
        .map((d) => Map<String, dynamic>.from(d as Map))
        .toList();
    final goal = double.tryParse((camp['goal_amount'] ?? '0').toString()) ?? 0;
    final raised =
        double.tryParse((camp['raised_amount'] ?? '0').toString()) ?? 0;
    final pct = goal > 0 ? (raised / goal).clamp(0.0, 1.0) : 0.0;
    final status = (camp['status'] ?? 'active').toString();

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Campaign header ──────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppThemeConfig.primary.withValues(alpha: 0.25),
                              AppThemeConfig.primary.withValues(alpha: 0.10),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.campaign_rounded,
                          color: AppThemeConfig.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppThemeConfig.text(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                _StatusPill(status: status),
                                const SizedBox(width: 8),
                                Text(
                                  '${donations.length} ${'donations'.tr}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppThemeConfig.mutedText(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // ── Progress bar ──────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_fmtMoney(raised)} IQD ${'raised'.tr}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppThemeConfig.primary,
                                  ),
                                ),
                                Text(
                                  '${'goal'.tr}: ${_fmtMoney(goal)} IQD',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppThemeConfig.mutedText(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 6,
                                backgroundColor: AppThemeConfig.border(context),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppThemeConfig.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Donations list ───────────────────────────────────────
          if (_expanded) ...[
            Divider(
              height: 1,
              color: AppThemeConfig.border(context),
            ),
            if (donations.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.inbox_rounded,
                      color: AppThemeConfig.mutedText(context),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'No donations yet for this campaign.'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (int i = 0; i < donations.length; i++) ...[
                _DonationRow(
                  donation: donations[i],
                  campaignId: int.tryParse('${camp['id']}'),
                  campaignTitle: title,
                  isLast: i == donations.length - 1,
                ),
              ],
          ],
        ],
      ),
    );
  }
}

// ── Single donation row ──────────────────────────────────────────────────────

class _DonationRow extends StatelessWidget {
  const _DonationRow({
    required this.donation,
    required this.isLast,
    this.campaignId,
    this.campaignTitle,
  });

  final Map<String, dynamic> donation;
  final bool isLast;
  final int? campaignId;
  final String? campaignTitle;

  Future<void> _suggestChat(BuildContext context) async {
    final donorId = int.tryParse('${donation['donor_user_id']}');
    if (donorId == null || campaignId == null) return;
    final donorName = (donation['donor_name'] ?? 'this donor').toString().trim();
    await ChatActions.startChat(
      context,
      donorUserId: donorId,
      campaignId: campaignId,
      otherPartyLabel: donorName.isEmpty ? 'this donor' : donorName,
      conversationTitle: donorName.isEmpty ? 'Contributor' : donorName,
      conversationSubtitle: campaignTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount =
        double.tryParse((donation['amount'] ?? '0').toString()) ?? 0;
    final status = (donation['delivery_status'] ?? 'registered').toString();
    final method = (donation['payment_method'] ?? '').toString();
    final message = (donation['message'] ?? '').toString().trim();
    final donorName = (donation['donor_name'] ?? '').toString().trim();
    final donorPhone = (donation['donor_phone'] ?? '').toString().trim();
    final dateStr = (donation['transaction_date'] ?? '').toString();
    final date = _parseDate(dateStr);
    final statusColor = _donationStatusColor(status);
    final canChat = int.tryParse('${donation['donor_user_id']}') != null &&
        campaignId != null;

    return InkWell(
      onTap: canChat ? () => _suggestChat(context) : null,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppThemeConfig.border(context),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Donor avatar ────────────────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                donorName.isNotEmpty
                    ? donorName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.teal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Info ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        donorName.isNotEmpty
                            ? donorName
                            : 'Anonymous Donor'.tr,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                    ),
                    Text(
                      '${_fmtMoney(amount)} IQD',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppThemeConfig.primary,
                      ),
                    ),
                    if (canChat) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.forum_rounded, size: 16, color: AppThemeConfig.primary.withValues(alpha: 0.7)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (donorPhone.isNotEmpty) ...[
                      Icon(
                        Icons.phone_rounded,
                        size: 12,
                        color: AppThemeConfig.mutedText(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        donorPhone,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (method.isNotEmpty) ...[
                      Icon(
                        Icons.payment_rounded,
                        size: 12,
                        color: AppThemeConfig.mutedText(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        method,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // ── Status chip ────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        status.replaceAll('_', ' ').tr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (date != null)
                      Text(
                        DateFormat.yMMMd().format(date),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                  ],
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '"$message"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppThemeConfig.mutedText(context),
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

// ── Status pill (campaign) ───────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _campaignStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.tr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _fmtMoney(double amount) =>
    NumberFormat.decimalPattern().format(amount);

DateTime? _parseDate(String raw) {
  if (raw.isEmpty) return null;
  // The backend returns transaction_date as ISO text; strip trailing UTC offset if any.
  return DateTime.tryParse(raw.replaceAll(' ', 'T'));
}

Color _donationStatusColor(String s) {
  return switch (s) {
    'delivered' => Colors.green,
    'received' => Colors.teal,
    'under_review' => Colors.orange,
    'cancelled' => Colors.redAccent,
    _ => Colors.blueGrey,
  };
}

Color _campaignStatusColor(String s) {
  return switch (s) {
    'active' => Colors.green,
    'finished' => Colors.blueGrey,
    'hidden' => Colors.orange,
    _ => Colors.indigo,
  };
}
