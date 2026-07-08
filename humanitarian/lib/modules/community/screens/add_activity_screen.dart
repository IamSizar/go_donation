import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #30 — "Add an Activity": an app user suggests a new City Guide place. It is
/// submitted with status='pending' and appears in the admin approval queue
/// before it shows publicly.
class AddActivityScreen extends StatefulWidget {
  const AddActivityScreen({super.key});

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _hours = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;

  late final CommunityController _controller = Get.isRegistered<CommunityController>()
      ? Get.find<CommunityController>()
      : Get.put(CommunityController());

  @override
  void initState() {
    super.initState();
    if (_controller.sectors.isEmpty) _controller.fetchSectors();
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _city, _address, _phone, _hours, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _category.text.trim().isEmpty) {
      Get.snackbar('add_activity'.tr, 'activity_need_fields'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      await const ModuleApi().submitCommunity({
        'name': _name.text.trim(),
        'category': _category.text.trim(),
        'city': _city.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'opening_hours': _hours.text.trim(),
        'latitude': _lat.text.trim(),
        'longitude': _lng.text.trim(),
        'sectors': _selected.toList(),
      });
      if (!mounted) return;
      Get.back();
      Get.snackbar('add_activity'.tr, 'activity_submitted'.tr);
    } catch (_) {
      if (mounted) Get.snackbar('add_activity'.tr, 'activity_submit_failed'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'add_activity'.tr,
      subtitle: 'activity_subtitle'.tr,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          _field(_name, 'activity_name'.tr, required: true),
          _field(_category, 'activity_category'.tr, required: true),
          _field(_city, 'activity_city'.tr),
          _field(_address, 'activity_address'.tr),
          _field(_phone, 'activity_phone'.tr, keyboard: TextInputType.phone),
          _field(_hours, 'city_opening_hours'.tr),
          Row(
            children: [
              Expanded(child: _field(_lat, 'activity_latitude'.tr, keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field(_lng, 'activity_longitude'.tr, keyboard: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 8),
          Obx(() {
            final sectors = _controller.sectors.toList();
            if (sectors.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('field_sectors'.tr,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppThemeConfig.text(context),
                    )),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in sectors)
                      _sectorChip(
                        (s['slug'] ?? '').toString(),
                        localizedContentFromValues(
                          base: (s['name_en'] ?? '').toString(),
                          arabic: (s['name_ar'] ?? '').toString(),
                          sorani: (s['name_ckb'] ?? '').toString(),
                          badini: (s['name_kmr'] ?? '').toString(),
                          fallback: (s['slug'] ?? '').toString(),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'activity_submitting'.tr : 'activity_submit'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        // Explicit theme-aware text colour — without this the input text
        // inherited the dark-theme default (white) and was invisible in light
        // mode.
        style: TextStyle(color: AppThemeConfig.text(context)),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(color: AppThemeConfig.mutedText(context)),
          filled: true,
          fillColor: AppThemeConfig.softSurface(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeConfig.border(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeConfig.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeConfig.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _sectorChip(String slug, String label) {
    final active = _selected.contains(slug);
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() {
        if (active) {
          _selected.remove(slug);
        } else {
          _selected.add(slug);
        }
      }),
    );
  }
}
