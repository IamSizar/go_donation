// Step 2 — balance transfer (R2 #49).
//
// ONE fixed page with two toggles at the top. «تعبئة / تحويل مباشر» sends credit
// to the organization's number and attaches the screenshot of the transfer;
// «إرسال كرت» photographs a recharge card and gives its serial. Switching the
// toggle changes the fields in place — the page, the attachment slot, the
// notes box and the confirm button do not move.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/modules/donations/controllers/contribution_submitter.dart';
import 'package:flutter_application_1/modules/donations/widgets/contribution_kit.dart';

enum _Kind { transfer, card }

class BalanceTransferContributionScreen extends StatefulWidget {
  const BalanceTransferContributionScreen({super.key, this.campaignsId});

  final int? campaignsId;

  @override
  State<BalanceTransferContributionScreen> createState() =>
      _BalanceTransferContributionScreenState();
}

class _BalanceTransferContributionScreenState
    extends State<BalanceTransferContributionScreen> {
  static const _networks = <ContributionOption<String>>[
    ContributionOption('asiacell', 'Asiacell'),
    ContributionOption('zain', 'Zain'),
    ContributionOption('korek', 'Korek'),
  ];

  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: kDefaultContributionCurrency);
  final _serial = TextEditingController();
  final _note = TextEditingController();
  // Pre-filled from the account and still editable (R2 #49).
  final _phone = TextEditingController(text: contributionPhoneDefault());
  final _address = TextEditingController(text: contributionAddressDefault());

  _Kind _kind = _Kind.transfer;
  String? _network;
  String? _networkError;
  String? _photo;
  String? _photoError;
  List<PaymentMethod> _mobile = const [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _serial.dispose();
    _note.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadMethods() async {
    try {
      final all = await fetchPaymentMethods();
      if (!mounted) return;
      setState(
        () => _mobile = [
          for (final m in all)
            if (m.methodType == 'mobile') m,
        ],
      );
    } catch (e) {
      // The number is a convenience on the transfer toggle; without it the
      // page still works.
      debugPrint('Balance transfer: catalogue unavailable: $e');
    }
  }

  /// The organization's number for the chosen network: a mobile method named
  /// after the network wins, else the first mobile method that has a number.
  String get _orgNumber {
    final withNumber = _mobile.where((m) => m.accountNumber.trim().isNotEmpty);
    if (_network != null) {
      for (final m in withNumber) {
        if ('${m.nameEn} ${m.accountName}'.toLowerCase().contains(_network!)) {
          return m.accountNumber.trim();
        }
      }
    }
    return withNumber.isEmpty ? '' : withNumber.first.accountNumber.trim();
  }

  /// The method name staff see: the catalogue's own where it has one.
  String get _methodName {
    final hint = _kind == _Kind.card ? 'recharge' : 'transfer';
    for (final m in _mobile) {
      if (m.nameEn.toLowerCase().contains(hint)) return m.nameEn;
    }
    return _kind == _Kind.card
        ? 'Mobile recharge card'
        : 'Mobile balance transfer';
  }

  Future<void> _confirm() async {
    final okForm = _form.currentState!.validate();
    setState(() {
      _networkError = _network == null ? 'Choose a network'.tr : null;
      _photoError = _photo == null
          ? (_kind == _Kind.card
                ? 'Photograph the card'.tr
                : 'Attach the transfer screenshot'.tr)
          : null;
    });
    if (!okForm || _network == null || _photo == null) return;

    setState(() => _submitting = true);
    final note = _note.text.trim();
    final ok = await submitMoneyContribution(
      context,
      MoneyContribution(
        amount: int.parse(_amount.text.trim()),
        currency: _currency.text.trim().toUpperCase(),
        method: _methodName,
        channel: 'balance_transfer',
        transferKind: _kind == _Kind.card ? 'card' : 'transfer',
        network: _network,
        serialNumber: _kind == _Kind.card ? _serial.text.trim() : null,
        attachmentLocalPath: _photo,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        note: note.isEmpty ? null : note,
        campaignsId: widget.campaignsId,
      ),
    );
    if (mounted && !ok) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isCard = _kind == _Kind.card;
    final number = _orgNumber;
    return Form(
      key: _form,
      child: ContributionScaffold(
        title: 'Balance transfer'.tr,
        submitting: _submitting,
        onConfirm: _confirm,
        children: [
          ContributionToggle<_Kind>(
            options: const [
              ContributionOption(_Kind.transfer, 'Top-up / direct transfer'),
              ContributionOption(_Kind.card, 'Send a card'),
            ],
            selected: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              // The slot is shared, but a screenshot is not a card photo.
              _photo = null;
              _photoError = null;
            }),
          ),
          ContributionLabelled(
            label: 'Network',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ContributionChoice<String>(
                  options: _networks,
                  selected: _network,
                  onChanged: (v) => setState(() {
                    _network = v;
                    _networkError = null;
                  }),
                ),
                if (_networkError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Text(
                      _networkError!,
                      style: TextStyle(
                        fontSize: AppType.dense,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!isCard && number.isNotEmpty)
            ContributionCopyRow(label: 'Our number', value: number),
          if (isCard)
            ContributionTextField(
              label: 'Card serial number',
              controller: _serial,
              ltr: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\- ]')),
                LengthLimitingTextInputFormatter(40),
              ],
              validator: (v) => (v ?? '').trim().length < 6
                  ? 'Enter the serial number'.tr
                  : null,
            ),
          ContributionAmountRow(amount: _amount, currency: _currency),
          ContributionPhotoTile(
            label: isCard ? 'Photograph the card' : 'Attach the screenshot',
            path: _photo,
            // «photograph card with camera» / «screenshot attach».
            source: isCard ? ImageSource.camera : ImageSource.gallery,
            errorText: _photoError,
            onChanged: (p) => setState(() {
              _photo = p;
              _photoError = null;
            }),
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
            label: 'Address',
            controller: _address,
            maxLines: 2,
          ),
          ContributionTextField(label: 'Notes', controller: _note, maxLines: 3),
        ],
      ),
    );
  }
}
