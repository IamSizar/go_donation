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
    required this.reference,
    required this.note,
  });

  final String campaignName;
  final int amount;
  final String dateLabel;
  final String paymentMethod;
  final DonationRecordStatus status;
  final String reference;
  final String note;

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
                'Donation')
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
      reference: ref,
      note: note.isEmpty ? '—' : note,
    );
  }
}
