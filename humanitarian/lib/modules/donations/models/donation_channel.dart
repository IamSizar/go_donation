// The five ways a donor can give (M3), and how each one maps onto data the
// server already serves.
//
// WHY THIS FILE EXISTS
// The client's donation note asks for ONE step that asks what kind of donation
// this is, with five choices:
//
//   1. تبرع نقدي (تسليم مباشر)              — cash, handed over in person
//   2. تبرع عبر وسائل الدفع الإلكتروني        — cards, wallets, bank transfer
//   3. التبرع عبر تحويل الرصيد                — recharge cards / phone transfer
//   4. التبرعات العينية                      — goods, not money
//   5. التبرع لدعم المنظمة                   — running costs, not a beneficiary
//
// The app had no such step. Checkout stacked four unrelated selectors instead,
// cash/electronic/balance existed only as flat rows in the payment list with
// nothing naming them as a choice, and the in-kind form lived in a different
// module that a donor never reaches from the Contribute tab.
//
// THE ONE THING THIS FILE IS CAREFUL ABOUT
// Three of the five are FAMILIES OF PAYMENT METHODS, not a second catalogue.
// The organization's real payment methods are admin-managed rows
// (`GET /api/payment-methods`, migration 084) carrying a `method_type` of
// cash | bank | card | wallet | mobile. Writing "MasterCard, Visa, e-wallet"
// into the binary would recreate the exact defect migration 103 was written to
// remove one table over. So each money channel is defined here as a PREDICATE
// over `method_type`, and the step screen offers a channel only when the
// catalogue actually contains a method of that family. Adding a new processor
// from the dashboard makes it appear under its family with no app release —
// which is what "ووسائل الدفع الإلكترونية المستقبلية" asks for.
//
// The remaining two are not payment families at all:
//   • in-kind has its own form and its own admin-managed category vocabulary
//     (`GET /api/inkind-categories`), and needs no payment method;
//   • supporting the organization is a DESTINATION for money — it is submitted
//     as `donation_kind: operational`, has its own reporting section and its
//     own transaction-code prefix — so it accepts every payment method.
//
// NOT to be confused with the donor's giving TYPE (General / Zakat / Sadaqah),
// which is a separate admin-managed taxonomy — see lib/api/donation_types_api.
library;

/// One of the five choices M3 asks for.
enum DonationChannel {
  /// Cash, handed to a representative or a collection point.
  cash,

  /// Cards, electronic wallets and bank transfer.
  electronic,

  /// Recharge cards, or transfer to the organization's phone numbers.
  balanceTransfer,

  /// Goods rather than money. Routes to the in-kind form, not to checkout.
  inKind,

  /// Money towards the organization's own running costs.
  supportOrganization,
}

extension DonationChannelBehaviour on DonationChannel {
  /// Whether this channel ends at the money checkout screen.
  ///
  /// In-kind is the only one that does not: it has its own form, and asking a
  /// donor for a payment method for a box of clothes is nonsense.
  bool get isMoney => this != DonationChannel.inKind;

  /// The `donation_kind` this channel submits under, or null for the default.
  ///
  /// Only "support the organization" changes it. The three money channels are
  /// ordinary cause donations that differ in HOW the money arrives, not in
  /// where it goes, so they must not be re-filed as anything else.
  String? get donationKind =>
      this == DonationChannel.supportOrganization ? 'operational' : null;

  /// Whether a donation through this channel can still be aimed at a project.
  ///
  /// Supporting the organization cannot: it funds servers and administration,
  /// not a project, so offering a project picker beside it would mis-file the
  /// gift (M4).
  bool get allowsProjectChoice =>
      isMoney && this != DonationChannel.supportOrganization;

  /// Does a payment method of this `method_type` belong to this channel?
  ///
  /// `supportOrganization` accepts everything — it is a destination, not a
  /// payment family. `inKind` accepts nothing, because it takes no payment.
  ///
  /// An unrecognised `method_type` (a value added server-side that this build
  /// has never heard of) counts as electronic. That is the honest default:
  /// "cash" and "recharge card" are specific physical arrangements the server
  /// already names explicitly, so anything else arriving through the API is
  /// some form of electronic payment, and hiding it entirely would lose the
  /// donor a way to pay.
  bool acceptsMethodType(String methodType) {
    switch (this) {
      case DonationChannel.inKind:
        return false;
      case DonationChannel.supportOrganization:
        return true;
      case DonationChannel.cash:
        return methodType == 'cash';
      case DonationChannel.balanceTransfer:
        return methodType == 'mobile';
      case DonationChannel.electronic:
        return methodType != 'cash' && methodType != 'mobile';
    }
  }

  /// Whether the app's own internal wallet is offered on this channel.
  ///
  /// The wallet is a stored electronic balance, so it belongs with the
  /// electronic family, and with "support the organization" because that
  /// channel accepts every method. Offering it under "cash — direct handover"
  /// would contradict the choice the donor just made.
  bool get includesAppWallet =>
      this == DonationChannel.electronic ||
      this == DonationChannel.supportOrganization;

  /// The translation KEY naming this channel.
  ///
  /// Lives here rather than in the step screen because two surfaces show it:
  /// the step where it is chosen, and the checkout row that reports what was
  /// chosen. Two copies of the same five labels is how they drift apart.
  ///
  /// In-kind and support-the-organization deliberately reuse keys the app
  /// already ships in Arabic and Sorani — the Services hub names the same
  /// form, and checkout already named the same destination.
  String get titleKey => switch (this) {
    DonationChannel.cash => 'Cash donation (direct handover)',
    DonationChannel.electronic => 'Donation by electronic payment',
    DonationChannel.balanceTransfer => 'Donation by balance transfer',
    DonationChannel.inKind => 'In-kind donation',
    DonationChannel.supportOrganization => 'Support the organization',
  };

  /// The translation key for the one-line explanation under [titleKey].
  String get subtitleKey => switch (this) {
    DonationChannel.cash =>
      'Hand your gift to a representative or leave it at a collection point.',
    DonationChannel.electronic =>
      'Cards, electronic wallets and bank transfer.',
    DonationChannel.balanceTransfer =>
      'Recharge cards, or transfer to the numbers set aside for donations.',
    DonationChannel.inKind =>
      'Food, clothing, stationery, furniture or home appliances.',
    DonationChannel.supportOrganization =>
      'Covers running costs: servers, subscriptions and administration.',
  };

  /// A stable token for logs and test assertions. Never shown to a user —
  /// user-facing names come from the translation map.
  String get slug => switch (this) {
    DonationChannel.cash => 'cash',
    DonationChannel.electronic => 'electronic',
    DonationChannel.balanceTransfer => 'balance_transfer',
    DonationChannel.inKind => 'in_kind',
    DonationChannel.supportOrganization => 'support_organization',
  };
}
