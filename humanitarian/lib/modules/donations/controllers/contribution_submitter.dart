// Sends a contribution from one of the four R2 pages and tells the donor what
// happened (R2 #52, #54).
//
// WHAT #54 WAS
// The old checkout said "sent and pending" and then nothing showed up. Two
// causes were found: the server answered success while saving an EMPTY amount
// for any gift of 1,000,000 or more (fixed server-side — it now refuses), and
// the donor was dropped back on the Contribute tab with no sight of the gift.
// So success here ends on «تبرعاتي», where the new row is, not on a dialog
// that only says it went somewhere.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/donations/controllers/continue_donation_controller.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';
import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';

/// The details a money page hands over. Null / empty values are not sent.
class MoneyContribution {
  const MoneyContribution({
    required this.amount,
    required this.currency,
    required this.method,
    required this.channel,
    this.transferKind,
    this.network,
    this.serialNumber,
    this.attachmentLocalPath,
    this.phone,
    this.address,
    this.visitNote,
    this.note,
    this.campaignsId,
  });

  final int amount;
  final String currency;

  /// The payment method as staff know it — the catalogue's English name.
  final String method;

  /// electronic | balance_transfer | cash
  final String channel;
  final String? transferKind;
  final String? network;
  final String? serialNumber;

  /// A file on this device. Uploaded here, only when the donor confirms.
  final String? attachmentLocalPath;
  final String? phone;
  final String? address;
  final String? visitNote;
  final String? note;
  final int? campaignsId;
}

/// Uploads the attachment (if any), submits, and reports. Returns true when the
/// contribution was saved — the caller has nothing left to do then, because the
/// donor has already been taken to their contributions list.
Future<bool> submitMoneyContribution(
  BuildContext context,
  MoneyContribution c,
) async {
  // A contribution is a purchase; guests upgrade first (also enforced
  // server-side).
  if (!await requireUpgrade(context)) return false;
  if (!context.mounted) return false;

  String? uploaded;
  if (c.attachmentLocalPath != null) {
    try {
      uploaded = await const ModuleApi().uploadPhoto(
        File(c.attachmentLocalPath!),
      );
    } catch (e) {
      debugPrint('contribution attachment upload failed: $e');
      _showError('The photo could not be uploaded. Try again.'.tr);
      return false;
    }
  }

  final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
  final err = await ContinueDonationController().submitDonation(
    userId: userId,
    campaignsId: c.campaignsId,
    message: c.note,
    amount: c.amount,
    paymentMethod: c.method,
    extraFields: {
      'channel': c.channel,
      if (c.transferKind != null) 'transfer_kind': c.transferKind!,
      if (c.network != null) 'network': c.network!,
      if (c.serialNumber != null) 'serial_number': c.serialNumber!,
      if (uploaded != null) 'attachment_path': uploaded,
      if (c.phone != null) 'donor_phone': c.phone!,
      if (c.address != null) 'donor_address': c.address!,
      if (c.visitNote != null) 'visit_note': c.visitNote!,
      'currency': c.currency,
    },
  );
  if (err != null) {
    _showError(err.tr);
    return false;
  }
  if (!context.mounted) return true;
  await _finish(context);
  return true;
}

void _showError(String message) {
  Get.snackbar(
    'Contribution failed'.tr,
    message,
    snackPosition: SnackPosition.BOTTOM,
    margin: const EdgeInsets.all(16),
    backgroundColor: Colors.red.shade700,
    colorText: Colors.white,
    duration: const Duration(seconds: 4),
  );
}

/// One short confirmation, then straight to the list the gift now appears in.
Future<void> _finish(BuildContext context) async {
  AppHaptics.success();
  await showAdaptiveMessage(
    context,
    title: 'Contribution sent'.tr,
    message: 'It is under review. You can follow it in My contributions.'.tr,
    buttonLabel: 'OK'.tr,
    icon: Icon(
      Icons.check_circle_rounded,
      size: 48,
      color: Theme.of(context).colorScheme.primary,
    ),
    barrierDismissible: false,
  );
  // Replace the whole donation flow with the list, so Back lands on Home and
  // not on a form that has already been sent.
  Get.offUntil(
    GetPageRoute<void>(page: () => const MyDonationsPage()),
    (route) => route.isFirst,
  );
}

/// The same ending for the in-kind page, which has no money list to land on.
Future<void> finishInKindContribution(BuildContext context) async {
  AppHaptics.success();
  await showAdaptiveMessage(
    context,
    title: 'Contribution sent'.tr,
    message:
        'It is under review. We will contact you to arrange collection.'.tr,
    buttonLabel: 'OK'.tr,
    icon: Icon(
      Icons.check_circle_rounded,
      size: 48,
      color: Theme.of(context).colorScheme.primary,
    ),
    barrierDismissible: false,
  );
  Get.until((route) => route.isFirst);
}

/// Shared by the in-kind page: surfaces the same error snackbar.
void showContributionError(String message) => _showError(message);
