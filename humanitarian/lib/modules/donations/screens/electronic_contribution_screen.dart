// Step 2 — electronic payment (R2 #48).
//
// Card type, amount, currency, notes, one button. The card types are the
// organization's own electronic methods from the dashboard-managed catalogue
// (Visa, MasterCard, FIB, wallets…), so adding one there adds it here.
//
// NOT DONE HERE: handing the donor to a payment gateway. There is no gateway
// integration anywhere in this app or backend, so the contribution is recorded
// as pending with the chosen card type and staff confirm it — exactly what the
// old checkout did. A real gateway is a new integration (see the report, #48).
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/api/wallet_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/modules/donations/controllers/contribution_submitter.dart';
import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';
import 'package:flutter_application_1/modules/donations/widgets/contribution_kit.dart';

class ElectronicContributionScreen extends StatefulWidget {
  const ElectronicContributionScreen({super.key, this.campaignsId});

  /// Set when the donor came from a campaign; the gift is filed under it.
  final int? campaignsId;

  @override
  State<ElectronicContributionScreen> createState() =>
      _ElectronicContributionScreenState();
}

class _ElectronicContributionScreenState
    extends State<ElectronicContributionScreen> {
  static const _walletKey = 'app_wallet';

  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: kDefaultContributionCurrency);
  final _note = TextEditingController();

  List<PaymentMethod> _methods = const [];
  bool _loading = true;
  bool _failed = false;
  String? _selected; // PaymentMethod.nameEn, or _walletKey
  String? _selectError;
  int? _walletBalance;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final all = await fetchPaymentMethods();
      if (!mounted) return;
      setState(() {
        _methods = [
          for (final m in all)
            if (DonationChannel.electronic.acceptsMethodType(m.methodType)) m,
        ];
        _loading = false;
      });
    } catch (e) {
      debugPrint('Electronic contribution: catalogue unavailable: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
    try {
      final b = await fetchWalletBalance();
      if (mounted) setState(() => _walletBalance = b.balanceIQD);
    } catch (_) {
      // Unknown balance renders as nothing rather than a confident 0.
    }
  }

  Future<void> _confirm() async {
    final okForm = _form.currentState!.validate();
    setState(
      () => _selectError = _selected == null ? 'Choose a card type'.tr : null,
    );
    if (!okForm || _selected == null) return;

    setState(() => _submitting = true);
    final ok = await submitMoneyContribution(
      context,
      MoneyContribution(
        amount: int.parse(_amount.text.trim()),
        currency: _currency.text.trim().toUpperCase(),
        method: _selected!,
        channel: 'electronic',
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        campaignsId: widget.campaignsId,
      ),
    );
    if (mounted && !ok) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final options = <ContributionOption<String>>[
      for (final m in _methods) ContributionOption(m.nameEn, m.localizedName),
      if (DonationChannel.electronic.includesAppWallet)
        const ContributionOption(_walletKey, 'App wallet'),
    ];
    return Form(
      key: _form,
      child: ContributionScaffold(
        title: 'Electronic payment'.tr,
        submitting: _submitting,
        onConfirm: _confirm,
        children: [
          ContributionLabelled(
            label: 'Card type',
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
                    child: LinearProgressIndicator(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_failed)
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('Could not load. Tap to retry.'.tr),
                        ),
                      ContributionChoice<String>(
                        options: options,
                        selected: _selected,
                        onChanged: (v) => setState(() {
                          _selected = v;
                          _selectError = null;
                        }),
                      ),
                      if (_selected == _walletKey && _walletBalance != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xs),
                          child: Text(
                            '${'Balance'.tr}: '
                            '${NumberFormat('#,##0').format(_walletBalance)} '
                            '${localizedCurrency('IQD')}',
                          ),
                        ),
                      if (_selectError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xxs),
                          child: Text(
                            _selectError!,
                            style: TextStyle(
                              fontSize: AppType.dense,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          ContributionAmountRow(amount: _amount, currency: _currency),
          ContributionTextField(label: 'Notes', controller: _note, maxLines: 3),
        ],
      ),
    );
  }
}
