import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/donations/controllers/my_donations_controller.dart';
import 'package:flutter_application_1/modules/donations/models/donation_history_models.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

const Color _donationHistoryPrimary = Color(0xFF0F766E);

final NumberFormat _numFormat = NumberFormat.decimalPattern();

class MyDonationsPage extends StatefulWidget {
  const MyDonationsPage({super.key});

  @override
  State<MyDonationsPage> createState() => _MyDonationsPageState();
}

class _MyDonationsPageState extends State<MyDonationsPage> {
  late final MyDonationsController _controller;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<MyDonationsController>()) {
      Get.delete<MyDonationsController>();
    }
    _controller = Get.put(MyDonationsController());
  }

  @override
  void dispose() {
    if (Get.isRegistered<MyDonationsController>()) {
      Get.delete<MyDonationsController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: 'My Donations'),
            ),
            Expanded(
              child: Obx(() {
                final loading = _controller.isLoading.value;
                final err = _controller.errorMessage.value;
                final s = _controller.summary.value;
                final list = _controller.items;

                if (loading && list.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return RefreshIndicator(
                  onRefresh: _controller.fetchHistory,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      if (err != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: GlassPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  err,
                                  style: TextStyle(
                                    color: AppThemeConfig.text(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _controller.fetchHistory,
                                  child: Text('Retry'.tr),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _DonationHistoryHeroCard(
                        totalAmount: s.totalAmount.round(),
                        campaignCount: s.totalCount,
                        successCount: s.successCount,
                        pendingCount: s.pendingCount,
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Donation status'),
                      const SizedBox(height: 12),
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            _StatusLegendChip(
                              status: DonationRecordStatus.success,
                              count: s.successCount,
                            ),
                            _StatusLegendChip(
                              status: DonationRecordStatus.pending,
                              count: s.pendingCount,
                            ),
                            _StatusLegendChip(
                              status: DonationRecordStatus.failed,
                              count: s.failedCount,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Recent donations'),
                      const SizedBox(height: 12),
                      if (list.isEmpty && err == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No donations yet.'.tr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppThemeConfig.mutedText(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        ...list.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _DonationHistoryCard(item: item),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationHistoryHeroCard extends StatelessWidget {
  const _DonationHistoryHeroCard({
    required this.totalAmount,
    required this.campaignCount,
    required this.successCount,
    required this.pendingCount,
  });

  final int totalAmount;
  final int campaignCount;
  final int successCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0EA5A4), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: _donationHistoryPrimary.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Donation history'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${_numFormat.format(totalAmount)} IQD',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A simple record of every campaign donation with a clear status for pending, success, or failed payments.'
                .tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              height: 1.5,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroMetric(
                label: 'Campaigns',
                value: _numFormat.format(campaignCount),
              ),
              _HeroMetric(
                label: 'Success',
                value: _numFormat.format(successCount),
              ),
              _HeroMetric(
                label: 'Pending',
                value: _numFormat.format(pendingCount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonationHistoryCard extends StatelessWidget {
  const _DonationHistoryCard({required this.item});

  final DonationHistoryEntry item;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.status.color;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.volunteer_activism_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.campaignName,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_numFormat.format(item.amount)} IQD',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(
                icon: Icons.calendar_today_rounded,
                label: item.dateLabel,
              ),
              _InfoChip(
                icon: Icons.credit_card_rounded,
                label: item.paymentMethod.isEmpty ? '—' : item.paymentMethod,
              ),
              _InfoChip(
                icon: Icons.receipt_long_rounded,
                label: item.reference,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            item.note,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeConfig.softSurface(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppThemeConfig.mutedText(context)),
          const SizedBox(width: 8),
          Text(
            label,
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

class _StatusLegendChip extends StatelessWidget {
  const _StatusLegendChip({required this.status, required this.count});

  final DonationRecordStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 16, color: status.color),
          const SizedBox(width: 8),
          Text(
            status.label.tr,
            style: TextStyle(color: status.color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            '(${_numFormat.format(count)})',
            style: TextStyle(
              color: status.color.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DonationRecordStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label.tr,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
