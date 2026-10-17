import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/localization/money.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';
import 'package:flutter_application_1/modules/donations/controllers/continue_donation_controller.dart';
import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';
import 'package:flutter_application_1/modules/donations/widgets/aid_target_field.dart';
import 'package:flutter_application_1/modules/donations/widgets/donation_type_field.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart'
    show InKindDonationFormScreen;
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/api/project_categories_api.dart';
import 'package:get/get.dart';
// `intl` exports its own `TextDirection`, which collides with Flutter's when
// forcing LTR on the locked phone row below — this file only needs the
// formatters from it.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/app_snackbar.dart';
import 'package:flutter_application_1/core/phone_format.dart';

class ContinueDonationScreen extends StatefulWidget {
  const ContinueDonationScreen({
    super.key,
    required this.amount,
    this.campaignsId,
    required this.optionTitle,
    required this.optionSummary,
    required this.optionTypeLabel,
    required this.optionSupportNote,
    required this.optionIcon,
    required this.optionColor,
    required this.paymentMethod,
    required this.channel,
  });

  final int amount;

  /// When set (featured campaign), sent as `campaigns_id` to the donation API.
  final int? campaignsId;
  final String optionTitle;
  final String optionSummary;
  final String optionTypeLabel;
  final String optionSupportNote;
  final IconData optionIcon;
  final Color optionColor;
  final String paymentMethod;

  /// M3 — which of the five kinds of donation the donor chose on the step
  /// before this one. It decides three things here and is not asked again:
  /// which payment methods are on offer, whether a project may be chosen, and
  /// whether the gift is filed as operational support.
  final DonationChannel channel;

  @override
  State<ContinueDonationScreen> createState() => _ContinueDonationScreenState();
}

class _ContinueDonationScreenState extends State<ContinueDonationScreen> {
  final _formKey = GlobalKey<FormState>();
  // Note: there are no name/phone controllers here. Those two donor details
  // are read straight out of the signed-in account (see `_accountName` /
  // `_accountPhone`) and are never editable and never submitted, so they are
  // rendered as locked rows instead of as text fields.
  final _moneyController = TextEditingController();
  final _noteController = TextEditingController();

  late final ContinueDonationController _submitController;

  /// The kind of donation. Starts as the one handed in and is changed on this
  /// same screen (R2 #47) — it used to be a separate step before checkout.
  late DonationChannel _channel;

  int _selectedPaymentIndex = 0;
  String _donationType = 'general';
  // M4 — where a cause donation lands: null is مساعدات عامة (staff distribute
  // by need), a value is التبرع حسب مشروع محدد. The list, the dashboard
  // visibility switch and all four load states now live in [AidTargetField];
  // this screen holds only what it will actually submit.
  ProjectCategory? _selectedProject;

  // Where the gift goes — 'operational' for "Donation to Support the
  // Organization" (running costs: servers, subscriptions, administration; its
  // own reporting section and its own transaction-code prefix), null for an
  // ordinary cause donation.
  //
  // This used to be a pair of tiles ON THIS SCREEN, asked directly above the
  // payment list. M3 moved the question one screen earlier, where it is one of
  // the five kinds of donation, so asking it twice would be the duplication
  // the client reported. It is now derived, never re-asked.
  String? get _donationKind => _channel.donationKind;

  // #19 — payment methods are admin-managed (fetched from /api/payment-methods).
  // These two are the offline fallback so the donate form always works.
  static const List<_PaymentMethodData> _fallbackMethods = [
    _PaymentMethodData(
      title: 'Cash',
      subtitle: 'Pay in person or at a collection point',
      icon: Icons.payments_rounded,
      methodType: 'cash',
      submitName: 'Cash',
    ),
    _PaymentMethodData(
      title: 'FIB',
      subtitle: 'First Iraqi Bank and supported channels',
      icon: Icons.account_balance_rounded,
      methodType: 'bank',
      accountNumber: '7510208962',
      submitName: 'FIB',
    ),
  ];

