import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
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
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _hours = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _selected = <String>{};

  /// The chosen sub-category's slug (K16). Null until one is picked, which is
  /// what `_submit` validates — the field is required, exactly as the free-text
  /// box it replaces was.
  String? _categorySlug;

  bool _busy = false;

  late final CommunityController _controller =
      Get.isRegistered<CommunityController>()
      ? Get.find<CommunityController>()
      : Get.put(CommunityController());

  @override
  void initState() {
    super.initState();
    if (_controller.sectors.isEmpty) _controller.fetchSectors();
    // K16 — the curated sub-categories. Without them "التصنيف" was a free-text
    // box, which is how the column ended up holding 'asdsa' and single Arabic
    // letters alongside real values.
    if (_controller.categories.isEmpty) _controller.fetchCategories();
  }

  @override
  void dispose() {
    for (final c in [_name, _city, _address, _phone, _hours, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The sub-categories offered, given the sectors ticked below.
  ///
  /// Scoped rather than showing all 27: a place tagged "الصحة" has no business
  /// offering "Malls and shopping complexes", and the whole point of the
  /// curated list is that the pair is coherent. With no sector chosen yet the
  /// list is empty and the field says so, which is also the nudge to pick one.
  List<Map<String, dynamic>> get _categoryOptions {
    if (_selected.isEmpty) return const [];
    return _controller.categories
        .where((c) => _selected.contains((c['sector_slug'] ?? '').toString()))
        .toList();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _categorySlug == null) {
      Get.snackbar('add_activity'.tr, 'activity_need_fields'.tr);
      return;
    }
    setState(() => _busy = true);
    try {
      await const ModuleApi().submitCommunity({
        'name': _name.text.trim(),
        // The SLUG, not a typed name: it is stable across languages, and the
        // City Guide filter matches it directly.
        'category': _categorySlug!,
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
          _field(_city, 'activity_city'.tr),
          _field(_address, 'activity_address'.tr),
          _field(_phone, 'activity_phone'.tr, keyboard: TextInputType.phone),
          _field(_hours, 'city_opening_hours'.tr),
          Row(
            children: [
              Expanded(
                child: _field(
                  _lat,
                  'activity_latitude'.tr,
                  keyboard: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _lng,
                  'activity_longitude'.tr,
                  keyboard: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Obx(() {
            final sectors = _controller.sectors.toList();
            if (sectors.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'field_sectors'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                  ),
                ),
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
          const SizedBox(height: 16),
          // K16 — "التصنيف" is a picker now, fed by the curated list under the
          // sectors ticked above. It sits BELOW the sectors on purpose: it
          // cannot offer anything until one is chosen, and a control that
          // fills in after the control above it reads as a consequence rather
          // than as a bug.
          Obx(() {
            final options = _categoryOptions;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'activity_category'.tr} *',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                const SizedBox(height: 8),
                if (_controller.categoriesLoading.value)
                  const AppSkeleton(child: SizedBox(height: 38))
                else if (_controller.categoriesError.value != null)
                  AppErrorState(
                    message: _controller.categoriesError.value!,
                    onRetry: _controller.fetchCategories,
                  )
                else if (options.isEmpty)
                  Text(
                    'activity_pick_sector_first'.tr,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppThemeConfig.mutedText(context),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in options)
                        _categoryChip(
                          (c['slug'] ?? '').toString(),
                          localizedContentFromValues(
                            base: (c['name_en'] ?? '').toString(),
                            arabic: (c['name_ar'] ?? '').toString(),
                            sorani: (c['name_ckb'] ?? '').toString(),
                            badini: (c['name_kmr'] ?? '').toString(),
                            fallback: (c['slug'] ?? '').toString(),
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
              child: Text(
                _busy ? 'activity_submitting'.tr : 'activity_submit'.tr,
              ),
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
        // Un-ticking a sector can strand a sub-category belonging to it, which
        // would then be submitted under a sector the place is not in.
        if (_categorySlug != null &&
            !_categoryOptions.any(
              (c) => (c['slug'] ?? '').toString() == _categorySlug,
            )) {
          _categorySlug = null;
        }
      }),
    );
  }

  /// One sub-category option. Single-select: a place has one classification,
  /// and the spec calls the field "التصنيف الرئيسي والفرعي" — one of each.
  Widget _categoryChip(String slug, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _categorySlug == slug,
      onSelected: (picked) =>
          setState(() => _categorySlug = picked ? slug : null),
    );
  }
}
