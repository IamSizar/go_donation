import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #33 — Global search: one box that queries the whole app (campaigns, news,
/// products, partners, city places) and lists typed, localized results.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;

  static const _typeMeta = <String, ({IconData icon, String labelKey, Color color})>{
    'campaign': (icon: Icons.volunteer_activism_rounded, labelKey: 'search_campaigns', color: Colors.pink),
    'media': (icon: Icons.article_rounded, labelKey: 'search_media', color: Colors.indigo),
    'product': (icon: Icons.storefront_rounded, labelKey: 'search_products', color: Colors.teal),
    'partner': (icon: Icons.handshake_rounded, labelKey: 'search_partners', color: Colors.orange),
    'place': (icon: Icons.location_city_rounded, labelKey: 'search_places', color: Colors.blue),
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final rows = await const ModuleApi().globalSearch(q);
      if (mounted) setState(() => _results = rows);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'search_title'.tr,
      subtitle: 'search_subtitle'.tr,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'search_hint'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _searched && _results.isEmpty && !_loading
                ? Center(child: Text('search_no_results'.tr))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ResultTile(result: _results[i], meta: _typeMeta),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.meta});
  final Map<String, dynamic> result;
  final Map<String, ({IconData icon, String labelKey, Color color})> meta;

  @override
  Widget build(BuildContext context) {
    final type = (result['type'] ?? '').toString();
    final m = meta[type];
    final name = localizedContentFromMap(result, 'name', fallback: '—');
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (m?.color ?? Colors.grey).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(m?.icon ?? Icons.search_rounded, color: m?.color ?? Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  (m?.labelKey ?? type).tr,
                  style: TextStyle(fontSize: 12, color: m?.color ?? Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
