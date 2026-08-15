// M3 — the one step that asks what kind of donation this is.
//
// WHY THIS SCREEN EXISTS
// The client's donation note lists five ways to give and asks for them to be
// offered "عند الاختيار" — at the point of choosing. The app had no such step.
// Contribute → amount → Continue went straight to checkout, which stacked four
// unrelated selectors (destination, project, giving type, payment method) and
// never named cash / electronic / balance transfer as a choice at all: they
// were flat rows in the payment list. In-kind was worse than hidden — its form
// lives in the Services hub, so a donor in the Contribute tab could not reach
// it from the donation flow by any route.
//
// WHERE THE FIVE COME FROM
// Not from a list in this file. Three of them are families of the
// admin-managed payment-method catalogue and are offered only when the
// organization actually has a method of that family configured — see
// donation_channel.dart for the mapping and the reasoning. Adding a new
// processor from the dashboard makes it appear here with no app release.
//
// THE FOUR STATES
// Modelled on payment_methods_screen.dart, which documents why AppAsync is the
// wrong tool for a composite screen: the error is checked BEFORE the content
// branch so the two are mutually exclusive rather than stacked, and the empty
// case is a section inside the content rather than a whole-screen takeover —
// because donating GOODS never depended on the payment catalogue and stays on
// offer even when there is nothing to pay with.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';
import 'package:flutter_application_1/modules/donations/models/donation_draft.dart';
import 'package:flutter_application_1/modules/donations/screens/continue_donation_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart'
    show InKindDonationFormScreen;
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// Asks the donor which of the five kinds of donation this is, then sends them
/// down the matching flow.
class DonationKindScreen extends StatefulWidget {
  const DonationKindScreen({super.key, required this.draft});

  /// Everything the Contribute tab had already decided. Forwarded unchanged to
  /// checkout together with the channel chosen here.
  final DonationDraft draft;

  @override
  State<DonationKindScreen> createState() => _DonationKindScreenState();
}

class _DonationKindScreenState extends State<DonationKindScreen> {
  /// True for the FIRST load only, so a retry refreshes in place.
  bool _loading = true;

  /// A user-facing message, or null when the last load succeeded. Never an
  /// exception string — the technical detail goes to the log instead.
  String? _error;

  /// The money channels the organization can actually accept right now.
  /// Empty is a real answer (nothing configured), not a failure.
  List<DonationChannel> _moneyChannels = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the payment catalogue and works out which money channels it
  /// supports.
  ///
  /// Only the payment catalogue is fetched. In-kind is deliberately NOT gated
  /// on `GET /api/inkind-categories`: that call returns `[]` on failure rather
  /// than throwing, so gating on it would hide a working feature whenever the
  /// network blipped, and the in-kind form accepts a free-text category
  /// anyway. Donating goods needs no payment method and no vocabulary, so it
  /// is always on offer.
  Future<void> _load() async {
    // Cleared up front so a successful retry does not leave the old banner up.
    if (_error != null) setState(() => _error = null);
    try {
      final methods = await fetchPaymentMethods();
      if (!mounted) return;
      setState(() {
        _moneyChannels = _channelsFor(methods);
        _loading = false;
      });
    } catch (e) {
      // fetchPaymentMethods throws rather than returning [] precisely so this
      // branch can exist: without it, an unreachable server would look like an
      // organization that accepts no money at all.
      debugPrint('DonationKind: payment catalogue unavailable: $e');
      if (!mounted) return;
      setState(() {
        _error = 'We could not load the ways you can give.';
        _loading = false;
      });
    }
  }

  /// Which money channels this catalogue supports, in the order M3 lists them.
  ///
  /// A channel appears only when at least one active method belongs to it, so
  /// the donor is never offered a route with nothing behind it. "Support the
  /// organization" needs any method at all, since it is a destination for
  /// money rather than a way of paying.
  static List<DonationChannel> _channelsFor(List<PaymentMethod> methods) {
    if (methods.isEmpty) return const [];
    const ordered = [
      DonationChannel.cash,
      DonationChannel.electronic,
      DonationChannel.balanceTransfer,
      DonationChannel.supportOrganization,
    ];
    return [
      for (final channel in ordered)
        if (methods.any((m) => channel.acceptsMethodType(m.methodType)))
          channel,
    ];
  }

