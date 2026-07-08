import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/id_privacy.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #46 — Marriage search: browse profiles (q + gender), save (bookmark), and
/// request a meeting. Backed by GET /api/marriage + /marriage/:id/save +
/// /marriage/:id/request-meeting.
class MarriageSearchScreen extends StatefulWidget {
  const MarriageSearchScreen({super.key});

  @override
  State<MarriageSearchScreen> createState() => _MarriageSearchScreenState();
}

class _MarriageSearchScreenState extends State<MarriageSearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _gender = '';
  final _saved = <int>{};
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final rows = await const ModuleApi()
          .searchMarriage(q: _search.text, gender: _gender);
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

  Future<void> _requestMeeting(int id) async {
    try {
      await const ModuleApi().requestMarriageMeeting(id, '');
      Get.snackbar('marriage_search'.tr, 'meeting_requested'.tr);
    } catch (_) {
      Get.snackbar('marriage_search'.tr, 'meeting_request_failed'.tr);
    }
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
