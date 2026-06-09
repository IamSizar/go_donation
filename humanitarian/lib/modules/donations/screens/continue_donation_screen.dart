import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/donations/controllers/continue_donation_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

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

  @override
  State<ContinueDonationScreen> createState() => _ContinueDonationScreenState();
}

class _ContinueDonationScreenState extends State<ContinueDonationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _moneyController = TextEditingController();
  final _noteController = TextEditingController();

  late final ContinueDonationController _submitController;

  int _selectedPaymentIndex = 0;

  static const String _fibAccountNumber = '7510208962';

  static const List<_PaymentMethodData> _paymentMethods = [
    _PaymentMethodData(
      title: 'Cash',
      subtitle: 'Pay in person or at a collection point',
      icon: Icons.payments_rounded,
    ),
    _PaymentMethodData(
      title: 'FIB',
      subtitle: 'First Iraqi Bank and supported channels',
      icon: Icons.account_balance_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<ContinueDonationController>()) {
      Get.delete<ContinueDonationController>();
    }
    _submitController = Get.put(ContinueDonationController());
    final i = _paymentMethods.indexWhere(
      (m) => m.title == widget.paymentMethod,
    );
    if (i >= 0) {
      _selectedPaymentIndex = i;
    }
    _moneyController.text = widget.amount.toString();
  }

  @override
  void dispose() {
    if (Get.isRegistered<ContinueDonationController>()) {
      Get.delete<ContinueDonationController>();
    }
    _nameController.dispose();
    _emailController.dispose();
    _moneyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirmDonation() async {
    if (!_formKey.currentState!.validate()) return;

    final paymentMethod = _paymentMethods[_selectedPaymentIndex];
    final amount = int.parse(_moneyController.text.trim());
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    final note = _noteController.text.trim();

    final err = await _submitController.submitDonation(
      userId: userId,
      campaignsId: widget.campaignsId,
      message: note.isEmpty ? null : note,
      amount: amount,
      paymentMethod: paymentMethod.title,
    );

    if (!mounted) return;

    if (err != null) {
      Get.snackbar(
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

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.pending_actions_rounded,
            size: 48,
            color: widget.optionColor,
          ),
          title: Text(
            'Pending successfully'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Your donation was submitted and is pending. Thank you.'.tr,
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Get.back(result: true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: widget.optionColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
              child: Text('OK'.tr),
            ),
          ],
        );
      },
    );
  }

  void _copyFibAccountNumberToClipboard() {
    Clipboard.setData(ClipboardData(text: _fibAccountNumber));
    AppHaptics.gentle();
    Get.snackbar(
      'Copied'.tr,
      'Account number copied to clipboard.'.tr,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      backgroundColor: widget.optionColor,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

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
                      _CheckoutHeroCard(
                        amount: widget.amount,
                        optionTitle: widget.optionTitle,
                        optionSummary: widget.optionSummary,
                        optionTypeLabel: widget.optionTypeLabel,
                        optionIcon: widget.optionIcon,
                        optionColor: widget.optionColor,
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Donor details'),
                      const SizedBox(height: 12),
                      GlassPanel(
                        child: Column(
                          children: [
                            _CheckoutTextField(
                              controller: _nameController
                                ..text =
                                    sharedPreferences.getString('name_user') ??
                                    '',
                              label: 'Full name',
                              hintText: 'Your name',
                              icon: Icons.person_rounded,
                              textInputAction: TextInputAction.next,
                              enabled: false,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your name'.tr;
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 14),
                            _CheckoutTextField(
                              controller: _emailController
                                ..text =
                                    sharedPreferences.getString('phone_user') ??
                                    '',
                              label: 'Phone',
                              hintText: 'Your phone number',
                              icon: Icons.phone_rounded,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              enabled: false,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your phone number'.tr;
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 14),
                            _CheckoutTextField(
                              controller: _moneyController,
                              label: 'Amount',
                              hintText: 'Enter amount',
                              icon: Icons.attach_money_rounded,
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
                              maxLines: 3,
                              textInputAction: TextInputAction.newline,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Payment method'),
                      const SizedBox(height: 12),
                      ...List.generate(_paymentMethods.length, (index) {
                        final paymentMethod = _paymentMethods[index];
                        final isSelected = index == _selectedPaymentIndex;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PaymentMethodCard(
                            data: paymentMethod,
                            isSelected: isSelected,
                            accentColor: widget.optionColor,
                            onTap: () {
                              setState(() => _selectedPaymentIndex = index);
                            },
                          ),
                        );
                      }),
                      if (_paymentMethods[_selectedPaymentIndex].title ==
                          'FIB') ...[
                        const SizedBox(height: 8),
                        _FibAccountCard(
                          accentColor: widget.optionColor,
                          accountNumber: _fibAccountNumber,
                          onCopy: _copyFibAccountNumberToClipboard,
                        ),
                      ],
                      const SizedBox(height: 22),
                      const SectionLabel(title: 'Donation summary'),
                      const SizedBox(height: 12),
                      GlassPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                TileIcon(
                                  icon: widget.optionIcon,
                                  color: widget.optionColor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.optionTitle.tr,
                                        style: TextStyle(
                                          color: AppThemeConfig.text(context),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.optionSupportNote.tr,
                                        style: TextStyle(
                                          color: AppThemeConfig.mutedText(
                                            context,
                                          ),
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _SummaryLine(
                              label: 'Donation amount',
                              value: '$donationAmount IQD',
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1),
                            ),
                            _SummaryLine(
                              label: 'Total',
                              value: '$donationAmount IQD',
                              isEmphasized: true,
                            ),
                          ],
                        ),
                      ),
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
                                      'amount': donationAmount.toString(),
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

class _CheckoutHeroCard extends StatelessWidget {
  const _CheckoutHeroCard({
    required this.amount,
    required this.optionTitle,
    required this.optionSummary,
    required this.optionTypeLabel,
    required this.optionIcon,
    required this.optionColor,
  });

  final int amount;
  final String optionTitle;
  final String optionSummary;
  final String optionTypeLabel;
  final IconData optionIcon;
  final Color optionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            optionColor,
            optionColor.withValues(alpha: 0.84),
            const Color(0xFF2563EB),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: optionColor.withValues(alpha: 0.24),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(optionIcon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  optionTypeLabel.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Review your donation'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            optionSummary.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroMetricChip(icon: Icons.favorite_rounded, label: optionTitle),
              _HeroMetricChip(
                icon: Icons.payments_rounded,
                label: '@amount IQD ready'.trParams({
                  'amount': amount.toString(),
                }),
              ),
              const _HeroMetricChip(
                icon: Icons.shield_rounded,
                label: 'Secure step',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetricChip extends StatelessWidget {
  const _HeroMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FibAccountCard extends StatelessWidget {
  const _FibAccountCard({
    required this.accentColor,
    required this.accountNumber,
    required this.onCopy,
  });

  final Color accentColor;
  final String accountNumber;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final muted = AppThemeConfig.mutedText(context);
    final text = AppThemeConfig.text(context);

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
                  'FIB account'.tr,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  accountNumber,
                  style: TextStyle(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
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
    this.enabled = true,
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
  final bool enabled;
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
          enabled: enabled,
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
                  duration: const Duration(milliseconds: 220),
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

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.isEmphasized = false,
  });

  final String label;
  final String value;
  final bool isEmphasized;

  @override
  Widget build(BuildContext context) {
    final color = isEmphasized
        ? AppThemeConfig.text(context)
        : AppThemeConfig.mutedText(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label.tr,
            style: TextStyle(
              color: color,
              fontWeight: isEmphasized ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppThemeConfig.text(context),
            fontWeight: isEmphasized ? FontWeight.w800 : FontWeight.w700,
            fontSize: isEmphasized ? 18 : 15,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodData {
  const _PaymentMethodData({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}
