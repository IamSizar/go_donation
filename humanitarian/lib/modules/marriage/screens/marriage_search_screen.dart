import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/registration_api.dart';
import 'package:flutter_application_1/core/id_privacy.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #46 — Marriage search: browse profiles (q + gender), save (bookmark), and
/// request a meeting. Backed by GET /api/marriage + /marriage/:id/save +
/// /marriage/:id/request-meeting.
///
/// Client note — Marriage "Search": filters (age, marital status, religion,
/// employment status, weight, height) are staff-configurable via the same
/// Field Rules mechanism the registration form already uses (a field can be
/// independently required/hidden on the FORM and/or usable as a SEARCH
/// filter) — each filter below only appears once staff enables it.
class MarriageSearchScreen extends StatefulWidget {
  const MarriageSearchScreen({super.key});

  @override
  State<MarriageSearchScreen> createState() => _MarriageSearchScreenState();
}

class _MarriageSearchScreenState extends State<MarriageSearchScreen> {
  static const _fieldRulePrefix = 'marriage_';

  final _search = TextEditingController();
  Timer? _debounce;
  String _gender = '';
  final _saved = <int>{};
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  Set<String> _searchable = {};

  // Extra filters, all optional and only shown when staff-enabled.
  final _minAgeController = TextEditingController();
  final _maxAgeController = TextEditingController();
  String _maritalStatus = '';
  final _religionController = TextEditingController();
  String _employmentStatus = '';
  final _minWeightController = TextEditingController();
  final _maxWeightController = TextEditingController();
  final _minHeightController = TextEditingController();
  final _maxHeightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchFieldRuleSets().then((rules) {
      if (!mounted) return;
      setState(() {
        _searchable = rules.searchable
            .where((k) => k.startsWith(_fieldRulePrefix))
            .map((k) => k.substring(_fieldRulePrefix.length))
            .toSet();
      });
    });
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final c in [
      _minAgeController,
      _maxAgeController,
      _religionController,
      _minWeightController,
      _maxWeightController,
      _minHeightController,
      _maxHeightController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  bool get _hasActiveExtraFilters =>
      _minAgeController.text.trim().isNotEmpty ||
      _maxAgeController.text.trim().isNotEmpty ||
      _maritalStatus.isNotEmpty ||
      _religionController.text.trim().isNotEmpty ||
      _employmentStatus.isNotEmpty ||
      _minWeightController.text.trim().isNotEmpty ||
      _maxWeightController.text.trim().isNotEmpty ||
      _minHeightController.text.trim().isNotEmpty ||
      _maxHeightController.text.trim().isNotEmpty;

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final rows = await const ModuleApi().searchMarriage(
        q: _search.text,
        gender: _gender,
        minAge: int.tryParse(_minAgeController.text.trim()) ?? 0,
        maxAge: int.tryParse(_maxAgeController.text.trim()) ?? 0,
        maritalStatus: _maritalStatus,
        religion: _religionController.text,
        employmentStatus: _employmentStatus,
        minWeight: int.tryParse(_minWeightController.text.trim()) ?? 0,
        maxWeight: int.tryParse(_maxWeightController.text.trim()) ?? 0,
        minHeight: int.tryParse(_minHeightController.text.trim()) ?? 0,
        maxHeight: int.tryParse(_maxHeightController.text.trim()) ?? 0,
      );
      if (mounted) setState(() => _results = rows);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleSave(int id) async {
    try {
      final saved = await const ModuleApi().toggleSaveMarriage(id);
      if (mounted) {
        setState(() => saved ? _saved.add(id) : _saved.remove(id));
      }
    } catch (_) {}
  }

  // Note #40 — requesting a meeting is what opens the staff-mediated marriage
  // chat, so it's gated the same as any other messaging entry point.
  Future<void> _requestMeeting(int id) async {
    if (!await requireUpgrade(context)) return;
    try {
      await const ModuleApi().requestMarriageMeeting(id, '');
      Get.snackbar('marriage_search'.tr, 'meeting_requested'.tr);
    } catch (_) {
      Get.snackbar('marriage_search'.tr, 'meeting_request_failed'.tr);
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: AppThemeConfig.surface(sheetContext),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppThemeConfig.border(sheetContext)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        alignment: Alignment.center,
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppThemeConfig.mutedText(sheetContext)
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Text(
                        'marriage_filters'.tr,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppThemeConfig.text(sheetContext),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_searchable.contains('age'))
                        Row(
                          children: [
                            Expanded(
                              child: _sheetNumberField(
                                _minAgeController,
                                'marriage_min_age',
                                setSheetState,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _sheetNumberField(
                                _maxAgeController,
                                'marriage_max_age',
                                setSheetState,
                              ),
                            ),
                          ],
                        ),
                      if (_searchable.contains('marital_status'))
                        _sheetDropdown(
                          label: 'marriage_marital_status',
                          value: _maritalStatus,
                          options: const ['single', 'married', 'widowed', 'divorced'],
                          optionLabel: (v) => 'marital_status_$v'.tr,
                          onChanged: (v) =>
                              setSheetState(() => _maritalStatus = v ?? ''),
                        ),
                      if (_searchable.contains('religion'))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextField(
                            controller: _religionController,
                            decoration: InputDecoration(
                              labelText: 'marriage_religion'.tr,
                              prefixIcon: const Icon(Icons.church_outlined),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      if (_searchable.contains('employment_status'))
                        _sheetDropdown(
                          label: 'marriage_employment_status',
                          value: _employmentStatus,
                          options: const [
                            'employed',
                            'unemployed',
                            'self_employed',
                            'student',
                          ],
                          optionLabel: (v) => 'employment_status_$v'.tr,
                          onChanged: (v) =>
                              setSheetState(() => _employmentStatus = v ?? ''),
                        ),
                      if (_searchable.contains('weight'))
                        Row(
                          children: [
                            Expanded(
                              child: _sheetNumberField(
                                _minWeightController,
                                'marriage_min_weight',
                                setSheetState,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _sheetNumberField(
                                _maxWeightController,
                                'marriage_max_weight',
                                setSheetState,
                              ),
                            ),
                          ],
                        ),
                      if (_searchable.contains('height'))
                        Row(
                          children: [
                            Expanded(
                              child: _sheetNumberField(
                                _minHeightController,
                                'marriage_min_height',
                                setSheetState,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _sheetNumberField(
                                _maxHeightController,
                                'marriage_max_height',
                                setSheetState,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setSheetState(() {
                                  _minAgeController.clear();
                                  _maxAgeController.clear();
                                  _maritalStatus = '';
                                  _religionController.clear();
                                  _employmentStatus = '';
                                  _minWeightController.clear();
                                  _maxWeightController.clear();
                                  _minHeightController.clear();
                                  _maxHeightController.clear();
                                });
                              },
                              child: Text('marriage_clear_filters'.tr),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _run();
                              },
                              child: Text('marriage_apply_filters'.tr),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Widget _sheetNumberField(
    TextEditingController controller,
    String labelKey,
    StateSetter setSheetState,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: (_) => setSheetState(() {}),
        decoration: InputDecoration(
          labelText: labelKey.tr,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _sheetDropdown({
    required String label,
    required String value,
    required List<String> options,
    required String Function(String) optionLabel,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value.isEmpty ? null : value,
        decoration: InputDecoration(labelText: label.tr),
        items: [
          for (final v in options) DropdownMenuItem(value: v, child: Text(optionLabel(v))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_search'.tr,
      subtitle: 'marriage_search_desc'.tr,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      hintText: 'marriage_search_hint'.tr,
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (_searchable.contains('gender'))
                  DropdownButton<String>(
                    value: _gender.isEmpty ? null : _gender,
                    hint: Text('marriage_gender'.tr),
                    items: [
                      DropdownMenuItem(value: '', child: Text('city_all'.tr)),
                      for (final g in const ['Male', 'Female'])
                        DropdownMenuItem(value: g, child: Text(g.tr)),
                    ],
                    onChanged: (v) {
                      setState(() => _gender = v ?? '');
                      _run();
                    },
                  ),
                if (_searchable.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Material(
                    color: _hasActiveExtraFilters
                        ? AppThemeConfig.primary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'marriage_filters'.tr,
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: _openFilters,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _results.isEmpty && !_loading
                ? Center(child: Text('marriage_no_results'.tr))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ProfileCard(
                      profile: _results[i],
                      saved: _saved.contains(_results[i]['id']),
                      onSave: () => _toggleSave(_results[i]['id'] as int),
                      onMeet: () => _requestMeeting(_results[i]['id'] as int),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.saved,
    required this.onSave,
    required this.onMeet,
  });
  final Map<String, dynamic> profile;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onMeet;

  @override
  Widget build(BuildContext context) {
    final code = maskId((profile['profile_code'] ?? '').toString()); // #54
    final gender = (profile['gender'] ?? '').toString();
    final age = (profile['age'] ?? '').toString();
    final city = (profile['city'] ?? '').toString();
    final summary = localizedContentFromMap(profile, 'social_summary');
    final sub = [if (gender.isNotEmpty) gender.tr, if (age.isNotEmpty && age != '0') age, if (city.isNotEmpty) city]
        .join(' · ');

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              IconButton(
                icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: saved ? Colors.pink : null),
                onPressed: onSave,
              ),
            ],
          ),
          if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.grey)),
          if (summary.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: onMeet,
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text('request_meeting'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
