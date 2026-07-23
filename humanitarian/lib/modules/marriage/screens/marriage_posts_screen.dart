import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_post_card.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Marriage Posts — the continuous feed of approved marriage profiles
/// themselves (photo + age/city/gender + bio cards), newest first, infinite
/// scroll. Not admin-authored content: every card is a real profile, shown
/// automatically the moment it goes active — the Search screen stays the
/// filtered on-demand lookup, this is the casual "what's new" browse feed.
/// Visible to every role (including guests, per Note #40's browsing scope);
/// saving/requesting a meeting is gated to signed-in users.
class MarriagePostsScreen extends StatefulWidget {
  const MarriagePostsScreen({super.key});

  @override
  State<MarriagePostsScreen> createState() => _MarriagePostsScreenState();
}

class _MarriagePostsScreenState extends State<MarriagePostsScreen> {
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  final _saved = <int>{};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await const ModuleApi().searchMarriage();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _hasMore = rows.isNotEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'marriage_posts_load_failed'.tr);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final lastId = (_items.last['id'] as num).toInt();
      final rows = await const ModuleApi().searchMarriage(beforeId: lastId);
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.isNotEmpty;
      });
    } catch (_) {
      // Silent — the user can keep scrolling later or pull to refresh.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleSave(int id) async {
    try {
      final saved = await const ModuleApi().toggleSaveMarriage(id);
      if (mounted) setState(() => saved ? _saved.add(id) : _saved.remove(id));
    } catch (_) {}
  }

  Future<void> _requestMeeting(int id) async {
    if (!await requireUpgrade(context)) return;
    try {
      await const ModuleApi().requestMarriageMeeting(id, '');
      Get.snackbar('marriage_posts_title'.tr, 'meeting_requested'.tr);
    } catch (_) {
      Get.snackbar('marriage_posts_title'.tr, 'meeting_request_failed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_posts_title'.tr,
      subtitle: 'marriage_posts_subtitle'.tr,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFirstPage,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  if (_error != null)
                    SectionTile(
                      icon: Icons.diversity_1_rounded,
                      title: 'marriage_posts_title'.tr,
                      subtitle: _error!,
                      color: Colors.deepPurple,
                      onTap: _loadFirstPage,
                    )
                  else if (_items.isEmpty)
                    SectionTile(
                      icon: Icons.diversity_1_rounded,
                      title: 'marriage_posts_title'.tr,
                      subtitle: 'marriage_posts_empty'.tr,
                      color: Colors.deepPurple,
                    )
                  else ...[
                    for (final item in _items) ...[
                      MarriagePostCard(
                        profile: item,
                        saved: _saved.contains((item['id'] as num).toInt()),
                        onSave: () => _toggleSave((item['id'] as num).toInt()),
                        onMeet: () => _requestMeeting((item['id'] as num).toInt()),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_loadingMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