  /// Every method on offer, before the channel filter.
  List<_PaymentMethodData> _paymentMethods = _fallbackMethods;

  // True once a payment-methods load has actually failed, so the donor is
  // told the list they are looking at is the built-in default rather than the
  // organization's current catalogue. Not set merely because the catalogue
  // came back empty — that is a real (if unhelpful) answer, not a failure.
  bool _paymentMethodsFailed = false;

  // Note #42 — the internal test-phase wallet. Prepended to whatever
  // admin-managed methods exist (it's not one of them), at index 0 of
  // [_displayMethods] on the channels that accept it.
  //
  // `null` means "we do not know the balance" — it is the starting state and
  // the state we fall back to when the balance request fails. It is
  // deliberately NOT 0: a confident "0 IQD" on a checkout screen tells the
  // donor their wallet is empty, which is a specific claim we cannot make when
  // the request never succeeded. Unknown is rendered as an explicit
  // unavailable line instead (see [_walletMethod]).
  int? _walletBalanceIQD;

  _PaymentMethodData get _walletMethod => _PaymentMethodData(
    title: 'App Wallet',
    subtitle: _walletBalanceIQD == null
        ? 'Balance unavailable right now'.tr
        : '${'Balance'.tr}: ${_formatIQD(_walletBalanceIQD!)} ${localizedCurrency('IQD')}',
    icon: Icons.account_balance_wallet_rounded,
    // A stored electronic balance, so it belongs to the electronic family.
    methodType: 'wallet',
    submitName: 'app_wallet',
  );

  /// The methods that belong to the channel the donor chose (M3).
  ///
  /// Empty means the choice made one screen ago has nothing behind it here —
  /// see [_displayMethods], which refuses to leave the donor with no way to
  /// pay.
  List<_PaymentMethodData> get _channelMethods => [
    if (_channel.includesAppWallet) _walletMethod,
    ..._paymentMethods.where((m) => _channel.acceptsMethodType(m.methodType)),
  ];

  /// The money channels this organization can actually take right now: a
  /// channel is offered only when at least one method belongs to it, so the
  /// donor is never shown a route with nothing behind it.
  List<DonationChannel> get _availableChannels => [
    for (final c in const [
      DonationChannel.cash,
      DonationChannel.electronic,
      DonationChannel.balanceTransfer,
      DonationChannel.supportOrganization,
    ])
      if (_paymentMethods.any((m) => c.acceptsMethodType(m.methodType))) c,
  ];

