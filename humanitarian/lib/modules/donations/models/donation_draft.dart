// What the Contribute tab has decided by the time the donor taps Continue.
//
// WHY THIS FILE EXISTS
// M3 puts a new screen between the Contribute tab and checkout — "what kind of
// donation is this?" — so the nine values the tab had been handing straight to
// [ContinueDonationScreen] now have to travel one hop further. Threading nine
// positional details through a second constructor is how parameter lists rot,
// so they travel as one object instead.
//
// It carries no behaviour on purpose. It is the donor's in-progress choice,
// nothing more; every decision about what that choice MEANS lives in
// donation_channel.dart.
import 'package:flutter/widgets.dart';

/// The amount, the campaign, and the presentation of the option the donor
/// picked on the Contribute tab.
@immutable
class DonationDraft {
  const DonationDraft({
    required this.amount,
    required this.campaignsId,
    required this.optionTitle,
    required this.optionSummary,
    required this.optionTypeLabel,
    required this.optionSupportNote,
    required this.optionIcon,
    required this.optionColor,
    required this.paymentMethod,
  });

  /// The chosen amount in IQD. Still editable on the checkout screen.
  final int amount;

  /// Set when the donor came in through a featured campaign, in which case the
  /// gift already has a destination and no project may be chosen for it.
  final int? campaignsId;

  // The four strings below are the selected option's own copy, shown again in
  // the checkout summary so the donor can see what they are giving to without
  // going back. They are translation KEYS, passed through `.tr` at render.
  final String optionTitle;
  final String optionSummary;
  final String optionTypeLabel;
  final String optionSupportNote;

  final IconData optionIcon;

  /// The accent this donation is drawn in, so the flow keeps one colour from
  /// the Contribute tab through to the confirmation dialog.
  final Color optionColor;

  /// The payment method the Contribute tab had preselected, by display name.
  /// Checkout uses it to preselect the same row when it is still on offer.
  final String paymentMethod;
}
