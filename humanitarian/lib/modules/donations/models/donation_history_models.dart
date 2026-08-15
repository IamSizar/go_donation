import 'package:flutter/material.dart';

/// Matches PHP `summary` / `stats` object.
class DonationHistorySummary {
  const DonationHistorySummary({
    required this.totalCount,
    required this.totalAmount,
    required this.successCount,
    required this.successAmount,
    required this.pendingCount,
    required this.pendingAmount,
    required this.failedCount,
    required this.failedAmount,
  });

  final int totalCount;
  final double totalAmount;
  final int successCount;
  final double successAmount;
  final int pendingCount;
  final double pendingAmount;
  final int failedCount;
  final double failedAmount;

  static const DonationHistorySummary empty = DonationHistorySummary(
    totalCount: 0,
    totalAmount: 0,
    successCount: 0,
    successAmount: 0,
    pendingCount: 0,
    pendingAmount: 0,
    failedCount: 0,
    failedAmount: 0,
  );

  factory DonationHistorySummary.fromJson(Map json) {
    int i(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    double d(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    return DonationHistorySummary(
      totalCount: i(json['total_count']),
      totalAmount: d(json['total_amount']),
      successCount: i(json['success_count']),
      successAmount: d(json['success_amount']),
      pendingCount: i(json['pending_count']),
      pendingAmount: d(json['pending_amount']),
      failedCount: i(json['failed_count']),
      failedAmount: d(json['failed_amount']),
    );
  }
}

enum DonationRecordStatus { success, pending, failed }

/// Parses row status. Numeric codes (API / DB): **1 = success**, **2 = pending**, **3 = failed**.
DonationRecordStatus donationRecordStatusFromApi(dynamic value) {
  if (value == null) {
    return DonationRecordStatus.pending;
  }

  if (value is bool) {
    return value ? DonationRecordStatus.success : DonationRecordStatus.pending;
  }

  if (value is num) {
    final n = value.toInt();
    if (n == 1) return DonationRecordStatus.success;
    if (n == 2) return DonationRecordStatus.pending;
    if (n == 3) return DonationRecordStatus.failed;
    return DonationRecordStatus.pending;
  }

  var s = value.toString().toLowerCase().trim();

  // Stringified numbers from JSON / form data
  if (s == '1') return DonationRecordStatus.success;
  if (s == '2') return DonationRecordStatus.pending;
  if (s == '3') return DonationRecordStatus.failed;

  s = s.replaceAll(RegExp(r'\s+'), ' ');
  if ([
    'success',
    'completed',
    'paid',
    'complete',
    'verified',
    'approved',
    'confirmed',
  ].contains(s)) {
    return DonationRecordStatus.success;
  }
  if ([
    'failed',
    'fail',
    'cancelled',
    'canceled',
    'rejected',
    'declined',
  ].contains(s)) {
    return DonationRecordStatus.failed;
  }
  if ([
    'pending',
    'processing',
    'waiting',
    'in_progress',
    'submitted',
  ].contains(s)) {
    return DonationRecordStatus.pending;
  }
  return DonationRecordStatus.pending;
}

/// `donations.delivery_status` — where the aid itself has got to.
///
/// WHY THIS EXISTS (K5)
/// A donation carries TWO statuses and they answer different questions.
/// `payment_status` says whether the money cleared; `delivery_status` says
/// whether anything reached the family. The app parsed only the first, showed
/// it under the heading "Status", and told the donor in its own empty state
/// that every gift appears "with its reference code and delivery status" — so
/// the one thing the client asked to see was the one thing never read off the
/// wire, even though /api/donate/my_donations has always returned it.
///
/// The eight values are the CHECK constraint from migration 050, not a guess:
///   registered · received · under_review · delivered ·
///   paused · suspended · archived · cancelled
enum DonationDeliveryStatus {
  registered,
  received,
  underReview,
  delivered,
  paused,
  suspended,
  archived,
  cancelled,
}

/// Parses `delivery_status`, or returns null when the server sent nothing we
/// recognise.
///
/// NULL RATHER THAN A DEFAULT, DELIBERATELY. Falling back to `registered`
/// would paint a red "nothing has been delivered" indicator on a donation
/// whose state we do not actually know — a claim invented out of a missing
/// field, which is the same class of bug this whole row exists to remove. The
/// caller hides the indicator instead.
DonationDeliveryStatus? donationDeliveryStatusFromApi(dynamic value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  if (raw.isEmpty) return null;
  return switch (raw) {
    'registered' => DonationDeliveryStatus.registered,
    'received' => DonationDeliveryStatus.received,
    'under_review' => DonationDeliveryStatus.underReview,
    'delivered' => DonationDeliveryStatus.delivered,
    'paused' => DonationDeliveryStatus.paused,
    'suspended' => DonationDeliveryStatus.suspended,
    'archived' => DonationDeliveryStatus.archived,
    'cancelled' => DonationDeliveryStatus.cancelled,
    _ => null,
  };
}

extension DonationDeliveryStatusUi on DonationDeliveryStatus {
  /// The translation key. These are the BARE backend tokens, matching how the
  /// rest of the app keys server enums (see the `under_review` / `archived`
  /// block in app_translations.dart) so `localizedTag` resolves them too.
  String get labelKey => switch (this) {
    DonationDeliveryStatus.registered => 'registered',
    DonationDeliveryStatus.received => 'received',
    DonationDeliveryStatus.underReview => 'under_review',
    DonationDeliveryStatus.delivered => 'delivered',
    DonationDeliveryStatus.paused => 'paused',
    DonationDeliveryStatus.suspended => 'suspended',
    DonationDeliveryStatus.archived => 'archived',
    DonationDeliveryStatus.cancelled => 'cancelled',
  };

  /// Position on the delivery ladder, 0.0 .. 1.0 — or null when the donation
  /// is not on the ladder at all.
  ///
  /// The ladder is the order the backend itself moves a donation through:
  /// registered → received → under_review → delivered. The fractions are that
  /// POSITION, and the label beside them always names the step, so the number
  /// is never left to stand for "how much aid arrived" on its own.
  ///
  /// Paused, suspended, archived and cancelled are not steps toward delivery —
  /// they are exits from it. Giving them a percentage would be inventing one,
  /// so they get a word and no rule.
  double? get progress => switch (this) {
    DonationDeliveryStatus.registered => 0.0,
    DonationDeliveryStatus.received => 1 / 3,
    DonationDeliveryStatus.underReview => 2 / 3,
    DonationDeliveryStatus.delivered => 1.0,
    DonationDeliveryStatus.paused ||
    DonationDeliveryStatus.suspended ||
    DonationDeliveryStatus.archived ||
    DonationDeliveryStatus.cancelled => null,
  };
}

dynamic _statusFieldFromDonationRow(Map json) {
  return json['status'] ??
      json['donation_status'] ??
      json['payment_status'] ??
      json['state'] ??
      json['payment_state'];
}

extension DonationRecordStatusUi on DonationRecordStatus {
  String get label => switch (this) {
    DonationRecordStatus.success => 'Success',
    DonationRecordStatus.pending => 'Pending',
    DonationRecordStatus.failed => 'Failed',
  };

  Color get color => switch (this) {
    DonationRecordStatus.success => const Color(0xFF16A34A),
    DonationRecordStatus.pending => const Color(0xFFF59E0B),
    DonationRecordStatus.failed => const Color(0xFFEF4444),
  };

  IconData get icon => switch (this) {
    DonationRecordStatus.success => Icons.check_circle_rounded,
    DonationRecordStatus.pending => Icons.schedule_rounded,
    DonationRecordStatus.failed => Icons.cancel_rounded,
  };
}

String formatDonationHistoryDate(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString().trim();
  if (s.isEmpty) return '—';

  DateTime? dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  dt ??= DateTime.tryParse(s);
  if (dt == null) return s;

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = dt.day.toString().padLeft(2, '0');
  final m = months[dt.month - 1];
  return '$d $m ${dt.year}';
}

class DonationHistoryEntry {
  const DonationHistoryEntry({
    required this.campaignName,
    required this.amount,
    required this.dateLabel,
    required this.paymentMethod,
    required this.status,
    required this.deliveryStatus,
    required this.reference,
    required this.note,
    required this.id,
    required this.campaignId,
  });

  final String campaignName;
  final int amount;
  final String dateLabel;
  final String paymentMethod;

  /// Whether the MONEY cleared. Not the same question as [deliveryStatus].
  final DonationRecordStatus status;

  /// Whether the AID reached the family. Null when the server sent no
  /// recognised `delivery_status` — see [donationDeliveryStatusFromApi].
  final DonationDeliveryStatus? deliveryStatus;

  final String reference;
  final String note;

  /// Donation row id — used to start a chat with the campaign owner.
  final int? id;

  /// Campaign this donation went to (null for general donations). Only
  /// campaign donations can open a chat with an owner.
  final int? campaignId;

  factory DonationHistoryEntry.fromJson(Map json) {
    final amountRaw = json['amount'];
    int amount = 0;
    if (amountRaw is int) {
      amount = amountRaw;
    } else if (amountRaw is double) {
      amount = amountRaw.round();
    } else {
      amount = int.tryParse('$amountRaw') ?? 0;
    }

    final name =
        (json['campaign_name'] ??
                json['campaign_title'] ??
                json['title'] ??
                json['campaign'] ??
                'Contribution')
            .toString();

    final refExplicit = json['reference']?.toString().trim();
    final idRaw = json['id'];
    final String ref;
    if (refExplicit != null && refExplicit.isNotEmpty) {
      ref = refExplicit;
    } else if (idRaw != null && '$idRaw'.isNotEmpty) {
      ref = '#$idRaw';
    } else {
      ref = '—';
    }

    final note = (json['message'] ?? json['note'] ?? '').toString();

    return DonationHistoryEntry(
      campaignName: name,
      amount: amount,
      dateLabel: formatDonationHistoryDate(
        json['transaction_date'] ??
            json['transactionDate'] ??
            json['created_at'] ??
            json['date'] ??
            json['donation_date'],
      ),
      paymentMethod: (json['payment_method'] ?? json['paymentMethod'] ?? '')
          .toString(),
      status: donationRecordStatusFromApi(_statusFieldFromDonationRow(json)),
      deliveryStatus: donationDeliveryStatusFromApi(json['delivery_status']),
      reference: ref,
      note: note.isEmpty ? '—' : note,
      id: idRaw == null ? null : int.tryParse('$idRaw'),
      campaignId: json['campaign_id'] == null
          ? null
          : int.tryParse('${json['campaign_id']}'),
    );
  }
}
