import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';
import 'package:flutter_application_1/modules/donations/controllers/my_donations_controller.dart';
import 'package:flutter_application_1/modules/donations/models/donation_history_models.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_figure.dart';
import 'package:flutter_application_1/core/widgets/app_row.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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
    return Obx(() {
      final loading = _controller.isLoading.value;
      final err = _controller.errorMessage.value;
      final s = _controller.summary.value;
      final list = _controller.items;

      return AppScreen(
        eyebrow: '${s.totalCount} ${'gifts'.tr}',
        title: 'My Contributions',
        // padded: false so the RefreshIndicator's scrollable owns the full
        // width; the gutter is applied inside instead.
        padded: false,
        child: RefreshIndicator(
          onRefresh: _controller.fetchHistory,
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            // Scrolling dismisses the keyboard. The audit found this wired
            // nowhere in the app.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              // The headline figure and its counterweight. Delivered money
              // and money still in flight are shown separately rather than
              // folded into one flattering total — a donation stays
              // 'registered' until staff confirm it, and the pending count
              // is the number the donor can actually act on.
              AppFigure(
                label: 'Given so far',
                value: _numFormat.format(s.totalAmount.round()),
                unit: 'IQD',
                caption: '${s.totalCount} ${'contributions'.tr}',
              ),
              // K5 — this counter reads summary.success_count, which the
              // backend computes from payment_status. It was labelled
              // "Delivered", so a donor whose money had cleared but whose aid
              // had not moved was told it was delivered. The delivery answer
              // is per row, on the rule under each donation, because
              // /my_donations returns no delivery roll-up to count.
              AppStatPair(
                startValue: '${s.successCount}',
                startLabel: 'Confirmed',
                endValue: '${s.pendingCount}',
                endLabel: 'Awaiting confirmation',
                endTone: AppColors.of(context).pending,
              ),

              const AppSectionHeader(label: 'Recent donations'),

              // One switcher owns all four states, so none can be forgotten.
              AppAsync<List<DonationHistoryEntry>>(
                loading: loading,
                error: err,
                onRetry: _controller.fetchHistory,
                data: list,
                isEmpty: (items) => items.isEmpty,
                skeleton: AppSkeleton.rows(count: 4, withProgress: false),
                empty: const AppEmpty(
                  icon: Icons.volunteer_activism_rounded,
                  title: 'No gifts yet',
                  message:
                      'Every gift you make appears here with its reference '
                      'code and delivery status, so you always know where it '
                      'went.',
                ),
                builder: (items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _DonationRow(
                        item: items[i],
                        isLast: i == items.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Maps the donation's status to the design system's semantic tone.
///
/// Kept as a function rather than an extension on the model so the model
/// layer stays free of any dependency on the design system.
AppStatusTone _toneFor(DonationRecordStatus status) => switch (status) {
  DonationRecordStatus.success => AppStatusTone.settled,
  DonationRecordStatus.pending => AppStatusTone.pending,
  DonationRecordStatus.failed => AppStatusTone.attention,
};

/// The client's colour scheme for operation status, mapped onto the design
/// system's tones (K5): green when the aid has been delivered, red when the
/// family has received nothing, orange while it is in flight.
///
/// The four exits from the ladder — paused, suspended, archived, cancelled —
/// are `attention` rather than a ramp position: something stopped, and that is
/// worth a look regardless of how far it had got.
AppStatusTone _deliveryToneFor(DonationDeliveryStatus status) =>
    switch (status) {
      DonationDeliveryStatus.delivered => AppStatusTone.settled,
      DonationDeliveryStatus.received ||
      DonationDeliveryStatus.underReview => AppStatusTone.pending,
      DonationDeliveryStatus.registered ||
      DonationDeliveryStatus.paused ||
      DonationDeliveryStatus.suspended ||
      DonationDeliveryStatus.archived ||
      DonationDeliveryStatus.cancelled => AppStatusTone.attention,
    };

/// One donation, as a hairline-separated row.
///
/// Replaces the previous card, which carried its own 52pt tinted icon tile,
/// three info chips, a note and a full-width "View details" button — roughly
/// 120pt of height per donation. The row shows what a donor scans for
/// (campaign, amount, status, reference) and moves the rest into the detail
/// sheet that was already there.
class _DonationRow extends StatelessWidget {
  const _DonationRow({required this.item, required this.isLast});

  final DonationHistoryEntry item;
  final bool isLast;

  void _openDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DonationDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    // K5 — the coloured operation status the client asked for, on the one
    // number that actually measures it. The rule is drawn only when the server
    // sent a delivery_status we recognise AND that status is a step on the
    // ladder; a stopped donation still gets its word in the detail sheet, but
    // no invented position.
    final delivery = item.deliveryStatus;
    final deliveryProgress = delivery?.progress;

    return AppRow(
      title: item.campaignName,
      meta: '${item.reference} · ${item.dateLabel}',
      showDivider: !isLast,
      onTap: () => _openDetails(context),
      progress: deliveryProgress,
      progressTone: delivery == null
          ? AppStatusTone.neutral
          : _deliveryToneFor(delivery),
      // The word on one side, the number on the other, so the percentage can
      // never be read as "how much aid arrived" on its own.
      progressStart: delivery?.labelKey,
      progressEnd: deliveryProgress == null
          ? null
          : '${(deliveryProgress * 100).round()}%',
      // The trailing slot keeps PAYMENT status. Swapping it for delivery would
      // have hidden a failed payment behind a delivery word, which is the same
      // conflation in the other direction.
      trailing: AppRowAmount(
        amount: _numFormat.format(item.amount),
        status: item.status.label,
        tone: _toneFor(item.status),
      ),
    );
  }
}

class _DonationDetailSheet extends StatelessWidget {
  const _DonationDetailSheet({required this.item});

  final DonationHistoryEntry item;

  Future<void> _chatWithOwner(BuildContext context) async {
    Navigator.of(context).pop(); // close the sheet first
    await ChatActions.startChat(
      context,
      donationId: item.id,
      otherPartyLabel: 'the owner of "${item.campaignName}"',
      conversationTitle: item.campaignName,
      conversationSubtitle: 'Campaign owner'.tr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = item.status.color;
    final canChat = item.campaignId != null && item.id != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.mutedText(
                      context,
                    ).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                item.campaignName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_numFormat.format(item.amount)} IQD',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 16),
              // Two statuses, two questions, named apart. "Status" alone was
              // the payment one wearing a heading broad enough to be read as
              // either (K5).
              _DetailLine(label: 'Payment status', value: item.status.label),
              _DetailLine(
                label: 'Delivery status',
                // localizedTag rather than `.tr`: a value added server-side
                // before anyone translates it degrades to "Under review"
                // rather than printing `under_review` at the donor.
                value: item.deliveryStatus == null
                    ? '—'
                    : localizedTag(item.deliveryStatus!.labelKey),
              ),
              _DetailLine(label: 'Date', value: item.dateLabel),
              _DetailLine(
                label: 'Payment method',
                value: item.paymentMethod.isEmpty ? '—' : item.paymentMethod,
              ),
              _DetailLine(label: 'Reference', value: item.reference),
              if (item.note.trim().isNotEmpty && item.note != '—')
                _DetailLine(label: 'Message', value: item.note),
              const SizedBox(height: 18),
              if (canChat)
                FilledButton.icon(
                  onPressed: () => _chatWithOwner(context),
                  icon: const Icon(Icons.forum_rounded, size: 19),
                  label: Text('Chat with campaign owner'.tr),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    // Resolves per theme. Was a hardcoded copy of the old
                    // teal (#0F766E) that bypassed the theme entirely and so
                    // never adapted to dark mode.
                    backgroundColor: AppThemeConfig.accent(context),
                    foregroundColor: AppThemeConfig.onAccent(context),
                  ),
                )
              else
                Text(
                  'Chat is only available for campaign donations.'.tr,
                  style: TextStyle(
                    color: AppThemeConfig.mutedText(context),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
