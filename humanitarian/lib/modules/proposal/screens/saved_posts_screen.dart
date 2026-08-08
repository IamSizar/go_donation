import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Everything the user has saved for later, newest save first.
///
/// Backed by GET /media?saved=1 — the same list endpoint the feed uses, so a
/// saved post carries every field the feed shows and this screen needs no
/// endpoint of its own. Unsaving from here removes the row immediately rather
/// than waiting for a refetch.
class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = int.tryParse(sharedPreferences.getString('id_user') ?? '');
    if (userId == null || userId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final items = await const ModuleApi().savedMediaPosts(userId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _unsave(Map<String, dynamic> post) async {
    final id = int.tryParse('${post['id']}') ?? 0;
    if (id == 0) return;
    // Drop it straight away — this list is "things I saved", so an unsaved
    // item no longer belongs in it.
    setState(
      () => _items = _items.where((p) => p['id'] != post['id']).toList(),
    );
    try {
      await const ModuleApi().saveMediaPost(id);
    } catch (_) {
      // Put it back if the server refused.
      if (!mounted) return;
      setState(() => _items = [post, ..._items]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Saved'.tr,
      subtitle: '',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                      children: [
                        Icon(
                          Icons.bookmark_border_rounded,
                          size: 48,
                          color: AppThemeConfig.mutedText(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nothing saved yet.'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppThemeConfig.mutedText(context),
                            height: 1.5,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final p = _items[i];
                        return _SavedTile(post: p, onUnsave: () => _unsave(p));
                      },
                    ),
            ),
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.post, required this.onUnsave});

  final Map<String, dynamic> post;
  final VoidCallback onUnsave;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(post, 'title', fallback: 'Post');
    final body = localizedContentFromMap(post, 'body');
    final date = (post['event_date'] ?? post['created_at'] ?? '').toString();
    return GlassPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
                if (date.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    date.length >= 10 ? date.substring(0, 10) : date,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove'.tr,
            onPressed: onUnsave,
            icon: Icon(Icons.bookmark_rounded, color: AppThemeConfig.primary),
          ),
        ],
      ),
    );
  }
}
