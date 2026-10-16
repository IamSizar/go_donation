// The small set of pieces every contribution page is built from (R2 #47–55).
//
// WHY THIS FILE EXISTS
// The client asked for the donation flow to be two steps: pick one of four ways
// to give, then ONE fixed page per way, each ending in the same bottom button.
// Four pages that all look and behave alike is a kit, not four copies of a
// form — so the scaffold (title, scrolling body, pinned button), the labelled
// field, the choice pills and the photo tile live here once.
//
// What is deliberately NOT here: any explanation text under a field. The old
// screens explained every option in a sentence; the client called that clutter.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/phone_format.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_screen.dart';
import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/shared/utils/image_pick.dart';

/// The single fixed line shown on every money page (R2 #55). It replaces the
/// donation-type picker (عام / زكاة / صدقة) and «التبرع لمؤسسة», which the
/// client asked to remove.
const String kContributionNoticeKey =
    'Note: a small percentage of contributions is deducted to cover operating '
    'costs and keep the project running.';

/// Title + scrolling fields + a pinned bottom bar with the one button.
class ContributionScaffold extends StatelessWidget {
  const ContributionScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.onConfirm,
    this.submitting = false,
    this.showNotice = true,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onConfirm;
  final bool submitting;

  /// Money pages show the operating-costs line; the in-kind page has no money
  /// to deduct from, so it does not.
  final bool showNotice;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppScreen(
      title: title,
      scrollable: true,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showNotice)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text(
                kContributionNoticeKey.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppType.meta + 1,
                  height: AppType.leadDense,
                  color: c.inkSecondary,
                ),
              ),
            ),
          ElevatedButton(
            onPressed: submitting ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text('Confirm contribution'.tr),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.md),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A label above its control. The label is the only text a field gets.
class ContributionLabelled extends StatelessWidget {
  const ContributionLabelled({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.tr,
          style: TextStyle(
            fontSize: AppType.dense,
            fontWeight: FontWeight.w700,
            color: AppColors.of(context).inkSecondary,
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        child,
      ],
    );
  }
}

/// A labelled text field. [ltr] keeps digits, phone numbers and serials
/// left-to-right inside an Arabic screen.
class ContributionTextField extends StatelessWidget {
  const ContributionTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.maxLines = 1,
    this.ltr = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final bool ltr;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ContributionLabelled(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        maxLines: maxLines,
        onChanged: onChanged,
        textDirection: ltr ? TextDirection.ltr : null,
        // Digits and phone numbers run left-to-right, but the field still
        // aligns to the screen's own start edge so it lines up with its
        // label on an Arabic screen.
        textAlign: ltr
            ? (Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left)
            : TextAlign.start,
        decoration: InputDecoration(hintText: hint?.tr),
      ),
    );
  }
}

/// The currency a contribution is made in unless the donor says otherwise.
/// A code, not a label: it is what the server stores. It is shown to the donor
/// through [localizedCurrency], never raw.
const String kDefaultContributionCurrency = 'IQD';

/// The amount, then the currency: IQD by default, dollars in one tap, anything
/// else typed as a three-letter code (R2 #48: "other currencies manual").
class ContributionAmountRow extends StatefulWidget {
  const ContributionAmountRow({
    super.key,
    required this.amount,
    required this.currency,
  });

  final TextEditingController amount;

  /// Holds the three-letter code that will be sent. Starts as
  /// [kDefaultContributionCurrency].
  final TextEditingController currency;

  /// The server's ceiling (backend donations.maxAmount). Checked here so the
  /// donor is told before sending, not after.
  static const int maxAmount = 10000000000;

  static String? validateAmount(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < 1) return 'Enter a valid amount'.tr;
    if (n > maxAmount) return 'Enter a valid amount'.tr;
    return null;
  }

  static String? validateCurrency(String? v) {
    final t = (v ?? '').trim();
    if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(t)) return 'Currency code'.tr;
    return null;
  }

  @override
  State<ContributionAmountRow> createState() => _ContributionAmountRowState();
}

class _ContributionAmountRowState extends State<ContributionAmountRow> {
  static const _other = 'other';
  static const _presets = <String>['IQD', 'USD'];

