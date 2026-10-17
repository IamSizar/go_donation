import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/payment_methods_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/core/app_snackbar.dart';

/// R2 #67 — add money to the wallet. The user pays with one of the same
/// methods donations use, then sends a request here. Nothing in the wallet
/// changes until staff confirm the payment in the dashboard; the request shows
/// as waiting until then.
class WalletTopUpScreen extends StatefulWidget {
  const WalletTopUpScreen({super.key});

  @override
  State<WalletTopUpScreen> createState() => _WalletTopUpScreenState();
}

class _WalletTopUpScreenState extends State<WalletTopUpScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<PaymentMethod> _methods = const [];
  bool _methodsFailed = false;
  int _selected = 0;
  String? _proofPath;
  bool _busy = false;
  List<Map<String, dynamic>> _mine = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // The in-app wallet is not a way to fund the wallet.
      final all = await fetchPaymentMethods();
      if (mounted) {
        setState(() {
          _methods = all.where((m) => m.methodType != 'wallet').toList();
          _methodsFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _methodsFailed = true);
    }
    try {
      final res = await const ModuleApi().getObject(walletTopupRequestsUrl);
      final items = res['items'];
      if (mounted && items is List) {
        setState(() {
          _mine = [
            for (final i in items)
              if (i is Map) Map<String, dynamic>.from(i),
          ];
        });
      }
    } catch (_) {
      // The list is a convenience; the form still works without it.
    }
  }

  PaymentMethod? get _method => _methods.isEmpty
      ? null
      : _methods[_selected.clamp(0, _methods.length - 1)];

  Future<void> _pickProof() async {
    final path = await pickCroppedImage(context);
    if (path != null && mounted) setState(() => _proofPath = path);
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amount.text.trim());
    final method = _method;
    if (amount == null || amount < 1) {
      appSnackbar('Add funds'.tr, 'Enter a valid amount'.tr);
      return;
    }
    if (method == null) {
      appSnackbar('Add funds'.tr, 'Choose how you paid.'.tr);
      return;
    }
    // A general-user or guest account cannot add funds. Same upgrade prompt the
    // Contribute screen shows, asked before anything is sent.
    if (!await requireUpgrade(context)) return;
    setState(() => _busy = true);
    try {
      String? proof;
      if (_proofPath != null) {
        proof = await const ModuleApi().uploadPhoto(File(_proofPath!));
      }
      await const ModuleApi().postJson(walletTopupRequestsUrl, {
        'amount_iqd': amount,
        'payment_method': method.nameEn.isNotEmpty
            ? method.nameEn
            : method.localizedName,
        'note': _note.text.trim(),
        if (proof != null) 'proof_path': proof,
      });
      AppHaptics.success();
      _amount.clear();
      _note.clear();
      setState(() => _proofPath = null);
      appSnackbar(
        'Add funds'.tr,
        'Your request was sent. Your wallet is credited once our team confirms the payment.'
            .tr,
        duration: const Duration(seconds: 5),
        snackPosition: SnackPosition.BOTTOM,
      );
      await _load();
    } catch (e) {
      appSnackbar(
        'Add funds'.tr,
        failureMessage(e, 'error_wallet_topup_failed'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppThemeConfig.mutedText(context);
    final method = _method;
    return AppScreen(
      title: 'Add funds',
      scrollable: true,
      bottomBar: FilledButton(
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text('Send request'.tr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pay with one of these methods, then send the request. Your wallet is credited once our team confirms the payment.'
                .tr,
            style: TextStyle(color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (_methodsFailed)
            Text(
              "We couldn't load the latest payment options, so these are the default ones."
                  .tr,
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          for (var i = 0; i < _methods.length; i++) ...[
            _MethodTile(
              method: _methods[i],
              selected: i == _selected,
              onTap: () => setState(() => _selected = i),
            ),
            if (i == _selected && _methods[i].accountNumber.isNotEmpty) ...[
              const SizedBox(height: 8),
              _AccountTile(method: _methods[i]),
            ],
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Amount'.tr,
              hintText: 'Enter amount'.tr,
              suffixText: localizedCurrency('IQD'),
              prefixIcon: const Icon(Icons.payments_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Transfer reference (optional)'.tr,
              prefixIcon: const Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickProof,
            icon: Icon(
              _proofPath == null
                  ? Icons.add_a_photo_outlined
                  : Icons.check_circle_rounded,
            ),
            label: Text(
              _proofPath == null
                  ? 'Attach proof of payment (optional)'.tr
                  : 'Proof attached'.tr,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (_mine.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'My requests'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 10),
            for (final r in _mine) _RequestRow(row: r),
          ],
          if (method == null && !_methodsFailed) const SizedBox(height: 4),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeConfig.accent(context);
    // Ink paints on the nearest Material; without this one it is the page's own,
    // outside the scroll view, so the tile's border escapes the clip.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeConfig.surface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent : AppThemeConfig.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? accent : AppThemeConfig.mutedText(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.localizedName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    if (method.localizedInstructions.isNotEmpty)
                      Text(
                        method.localizedInstructions,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.method});

  final PaymentMethod method;

  @override
  Widget build(BuildContext context) {
    final label = method.accountName.isNotEmpty
        ? method.accountName
        : method.localizedName;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                SelectableText(
                  method.accountNumber,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: 'Copy'.tr,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: method.accountNumber));
              AppHaptics.gentle();
              appSnackbar(
                'Copied'.tr,
                'Account number copied to clipboard.'.tr,
                duration: const Duration(seconds: 2),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = (row['status'] ?? 'pending').toString();
    final amount = int.tryParse('${row['amount_iqd']}') ?? 0;
    final label = switch (status) {
      'approved' => 'Approved'.tr,
      'rejected' => 'Rejected'.tr,
      _ => 'Waiting for approval'.tr,
    };
    final color = switch (status) {
      'approved' => AppThemeConfig.accent(context),
      'rejected' => Theme.of(context).colorScheme.error,
      _ => AppThemeConfig.pending(context),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${NumberFormat('#,##0').format(amount)} ${localizedCurrency('IQD')}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    (row['payment_method'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
