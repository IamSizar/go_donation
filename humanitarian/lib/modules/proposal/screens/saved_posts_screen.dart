import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

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
  String? _error;

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
    } catch (e) {
      // Was `catch (_) { _loading = false; }` — the failure was swallowed
      // whole, so a fetch that errored fell through to the "Nothing saved
      // yet." empty state. That told the user they had saved nothing when in
      // fact the request had failed, and offered no way to retry.
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your saved items.';
        _loading = false;
      });
      debugPrint('savedMediaPosts failed: $e');
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
      child: AppAsync<List<Map<String, dynamic>>>(
        loading: _loading,
        error: _error,
        onRetry: _load,
        data: _items,
        isEmpty: (list) => list.isEmpty,
        empty: AppEmpty(
          icon: Icons.bookmark_border_rounded,
          title: 'Saved'.tr,
          message: 'Nothing saved yet.'.tr,
        ),
        builder: (list) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final post = list[i];
              return _SavedTile(post: post, onUnsave: () => _unsave(post));
            },
          ),
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
                    // Was `date.substring(0, 10)` — an ISO day, truncated so
                    // deliberately that it read as intentional.
                    localizedDate(date),
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