  /// Opens the picker of the five kinds of donation. Goods leave this screen
  /// for their own form; the money kinds just swap the methods listed below.
  Future<void> _pickChannel() async {
    AppHaptics.selection();
    final options = [..._availableChannels, DonationChannel.inKind];
    final picked = await showModalBottomSheet<DonationChannel>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final c in options)
              ListTile(
                leading: Icon(
                  c == _channel
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: widget.optionColor,
                ),
                title: Text(
                  c.titleKey.tr,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(c.subtitleKey.tr),
                onTap: () => Navigator.of(ctx).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (!picked.isMoney) {
      await Get.to<void>(() => const InKindDonationFormScreen());
      return;
    }
    setState(() {
      _channel = picked;
      _selectedProject = picked.allowsProjectChoice ? _selectedProject : null;
      _selectPreferredMethod();
    });
  }

  /// True when the chosen channel matched nothing in the list we ended up
  /// with, so the donor is being shown every method instead of that family.
  ///
  /// Reachable in one way: the catalogue was readable on the step screen and
  /// not here, so checkout fell back to its built-in Cash/FIB pair, which has
  /// no `mobile` method in it. Silently widening the list would make the
  /// channel choice a control that did nothing, so [_ChannelFallbackNote] says
  /// what happened.
  bool get _channelHasNoMethods => _channelMethods.isEmpty;

  /// What the donor actually sees, in order.
  List<_PaymentMethodData> get _displayMethods => _channelHasNoMethods
      ? [_walletMethod, ..._paymentMethods]
      : _channelMethods;

  static String _formatIQD(int n) => NumberFormat('#,##0').format(n);

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<ContinueDonationController>()) {
      Get.delete<ContinueDonationController>();
    }
    _submitController = Get.put(ContinueDonationController());
    _channel = widget.channel;
    _selectPreferredMethod();
    _moneyController.text = widget.amount.toString();
    _loadPaymentMethods();
    _loadWalletBalance();
  }

  /// Points [_selectedPaymentIndex] at the method the Contribute tab had
  /// preselected, or at the first one the channel offers.
  ///
  /// The index used to be maintained by hand with a `+1` offset for the wallet
  /// row. That offset stopped being a constant once the channel filter could
  /// drop the wallet, so the preference is resolved against the list the donor
  /// actually sees. The default is never the wallet unless the wallet is the
  /// only thing on offer — spending a stored balance should be a deliberate
  /// choice.
  void _selectPreferredMethod() {
    final shown = _displayMethods;
    final named = shown.indexWhere((m) => m.title == widget.paymentMethod);
    if (named >= 0) {
      _selectedPaymentIndex = named;
      return;
    }
    final firstNonWallet = shown.indexWhere(
      (m) => m.submitName != 'app_wallet',
    );
    _selectedPaymentIndex = firstNonWallet >= 0 ? firstNonWallet : 0;
  }

  /// Loads the wallet balance shown on the App Wallet payment card.
  ///
  /// [fetchWalletBalance] now throws instead of reporting a zero balance on
  /// failure. We must not turn that back into a number: on a checkout screen a
  /// wrong balance is worse than an absent one. On failure the balance is set
  /// back to `null`, which renders as "Balance unavailable right now" — the
  /// donor can still choose the wallet, and the server remains the authority
  /// on whether the funds cover the donation.
  Future<void> _loadWalletBalance() async {
    try {
      final balance = await fetchWalletBalance();
      if (!mounted) return;
      setState(() => _walletBalanceIQD = balance.balanceIQD);
    } catch (e) {
      debugPrint('ContinueDonation: wallet balance unavailable: $e');
      if (!mounted) return;
      setState(() => _walletBalanceIQD = null);
    }
  }

  // #19 — fetch the admin-managed payment methods; keep the built-in fallback
  // (Cash/FIB) if the list is empty or the request fails.
  //
  // The fallback is deliberate and lives here, at the call site: a donor must
  // still be able to pay when the catalogue endpoint is down, so a failure is
  // caught, logged, and answered with the built-in Cash/FIB pair plus a note
  // telling the donor these are default options. This is the one place that
  // wants that behaviour — it is no longer hidden inside the API where every
  // other caller inherited it.
  Future<void> _loadPaymentMethods() async {
    final List<PaymentMethod> fetched;
    try {
      fetched = await fetchPaymentMethods();
    } catch (e) {
      debugPrint('ContinueDonation: payment methods unavailable: $e');
      if (!mounted) return;
      setState(() => _paymentMethodsFailed = true);
      return;
    }
    if (!mounted || fetched.isEmpty) return;
    setState(() {
      _paymentMethodsFailed = false;
      _paymentMethods = [
        for (final m in fetched)
          _PaymentMethodData(
            title: m.localizedName,
            subtitle: m.localizedInstructions,
            icon: _iconForMethodType(m.methodType),
            methodType: m.methodType,
            accountNumber: m.accountNumber,
            accountName: m.accountName,
            submitName: m.nameEn.isNotEmpty ? m.nameEn : m.localizedName,
          ),
      ];
      // The list just changed under the selection, so re-resolve it rather
      // than leaving an index pointing at whatever now sits in that slot.
      final offered = _availableChannels;
      if (offered.isNotEmpty && !offered.contains(_channel)) {
        _channel = offered.first;
      }
      _selectPreferredMethod();
    });
  }

  static IconData _iconForMethodType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_rounded;
      case 'wallet':
        return Icons.account_balance_wallet_rounded;
      // Donations Page spec — electronic cards and mobile balance transfer.
      case 'card':
        return Icons.credit_card_rounded;
      case 'mobile':
        return Icons.smartphone_rounded;
      default:
        return Icons.account_balance_rounded;
    }
  }

  @override
  void dispose() {
    if (Get.isRegistered<ContinueDonationController>()) {
      Get.delete<ContinueDonationController>();
    }
    _moneyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirmDonation() async {
    if (!_formKey.currentState!.validate()) return;
    // Note #40 — a donation is a "purchase"; guests are prompted to upgrade
    // before acting (also enforced server-side). Matches the guard already
    // used one screen earlier on the campaign-select button.
    if (!await requireUpgrade(context)) return;

    final paymentMethod = _displayMethods[_selectedPaymentIndex];
    final amount = int.parse(_moneyController.text.trim());
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    final note = _noteController.text.trim();

    final err = await _submitController.submitDonation(
      userId: userId,
      campaignsId: widget.campaignsId,
      message: note.isEmpty ? null : note,
      amount: amount,
      paymentMethod: paymentMethod.submitName.isNotEmpty
          ? paymentMethod.submitName
          : paymentMethod.title,
      donationType: _donationType,
      // Belt and braces: the project section is hidden on the channels that
      // cannot target one, and the slug is dropped here too, so a stale
      // selection can never travel with an operational gift and mis-file it.
      projectSlug: _channel.allowsProjectChoice ? _selectedProject?.slug : null,
      donationKind: _donationKind,
    );

    if (!mounted) return;

    if (paymentMethod.submitName == 'app_wallet') {
      // Refresh the displayed balance regardless of outcome — a failed
      // submit still leaves the debit-then-refund cycle possibly reflected
      // server-side, and a success obviously changed it.
      unawaited(_loadWalletBalance());
    }

    if (err != null) {
      appSnackbar(
        'Donation failed'.tr,
        err,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    if (!mounted) return;

    AppHaptics.success();

    // barrierDismissible stays false: the screen behind this pops when the
    // message is acknowledged, so the user must actually see it first.
    await showAdaptiveMessage(
      context,
      title: 'Pending successfully'.tr,
      message: 'Your donation was submitted and is pending. Thank you.'.tr,
      buttonLabel: 'OK'.tr,
      icon: Icon(
        Icons.pending_actions_rounded,
        size: 48,
        color: widget.optionColor,
      ),
      barrierDismissible: false,
      onDismissed: () => Get.back(result: true),
    );
  }

  void _copyAccountNumberToClipboard() {
    final acct = _displayMethods[_selectedPaymentIndex].accountNumber;
    if (acct.isEmpty) return;
    Clipboard.setData(ClipboardData(text: acct));
    AppHaptics.gentle();
    appSnackbar(
      'Copied'.tr,
      'Account number copied to clipboard.'.tr,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      backgroundColor: widget.optionColor,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  /// The donor name held on the signed-in account. Empty for a guest session
  /// that has not filled a profile in yet, in which case the row shows a dash
  /// rather than an empty box.
  String get _accountName =>
      (sharedPreferences.getString('name_user') ?? '').trim();

  /// The account's phone number — the OTP-verified login identity.
  String get _accountPhone =>
      (sharedPreferences.getString('phone_user') ?? '').trim();

  int _parsedDonationAmount() {
    final n = int.tryParse(_moneyController.text.trim());
    if (n != null && n >= 1) return n;
    return widget.amount;
  }

  @override
  Widget build(BuildContext context) {
    final donationAmount = _parsedDonationAmount();

    return GradientScreen(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: 'Continue donation'),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(title: 'Donor details'),
                      const SizedBox(height: 12),
                      GlassPanel(
                        child: Column(
                          children: [
                            // Name and phone come from the verified account
                            // (changed in Profile), so they are shown as one
                            // quiet line instead of two boxes plus a note.
                            _DonorLine(
                              name: _accountName,
                              phone: formatPhoneForDisplay(_accountPhone),
                            ),
                            const SizedBox(height: 14),
                            _CheckoutTextField(
                              controller: _moneyController,
                              label: 'Amount',
                              hintText: 'Enter amount',
                              icon: Icons.payments_rounded,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: false,
                                    signed: false,
                                  ),
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter an amount'.tr;
                                }
                                final n = int.tryParse(value.trim());
                                if (n == null || n < 1) {
                                  return 'Enter a valid amount'.tr;
                                }
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),

                            const SizedBox(height: 14),
                            _CheckoutTextField(
                              controller: _noteController,
                              label: 'Message (optional)',
                              hintText: 'Add a note for this donation',
                              icon: Icons.edit_note_rounded,
                              maxLines: 2,
                              textInputAction: TextInputAction.newline,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Kind of donation'),
                      const SizedBox(height: 12),
                      // Reports the choice made on the step before this one
                      // rather than asking again, and offers the way back to
                      // change it — the tiles that used to sit here are that
                      // step now.
                      _ChosenKindRow(
                        channel: _channel,
                        accentColor: widget.optionColor,
                        onChange: _pickChannel,
                      ),
                      // M4 — the two paths, named. Skipped entirely for a
                      // campaign donation (its destination is already the
                      // campaign) and for operational support (running costs
                      // are not a project), so the question is only asked
                      // where it has two real answers.
                      if (widget.campaignsId == null &&
                          _channel.allowsProjectChoice) ...[
                        const SizedBox(height: 22),
                        const SectionLabel(title: 'Who should this help?'),
                        const SizedBox(height: 12),
                        AidTargetField(
                          selectedProject: _selectedProject,
                          accentColor: widget.optionColor,
                          onChanged: (p) =>
                              setState(() => _selectedProject = p),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Donation type'),
                      const SizedBox(height: 12),
                      // The three types this widget used to hardcode are rows
                      // in the dashboard now (migration 103), so it asks the
                      // server what to offer.
                      DonationTypeField(
                        selectedSlug: _donationType,
                        accentColor: widget.optionColor,
                        onSelected: (t) => setState(() => _donationType = t),
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Payment method'),
                      const SizedBox(height: 12),
                      // The catalogue could not be reached, so the cards below
                      // are the built-in defaults. Say so plainly rather than
                      // letting the donor assume they are seeing every option
                      // the organization currently accepts.
                      if (_paymentMethodsFailed) ...[
                        Text(
                          "We couldn't load the latest payment options, so these are the default ones."
                              .tr,
                          style: TextStyle(
                            color: AppThemeConfig.mutedText(context),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // The channel chosen a screen ago matched none of the
                      // methods we ended up with. Never silently widen the
                      // list — say what happened.
                      if (_channelHasNoMethods) ...[
                        _ChannelFallbackNote(channel: _channel),
                        const SizedBox(height: 12),
                      ],
                      ...List.generate(_displayMethods.length, (index) {
                        final paymentMethod = _displayMethods[index];
                        final isSelected = index == _selectedPaymentIndex;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PaymentMethodCard(
                            data: paymentMethod,
                            isSelected: isSelected,
                            accentColor: widget.optionColor,
                            onTap: () {
                              AppHaptics.selection();
                              setState(() => _selectedPaymentIndex = index);
                            },
                          ),
                        );
                      }),
                      if (_displayMethods[_selectedPaymentIndex]
                          .accountNumber
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _AccountCard(
                          accentColor: widget.optionColor,
                          method: _displayMethods[_selectedPaymentIndex],
                          onCopy: _copyAccountNumberToClipboard,
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: Obx(() {
                          final loading = _submitController.isSubmitting.value;
                          return FilledButton.icon(
                            onPressed: loading
                                ? null
                                : () => _handleConfirmDonation(),
                            icon: loading
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.lock_rounded),
                            label: Text(
                              loading
                                  ? 'Submitting…'.tr
                                  : 'Confirm @amount IQD donation'.trParams({
                                      'amount': _formatIQD(donationAmount),
                                    }),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.optionColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 17),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.accentColor,
    required this.method,
    required this.onCopy,
  });

  final Color accentColor;
  final _PaymentMethodData method;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final muted = AppThemeConfig.mutedText(context);
    final text = AppThemeConfig.text(context);
    final label = method.accountName.isNotEmpty
        ? method.accountName
        : method.title;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  method.accountNumber,
                  style: TextStyle(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            tooltip: 'Copy'.tr,
            icon: Icon(Icons.copy_rounded, size: 20, color: accentColor),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutTextField extends StatelessWidget {
  const _CheckoutTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.tr,
          style: TextStyle(
            color: AppThemeConfig.text(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: TextStyle(color: AppThemeConfig.text(context)),
          decoration: InputDecoration(
            hintText: hintText.tr,
            hintStyle: TextStyle(color: AppThemeConfig.mutedText(context)),
            prefixIcon: Icon(icon, color: AppThemeConfig.mutedText(context)),
            filled: true,
            fillColor: AppThemeConfig.softSurface(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: AppThemeConfig.border(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: AppThemeConfig.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: AppThemeConfig.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.data,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final _PaymentMethodData data;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isSelected ? accentColor : AppThemeConfig.border(context),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.12)
                    : AppThemeConfig.shadow(context),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                TileIcon(icon: data.icon, color: accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title.tr,
                        style: TextStyle(
                          color: AppThemeConfig.text(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.subtitle.tr,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: AppMotion.resolve(
                    context,
                    AppMotion.settleDuration,
                  ),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? accentColor : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? accentColor
                          : AppThemeConfig.border(context),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodData {
  const _PaymentMethodData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.methodType,
    this.accountNumber = '',
    this.accountName = '',
    this.submitName = '',
  });

  final String title; // localized display name
  final String subtitle; // localized instructions
  final IconData icon;

  /// The catalogue's own `method_type` — cash | bank | card | wallet | mobile.
  ///
  /// Carried through from [PaymentMethod] so the donation channel chosen one
  /// screen earlier can filter this list to the family the donor picked (M3).
  /// Without it the channel choice would be a label with nothing behind it.
  final String methodType;
  final String accountNumber; // '' → no transfer details for this method
  final String accountName;
  final String submitName; // canonical name (name_en) sent to the backend
}

/// Says why the payment list is wider than the channel the donor picked.
///
/// Only shown when the filter matched nothing — which happens when the
/// catalogue was readable on the step screen and unreachable here, so this
/// screen fell back to its built-in Cash/FIB pair. Widening the list without
/// saying so would turn the choice made a moment ago into a control that did
/// nothing.
class _ChannelFallbackNote extends StatelessWidget {
  const _ChannelFallbackNote({required this.channel});

  final DonationChannel channel;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${channel.titleKey.tr} — ${'this option is not available right now, so every method the organization accepts is shown below.'.tr}',
      style: TextStyle(
        color: AppThemeConfig.mutedText(context),
        fontSize: 12.5,
        height: 1.4,
      ),
    );
  }
}

/// Name and phone of the signed-in donor on one quiet line. Both come from the
/// verified account and are changed in Profile, so there is nothing to type
/// and no explanation is needed.
class _DonorLine extends StatelessWidget {
  const _DonorLine({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final muted = AppThemeConfig.mutedText(context);
    final text = AppThemeConfig.text(context);
    return Row(
      children: [
        Icon(Icons.person_rounded, size: 20, color: muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name.isEmpty ? '—' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: text, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        // Digits read left-to-right even in Arabic/Kurdish.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            phone.isEmpty ? '—' : phone,
            style: TextStyle(color: muted, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// The chosen kind of donation as one tappable row; tapping opens the picker.
class _ChosenKindRow extends StatelessWidget {
  const _ChosenKindRow({
    required this.channel,
    required this.accentColor,
    required this.onChange,
  });

  final DonationChannel channel;
  final Color accentColor;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        onTap: onChange,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Icon(Icons.category_rounded, size: 22, color: accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.titleKey.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ),
            Icon(
              Icons.unfold_more_rounded,
              size: 22,
              color: AppThemeConfig.mutedText(context),
            ),
          ],
        ),
      ),
    );
  }
}
