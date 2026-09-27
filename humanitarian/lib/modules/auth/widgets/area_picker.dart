import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:get/get.dart';

/// One city, district (قضاء) or sub-district (ناحية) under a governorate,
/// as managed from the dashboard's Areas page (migration 136).
class LocationArea {
  const LocationArea({
    required this.id,
    required this.parentId,
    required this.level,
    required this.nameEn,
    required this.nameAr,
    required this.nameCkb,
    required this.nameKmr,
  });

  final int id;
  final int? parentId;
  final String level; // city | district | subdistrict
  final String nameEn;
  final String nameAr;
  final String nameCkb;
  final String nameKmr;

  factory LocationArea.fromMap(Map<String, dynamic> m) => LocationArea(
    id: int.tryParse('${m['id']}') ?? 0,
    parentId: m['parent_id'] == null ? null : int.tryParse('${m['parent_id']}'),
    level: (m['level'] ?? '').toString(),
    nameEn: (m['name_en'] ?? '').toString().trim(),
    nameAr: (m['name_ar'] ?? '').toString().trim(),
    nameCkb: (m['name_ckb'] ?? '').toString().trim(),
    nameKmr: (m['name_kmr'] ?? '').toString().trim(),
  );

  /// What is STORED on the profile: the Arabic name (English when there is
  /// none). One canonical value whatever language the person used, so the
  /// dashboard reads the same word for everyone who picked this place.
  String get value => nameAr.isNotEmpty ? nameAr : nameEn;

  /// What the person READS, in their language (Kurdish falls back to Arabic
  /// when staff have not entered it — Kurdish place names are never guessed).
  String get label => localizedContentFromValues(
    base: nameEn,
    arabic: nameAr,
    sorani: nameCkb,
    badini: nameKmr,
    fallback: value,
  );

  /// A stored value (or a legacy free-text entry) matches this place when it
  /// equals any of its names — so a profile saved in Kurdish still preselects.
  bool matches(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t == nameAr || t == nameEn || t == nameCkb || t == nameKmr;
  }
}

/// The three levels of one governorate.
class AreaLists {
  AreaLists(List<LocationArea> all)
    : cities = all.where((a) => a.level == 'city').toList(),
      _all = all;

  final List<LocationArea> cities;
  final List<LocationArea> _all;

  bool get hasCities => cities.isNotEmpty;

  LocationArea? cityFor(String text) =>
      cities.where((c) => c.matches(text)).firstOrNull;

  List<LocationArea> childrenOf(LocationArea? parent, String level) => parent == null
      ? const []
      : _all.where((a) => a.level == level && a.parentId == parent.id).toList();
}

/// Loads and caches each governorate's areas once per app session. Shared by
/// every form so the registration and marriage forms never fetch the same
/// governorate twice, and so a form can ask "does this governorate have
/// cities?" (to decide whether to show the free-text city box) without owning
/// the request.
class AreaDirectory {
  AreaDirectory._();
  static final AreaDirectory instance = AreaDirectory._();

  /// A seam for tests.
  ModuleApi api = const ModuleApi();

  final Map<String, AreaLists> _lists = {};
  final Map<String, Future<AreaLists>> _inflight = {};

  /// Bumped whenever a governorate finishes loading, so screens can rebuild.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Tests only: forget every loaded governorate.
  @visibleForTesting
  void resetForTest() {
    _lists.clear();
    _inflight.clear();
    api = const ModuleApi();
  }

  AreaLists? peek(String? governorate) =>
      governorate == null ? null : _lists[governorate];

  Future<AreaLists> load(String governorate) {
    final done = _lists[governorate];
    if (done != null) return Future.value(done);
    return _inflight[governorate] ??= () async {
      try {
        final rows = await api.areas(governorate);
        final lists = AreaLists(rows.map(LocationArea.fromMap).toList());
        _lists[governorate] = lists;
        changes.value++;
        return lists;
      } finally {
        _inflight.remove(governorate);
      }
    }();
  }
}

