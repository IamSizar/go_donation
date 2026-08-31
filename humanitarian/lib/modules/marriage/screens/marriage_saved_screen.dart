import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_post_card.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_request_sheet.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// The profiles the user bookmarked on the Marriage Posts feed, newest first.
///
/// Reached from the bookmark button in the feed's own header. It is a sibling
/// of `modules/proposal/screens/saved_posts_screen.dart` rather than a reuse of
/// it: that screen is bound to media posts — it fetches `GET /media?saved=1`
/// and renders a title/body/date tile — while this list holds marriage
/// PROFILES, a different endpoint and a different card. What is shared is the
/// shape, deliberately: same SectionScaffold, same AppAsync with the 20pt
/// gutter, same "drop the row immediately, put it back if the server refuses"
/// unsave.
///
/// Backed by GET /api/marriage/saved, which answers with the same rows as the
/// feed's search, so [MarriagePostCard] renders here unchanged.
class MarriageSavedScreen extends StatefulWidget {
  const MarriageSavedScreen({super.key, this.api = const ModuleApi()});

  /// A seam for tests — widget tests have no network, so they drive this
  /// screen with a MockClient-backed ModuleApi. Defaulted, so no call site
  /// has to know about it.
  final ModuleApi api;

  @override
  State<MarriageSavedScreen> createState() => _MarriageSavedScreenState();
}

class _MarriageSavedScreenState extends State<MarriageSavedScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.savedMarriageProfiles();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      // Never fall through to the empty state on a failed fetch: that would
      // tell the user they saved nothing when in fact the request failed, and
      // would offer no way to retry.
      if (!mounted) return;
      setState(() {
        _error = 'marriage_saved_load_failed'.tr;
        _loading = false;
      });
    }
  }

  /// Optimistic unsave: the row leaves at once — this list is "things I
  /// saved", so an unsaved profile no longer belongs in it — and comes back
  /// visibly if the server refuses, rather than leaving a removal on screen
  /// that never happened.
  Future<void> _unsave(Map<String, dynamic> profile) async {
    final id = (profile['id'] as num?)?.toInt() ?? 0;
    if (id == 0) return;
    final index = _items.indexOf(profile);
    setState(
      () => _items = _items.where((p) => p['id'] != profile['id']).toList(),
    );
    try {
      await widget.api.toggleSaveMarriage(id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final restored = [..._items];
        restored.insert(index.clamp(0, restored.length), profile);
        _items = restored;
      });
      Get.snackbar('Saved'.tr, 'marriage_saved_unsave_failed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Saved'.tr,
      subtitle: '',
      child: AppAsync<List<Map<String, dynamic>>>(
        // The gutter lives inside this screen's own list, so the skeleton and
        // the error banner would otherwise sit edge-to-edge while the content
        // that replaces them sits in a 20pt margin.
        gutter: const EdgeInsets.symmetric(horizontal: 20),
        loading: _loading,
        error: _error,
        onRetry: _load,
        data: _items,
        isEmpty: (list) => list.isEmpty,
        empty: AppEmpty(
          icon: Icons.bookmark_border_rounded,
          title: 'Saved'.tr,
          // Says what to do next, not just that the list is empty.
          message: 'marriage_saved_empty'.tr,
        ),
        builder: (list) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, i) => MarriagePostCard(
              profile: list[i],
              // Every row here is saved by definition, so the bookmark is
              // always filled and always means "remove".
              saved: true,
              onSave: () => _unsave(list[i]),
              // Same flow as the feed's card, shared rather than copied.
              onMeet: () => startMarriageMeetingRequest(
                context,
                (list[i]['id'] as num).toInt(),
                api: widget.api,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
