import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_my_profile_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #42 — Marriage/engagement profile form with a privacy (visibility) control.
/// Submits to POST /api/marriage. The backend restricts this to the eligible
/// role; the entry tile is only shown to eligible users.
///
/// Note #33 — gender/age/city/social_summary/private_notes are now
/// Field-Rules-driven (GET /api/registration/field-rules, "marriage_" keys,
/// same mechanism as the general registration form's #43): a field the admin
/// marked required is enforced before submit, and one marked hidden isn't
/// rendered at all. visibility_level stays a fixed field (admin workflow
/// setting, not applicant data).
class MarriageFormScreen extends StatefulWidget {
  const MarriageFormScreen({super.key});

  @override
  State<MarriageFormScreen> createState() => _MarriageFormScreenState();
}

class _MarriageFormScreenState extends State<MarriageFormScreen> {
  static const _fieldRulePrefix = 'marriage_';

  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _summaryController = TextEditingController();
  final _notesController = TextEditingController();
  String? _gender; // Male | Female
  String _visibility = 'employee_only'; // private | employee_only | matched_summary
  bool _busy = false;
  Set<String> _required = {};
  Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    fetchFieldRuleSets().then((rules) {
      if (!mounted) return;
      setState(() {
        _required = rules.required
            .where((k) => k.startsWith(_fieldRulePrefix))
            .map((k) => k.substring(_fieldRulePrefix.length))
            .toSet();
        _hidden = rules.hidden
            .where((k) => k.startsWith(_fieldRulePrefix))
            .map((k) => k.substring(_fieldRulePrefix.length))
            .toSet();
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_ageController, _cityController, _summaryController, _notesController]) {
      c.dispose();
    }
    super.dispose();
  }

  // Note #33 — returns the label key of the first admin-required-but-empty
  // field, or null. Hidden fields are skipped (a hidden field can't be
  // required — the admin isn't shown the checkbox for it either).
  String? _firstMissingRequired() {
    bool blank(String v) => v.trim().isEmpty;
    final checks = <String, bool>{
      'gender': _gender != null,
      'age': !blank(_ageController.text),
      'city': !blank(_cityController.text),
      'social_summary': !blank(_summaryController.text),
      'private_notes': !blank(_notesController.text),
    };
    const labelKeys = <String, String>{
      'gender': 'marriage_gender',
      'age': 'marriage_age',
      'city': 'marriage_city',
      'social_summary': 'marriage_summary',
      'private_notes': 'marriage_private_notes',
    };
    for (final key in _required) {
      if (_hidden.contains(key)) continue;
      final filled = checks[key];
      if (filled == false) return labelKeys[key];
    }
    return null;
  }

  Future<void> _submit() async {
    final missing = _firstMissingRequired();
    if (missing != null) {
      Get.snackbar('marriage_title'.tr, '${missing.tr}: ${'reg_required_missing'.tr}');
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = int.tryParse(sharedPreferences.getString('id_user') ?? '');
      await const ModuleApi().submitMarriage({
        'user_id': uid,
        'gender': _hidden.contains('gender') ? '' : (_gender ?? ''),
        'age': _hidden.contains('age') ? 0 : (int.tryParse(_ageController.text.trim()) ?? 0),
        'city': _hidden.contains('city') ? '' : _cityController.text.trim(),
        'social_summary': _hidden.contains('social_summary') ? '' : _summaryController.text.trim(),
        'private_notes': _hidden.contains('private_notes') ? '' : _notesController.text.trim(),
        'visibility_level': _visibility,
      });
      if (!mounted) return;
      // Note #18 — was Get.back() (just returns to Profile with a toast, no
      // way to check status afterward). Now replaces this screen with the
      // status screen so the user immediately sees "Submitted" and can come
      // back to check it later without re-finding this tile.
      Get.off(() => const MarriageMyProfileScreen());
      Get.snackbar('marriage_title'.tr, 'marriage_submitted'.tr);
    } catch (_) {
      if (mounted) Get.snackbar('marriage_title'.tr, 'marriage_submit_failed'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_title'.tr,
      subtitle: 'marriage_subtitle'.tr,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          if (!_hidden.contains('gender')) ...[
            _label('marriage_gender'),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.wc_outlined)),
              hint: Text('marriage_gender_hint'.tr),
              items: [
                for (final g in const ['Male', 'Female'])
                  DropdownMenuItem(value: g, child: Text(g.tr)),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 14),
          ],
          if (!_hidden.contains('age'))
            _text(_ageController, 'marriage_age', Icons.cake_outlined,
                keyboard: TextInputType.number),
          if (!_hidden.contains('city'))
            _text(_cityController, 'marriage_city', Icons.location_city_outlined),
          if (!_hidden.contains('social_summary'))
            _text(_summaryController, 'marriage_summary', Icons.notes_outlined, lines: 3),
          if (!_hidden.contains('private_notes'))
            _text(_notesController, 'marriage_private_notes', Icons.lock_outline, lines: 2),
          _label('marriage_privacy'),
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.visibility_outlined)),
            items: [
              for (final v in const ['private', 'employee_only', 'matched_summary'])
                DropdownMenuItem(value: v, child: Text('vis_$v'.tr)),
            ],
            onChanged: (v) => setState(() => _visibility = v ?? 'employee_only'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'activity_submitting'.tr : 'marriage_submit'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String key) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(key.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _text(TextEditingController c, String labelKey, IconData icon,
      {int lines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: labelKey.tr,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