/// The cascading pickers under a governorate: city → district (optional) →
/// sub-district (optional). Each level appears only when staff have entered
/// something for it, so a governorate with no cities yet renders nothing and
/// the form keeps its free-text city box.
///
/// Values are names (see [LocationArea.value]); an empty string means "not
/// picked". Changing a level clears the levels below it.
class AreaPicker extends StatefulWidget {
  const AreaPicker({
    super.key,
    required this.governorate,
    required this.city,
    required this.district,
    required this.subdistrict,
    required this.onChanged,
    required this.cityLabel,
    this.showCity = true,
  });

  final String? governorate;
  final String city;
  final String district;
  final String subdistrict;
  final void Function(String city, String district, String subdistrict)
  onChanged;

  /// The caller's own label for the city (it carries the red required mark
  /// from the field rules, which this widget does not know about).
  final Widget cityLabel;

  /// False when the city field is hidden by the field rules — the whole
  /// cascade hangs off the city, so it hides with it.
  final bool showCity;

  @override
  State<AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<AreaPicker> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AreaPicker old) {
    super.didUpdateWidget(old);
    if (old.governorate != widget.governorate) _load();
  }

  Future<void> _load() async {
    final g = widget.governorate;
    if (g == null || g.isEmpty) return;
    if (_failed) setState(() => _failed = false);
    try {
      await AreaDirectory.instance.load(g);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('areas: could not load $g: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.governorate;
    if (g == null || g.isEmpty || !widget.showCity) {
      return const SizedBox.shrink();
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'areas_load_failed'.tr,
                style: TextStyle(color: AppThemeConfig.mutedText(context)),
              ),
            ),
            TextButton(onPressed: _load, child: Text('Retry'.tr)),
          ],
        ),
      );
    }
    final lists = AreaDirectory.instance.peek(g);
    if (lists == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (!lists.hasCities) return const SizedBox.shrink();

    final city = lists.cityFor(widget.city);
    final districts = lists.childrenOf(city, 'district');
    final district = districts
        .where((d) => d.matches(widget.district))
        .firstOrNull;
    final subdistricts = lists.childrenOf(district, 'subdistrict');
    final subdistrict = subdistricts
        .where((s) => s.matches(widget.subdistrict))
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        widget.cityLabel,
        const SizedBox(height: 6),
        _dropdown(
          icon: Icons.location_city_outlined,
          hint: 'area_city_hint'.tr,
          options: lists.cities,
          selected: city,
          optional: false,
          onPick: (v) => widget.onChanged(v, '', ''),
        ),
        if (districts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _optionalLabel(context, 'area_district'),
          const SizedBox(height: 6),
          _dropdown(
            icon: Icons.map_outlined,
            hint: 'area_district_hint'.tr,
            options: districts,
            selected: district,
            optional: true,
            onPick: (v) => widget.onChanged(city!.value, v, ''),
          ),
        ],
        if (subdistricts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _optionalLabel(context, 'area_subdistrict'),
          const SizedBox(height: 6),
          _dropdown(
            icon: Icons.place_outlined,
            hint: 'area_subdistrict_hint'.tr,
            options: subdistricts,
            selected: subdistrict,
            optional: true,
            onPick: (v) => widget.onChanged(city!.value, district!.value, v),
          ),
        ],
      ],
    );
  }

  Widget _optionalLabel(BuildContext context, String key) => Text.rich(
    TextSpan(
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: AppThemeConfig.mutedText(context),
      ),
      children: [
        TextSpan(text: key.tr),
        TextSpan(
          text: '  ${'area_optional'.tr}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );

  Widget _dropdown({
    required IconData icon,
    required String hint,
    required List<LocationArea> options,
    required LocationArea? selected,
    required bool optional,
    required ValueChanged<String> onPick,
  }) {
    return DropdownButtonFormField<String>(
      // Keyed on the options so switching the parent rebuilds the field
      // with the new list instead of holding a value it no longer offers.
      key: ValueKey('${options.map((o) => o.id).join(',')}|${selected?.id}'),
      initialValue: selected?.value,
      isExpanded: true,
      decoration: InputDecoration(prefixIcon: Icon(icon)),
      hint: Text(hint),
      items: [
        // An optional level can be un-picked again.
        if (optional)
          DropdownMenuItem(value: '', child: Text('area_none'.tr)),
        for (final o in options)
          DropdownMenuItem(value: o.value, child: Text(o.label)),
      ],
      onChanged: (v) => onPick(v ?? ''),
    );
  }
}
