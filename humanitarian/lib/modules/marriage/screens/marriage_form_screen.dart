import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #42 — Marriage/engagement profile form with a privacy (visibility) control.
/// Submits to POST /api/marriage. The backend restricts this to the eligible
/// role; the entry tile is only shown to eligible users.
class MarriageFormScreen extends StatefulWidget {
  const MarriageFormScreen({super.key});

  @override
  State<MarriageFormScreen> createState() => _MarriageFormScreenState();
}

class _MarriageFormScreenState extends State<MarriageFormScreen> {
  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _summaryController = TextEditingController();
  final _notesController = TextEditingController();
  String? _gender; // Male | Female
  String _visibility = 'employee_only'; // private | employee_only | matched_summary
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_ageController, _cityController, _summaryController, _notesController]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final uid = int.tryParse(sharedPreferences.getString('id_user') ?? '');
      await const ModuleApi().submitMarriage({
        'user_id': uid,
        'gender': _gender ?? '',
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'city': _cityController.text.trim(),
        'social_summary': _summaryController.text.trim(),
        'private_notes': _notesController.text.trim(),
        'visibility_level': _visibility,
      });
      if (!mounted) return;
      Get.back();
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
          _text(_ageController, 'marriage_age', Icons.cake_outlined,
              keyboard: TextInputType.number),
          _text(_cityController, 'marriage_city', Icons.location_city_outlined),
          _text(_summaryController, 'marriage_summary', Icons.notes_outlined, lines: 3),
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