  /// Opens the flow behind [channel] and forwards a completed donation back to
  /// the Contribute tab, which resets its selection on `true`.
  Future<void> _choose(DonationChannel channel) async {
    AppHaptics.selection();

    if (!channel.isMoney) {
      // Goods take no amount and no payment method, so the money checkout has
      // nothing to do here. The form is the one that already exists in the
      // Services hub — reached from the donation flow for the first time.
      await Get.to<void>(() => const InKindDonationFormScreen());
      return;
    }

    final submitted = await Get.to<bool>(
      () => ContinueDonationScreen(
        amount: widget.draft.amount,
        campaignsId: widget.draft.campaignsId,
        optionTitle: widget.draft.optionTitle,
        optionSummary: widget.draft.optionSummary,
        optionTypeLabel: widget.draft.optionTypeLabel,
        optionSupportNote: widget.draft.optionSupportNote,
        optionIcon: widget.draft.optionIcon,
        optionColor: widget.draft.optionColor,
        paymentMethod: widget.draft.paymentMethod,
        channel: channel,
      ),
    );
    if (!mounted) return;
    // Pass the outcome up rather than swallowing it: this screen sits between
    // the Contribute tab and checkout, and the tab clears its chosen amount
    // only when a donation actually went through.
    if (submitted == true) Get.back<bool>(result: true);
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      title: 'What kind of donation is this?',
      subtitle: 'Choose how you would like to give.',
      scrollable: true,
      child: _loading
          ? const _KindSkeleton()
          // Error BEFORE empty: a failed catalogue read must never be shown as
          // "the organization accepts nothing".
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_moneyChannels.isEmpty)
                  const _NoPaymentMethodsNote()
                else
                  for (final channel in _moneyChannels) ...[
                    _ChannelTile(
                      channel: channel,
                      onTap: () => _choose(channel),
                    ),
                    const SizedBox(height: AppSpace.sm),
                  ],
                // Always last, and always present: goods need no payment
                // method, so this tile survives an empty catalogue.
                _ChannelTile(
                  channel: DonationChannel.inKind,
                  onTap: () => _choose(DonationChannel.inKind),
                ),
                const SizedBox(height: AppSpace.xl),
              ],
            ),
    );
  }
}

/// One of the five choices, as a tappable card.
///
/// [SectionTile] is the app's existing icon + title + subtitle + chevron card
/// and translates both strings itself, so the labels below are keys.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onTap});

  final DonationChannel channel;
  final VoidCallback onTap;

  /// Icons match the ones the payment list already uses for the same families,
  /// so a donor who picks "cards and wallets" here meets the same glyphs on
  /// the next screen.
  IconData get _icon => switch (channel) {
    DonationChannel.cash => Icons.payments_rounded,
    DonationChannel.electronic => Icons.credit_card_rounded,
    DonationChannel.balanceTransfer => Icons.smartphone_rounded,
    DonationChannel.inKind => Icons.inventory_2_rounded,
    DonationChannel.supportOrganization => Icons.settings_suggest_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SectionTile(
      icon: _icon,
      // SectionTile passes both through `.tr` itself, so these stay keys.
      title: channel.titleKey,
      subtitle: channel.subtitleKey,
      color: AppThemeConfig.accent(context),
      onTap: onTap,
    );
  }
}

/// The empty state for the money half of this screen.
///
/// Written inline rather than with [AppEmpty] because this screen is a
/// composite: goods are still on offer below, so a full-height centred
/// takeover would both scroll wrongly inside the page and overstate the
/// problem. Same anatomy as AppEmpty — mark, headline, explanation — minus the
/// centring.
class _NoPaymentMethodsNote extends StatelessWidget {
  const _NoPaymentMethodsNote();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.lineStrong, width: 1.5),
              ),
              child: Icon(
                Icons.credit_card_off_rounded,
                size: 20,
                color: c.inkTertiary,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'No ways to pay yet'.tr,
              style: TextStyle(
                fontSize: AppType.heading,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: c.ink,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'The organization has not published a payment method yet. You can still donate goods below.'
                  .tr,
              style: TextStyle(
                fontSize: AppType.dense,
                height: AppType.leadBody,
                color: c.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First-load placeholder shaped like the real tiles.
///
/// Five bones at [SectionTile]'s real height, so the cards fill in where the
/// placeholder sat instead of pushing the layout around when they arrive.
/// [AppSkeleton.rows] would be wrong: ragged text lines land nowhere near a
/// column of tall cards.
class _KindSkeleton extends StatelessWidget {
  const _KindSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
              child: Container(
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.of(context).groundSunken,
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