  late String _choice = _presets.contains(widget.currency.text.toUpperCase())
      ? widget.currency.text.toUpperCase()
      : _other;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContributionTextField(
          label: 'Amount',
          controller: widget.amount,
          keyboardType: TextInputType.number,
          ltr: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: ContributionAmountRow.validateAmount,
        ),
        const SizedBox(height: AppSpace.sm),
        ContributionChoice<String>(
          options: [
            for (final code in _presets)
              ContributionOption(code, localizedCurrency(code)),
            const ContributionOption(_other, 'Other currency'),
          ],
          selected: _choice,
          onChanged: (v) => setState(() {
            _choice = v;
            if (v != _other) {
              widget.currency.text = v;
            } else if (_presets.contains(widget.currency.text.toUpperCase())) {
              widget.currency.clear();
            }
          }),
        ),
        if (_choice == _other) ...[
          const SizedBox(height: AppSpace.sm),
          ContributionTextField(
            label: 'Currency code',
            controller: widget.currency,
            ltr: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
              LengthLimitingTextInputFormatter(3),
              _UpperCase(),
            ],
            validator: ContributionAmountRow.validateCurrency,
          ),
        ],
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// One option in a [ContributionChoice].
class ContributionOption<T> {
  const ContributionOption(this.value, this.label);
  final T value;

  /// Already translated (catalogue names) or a key — `.tr` is applied, and an
  /// unknown key shows as written.
  final String label;
}

/// A row of pills; exactly one is selected. Wraps when it must.
class ContributionChoice<T> extends StatelessWidget {
  const ContributionChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ContributionOption<T>> options;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        for (final o in options)
          Builder(
            builder: (context) {
              final on = o.value == selected;
              return Semantics(
                button: true,
                selected: on,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  onTap: () => onChanged(o.value),
                  child: Container(
                    // A fixed height and a shrink-wrapped Row: a Container
                    // with `alignment` would expand to the full row width.
                    height: 44,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: on
                          ? AppThemeConfig.accent(context)
                          : AppThemeConfig.surface(context),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: on
                            ? AppThemeConfig.accent(context)
                            : AppThemeConfig.border(context),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          o.label.tr,
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w700,
                            color: on
                                ? AppThemeConfig.onAccent(context)
                                : c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Two-way switch at the top of a page (balance transfer: «تعبئة / تحويل
/// مباشر» vs «إرسال كرت»). Equal halves, selected one filled.
class ContributionToggle<T> extends StatelessWidget {
  const ContributionToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ContributionOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.groundSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: o.value == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(o.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 46),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: o.value == selected
                          ? AppThemeConfig.accent(context)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.md - 4),
                    ),
                    child: Text(
                      o.label.tr,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: o.value == selected
                            ? AppThemeConfig.onAccent(context)
                            : c.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A photo slot: empty tile → thumbnail with a remove control. Holds only the
/// local path; the page uploads it when the donor confirms, so a form that is
/// abandoned uploads nothing.
class ContributionPhotoTile extends StatelessWidget {
  const ContributionPhotoTile({
    super.key,
    required this.label,
    required this.path,
    required this.onChanged,
    this.source,
    this.errorText,
  });

  final String label;
  final String? path;
  final ValueChanged<String?> onChanged;

  /// Null asks the donor to choose camera or gallery; a value skips the sheet.
  final ImageSource? source;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final picked = await pickCroppedImage(
      context,
      source: source,
      // A receipt, a card and a photo of goods are all read for what they
      // show, so the file is sent as the donor took it — no crop, no resize.
      fidelity: PhotoFidelity.document,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final has = path != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: label.tr,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _pick(context),
            child: Container(
              height: has ? 160 : 72,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppThemeConfig.surface(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: errorText != null
                      ? Theme.of(context).colorScheme.error
                      : AppThemeConfig.border(context),
                ),
              ),
              child: has
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // The whole picture, not a crop: a receipt or card is checked for
                        // what it says at the edges too.
                        ColoredBox(
                          color: c.groundSunken,
                          child: Image.file(File(path!), fit: BoxFit.contain),
                        ),
                        PositionedDirectional(
                          top: AppSpace.xs,
                          end: AppSpace.xs,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Remove'.tr,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () => onChanged(null),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, color: c.inkSecondary),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          label.tr,
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(
              errorText!,
              style: TextStyle(
                fontSize: AppType.dense,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// A read-only value with a copy button — the organization's number on the
/// balance-transfer page.
class ContributionCopyRow extends StatelessWidget {
  const ContributionCopyRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ContributionLabelled(
      label: label,
      child: Container(
        padding: const EdgeInsetsDirectional.only(
          start: AppSpace.md,
          end: AppSpace.xs,
        ),
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: AppThemeConfig.surface(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppThemeConfig.border(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  value,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy'.tr,
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                Get.snackbar(
                  'Copied'.tr,
                  value,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(AppSpace.md),
                  duration: const Duration(seconds: 2),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The donor's phone, pre-filled from the account and still editable
/// (R2 #49–51). Shown the way the rest of the app shows numbers.
String contributionPhoneDefault() =>
    formatPhoneForDisplay(sharedPreferences.getString('phone_user'));

/// The donor's saved address, pre-filled and still editable (R2 #49–51).
String contributionAddressDefault() =>
    (sharedPreferences.getString('address_user') ?? '').trim();
