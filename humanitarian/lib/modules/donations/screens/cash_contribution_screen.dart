// Step 2 — direct cash handover (R2 #50).
//
// Amount, address, phone, and an optional note about when to visit. Phone and
// address come from the account and stay editable, because the person handing
// over cash may be at a different place or number than the one on file.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/modules/donations/controllers/contribution_submitter.dart';
import 'package:flutter_application_1/modules/donations/models/donation_channel.dart';
import 'package:flutter_application_1/modules/donations/widgets/contribution_kit.dart';

class CashContributionScreen extends StatefulWidget {
  const CashContributionScreen({super.key, this.campaignsId});

  final int? campaignsId;

  @override
  State<CashContributionScreen> createState() => _CashContributionScreenState();
}

class _CashContributionScreenState extends State<CashContributionScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: kDefaultContributionCurrency);
  final _address = TextEditingController(text: contributionAddressDefault());
  final _phone = TextEditingController(text: contributionPhoneDefault());
  final _visit = TextEditingController();

  /// The catalogue's name for cash, so staff see the same word they set up.
  String _method = 'Cash';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMethod();
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _address.dispose();
    _phone.dispose();
    _visit.dispose();
    super.dispose();
  }

  Future<void> _loadMethod() async {
    try {
      final all = await fetchPaymentMethods();
      for (final m in all) {
        if (DonationChannel.cash.acceptsMethodType(m.methodType) &&
            m.nameEn.isNotEmpty) {
          if (mounted) setState(() => _method = m.nameEn);
          return;
        }
      }
    } catch (e) {
      debugPrint('Cash contribution: catalogue unavailable: $e');
    }
  }

  Future<void> _confirm() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    final visit = _visit.text.trim();
    final ok = await submitMoneyContribution(
      context,
      MoneyContribution(
        amount: int.parse(_amount.text.trim()),
        currency: _currency.text.trim().toUpperCase(),
        method: _method,
        channel: 'cash',
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        visitNote: visit.isEmpty ? null : visit,
        campaignsId: widget.campaignsId,
      ),
    );
    if (mounted && !ok) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ContributionScaffold(
        title: 'Direct cash handover'.tr,
        submitting: _submitting,
        onConfirm: _confirm,
        children: [
          ContributionAmountRow(amount: _amount, currency: _currency),
          ContributionTextField(
            label: 'Address',
            controller: _address,
            maxLines: 2,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the address'.tr : null,
          ),
          ContributionTextField(
            label: 'Phone',
            controller: _phone,
            ltr: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 7
                ? 'Enter a valid phone number'.tr
                : null,
          ),
          ContributionTextField(
            label: 'Visit time',
            controller: _visit,
            hint: 'Best time for us to visit',
          ),
        ],
      ),
    );
  }
}
