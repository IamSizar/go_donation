// Step 2 — in-kind contributions (R2 #51).
//
// Material type, phone, address (both pre-filled and editable) and an optional
// photo of the items. No amount and no payment method: goods are not money.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/inkind_categories_api.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/modules/donations/controllers/contribution_submitter.dart';
import 'package:flutter_application_1/modules/donations/widgets/contribution_kit.dart';
import 'dart:io';

class InKindContributionScreen extends StatefulWidget {
  const InKindContributionScreen({super.key});

  @override
  State<InKindContributionScreen> createState() =>
      _InKindContributionScreenState();
}

class _InKindContributionScreenState extends State<InKindContributionScreen> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController(text: contributionAddressDefault());
  final _phone = TextEditingController(text: contributionPhoneDefault());
  final _other = TextEditingController();

  List<InkindCategory> _categories = const [];
  bool _loading = true;
  InkindCategory? _selected;
  String? _selectError;
  String? _photo;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _other.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await fetchInkindCategories();
    if (!mounted) return;
    setState(() {
      _categories = list;
      _loading = false;
    });
  }

  Future<void> _confirm() async {
    final okForm = _form.currentState!.validate();
    // With no vocabulary at all (offline), the type is typed by hand.
    final typed = _other.text.trim();
    final hasType = _selected != null || typed.isNotEmpty;
    setState(
      () => _selectError = hasType ? null : 'Choose the type of items'.tr,
    );
    if (!okForm || !hasType) return;
    if (!await requireUpgrade(context)) return;
    if (!mounted) return;

    setState(() => _submitting = true);
    try {
      String? uploaded;
      if (_photo != null) {
        uploaded = await const ModuleApi().uploadPhoto(File(_photo!));
      }
      final category = _selected?.nameEn.isNotEmpty == true
          ? _selected!.nameEn
          : typed;
      await const ModuleApi().postJson(inKindDonationsUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'category': category,
        // The server requires an item name; the type IS the description here.
        'item_name': category,
        'pickup_address': _address.text.trim(),
        'donor_phone': _phone.text.trim(),
        if (uploaded != null) 'photo_path': uploaded,
      });
      if (!mounted) return;
      await finishInKindContribution(context);
    } catch (e) {
      debugPrint('in-kind contribution failed: $e');
      showContributionError(
        'The contribution could not be sent. Try again.'.tr,
      );
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ContributionScaffold(
        title: 'In-kind contributions'.tr,
        showNotice: false,
        submitting: _submitting,
        onConfirm: _confirm,
        children: [
          ContributionLabelled(
            label: 'Type of items',
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
                    child: LinearProgressIndicator(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_categories.isNotEmpty)
                        ContributionChoice<InkindCategory>(
                          options: [
                            for (final c in _categories)
                              ContributionOption(c, c.localizedName),
                          ],
                          selected: _selected,
                          onChanged: (v) => setState(() {
                            _selected = v;
                            _selectError = null;
                          }),
                        )
                      else
                        TextFormField(
                          controller: _other,
                          decoration: InputDecoration(
                            hintText: 'Food, clothing, furniture…'.tr,
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
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the address'.tr : null,
          ),
          ContributionPhotoTile(
            label: 'Photo of the items',
            path: _photo,
            onChanged: (p) => setState(() => _photo = p),
          ),
        ],
      ),
    );
  }
}
