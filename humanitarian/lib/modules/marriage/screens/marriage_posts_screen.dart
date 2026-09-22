import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_saved_screen.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_post_card.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_request_sheet.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

/// Marriage Posts — the continuous feed of approved marriage profiles
/// themselves (photo + age/city/gender + bio cards), newest first, infinite
/// scroll. Not admin-authored content: every card is a real profile, shown
/// automatically the moment it goes active — the Search screen stays the
/// filtered on-demand lookup, this is the casual "what's new" browse feed.
/// Visible to every role (including guests, per Note #40's browsing scope);
/// saving/requesting a meeting is gated to signed-in users.
class MarriagePostsScreen extends StatefulWidget {
  const MarriagePostsScreen({super.key, this.api = const ModuleApi()});

  /// A seam for tests — widget tests have no network, so they drive this
  /// screen with a MockClient-backed ModuleApi. Defaulted, so no call site
  /// has to know about it.
  final ModuleApi api;

  @override
  State<MarriagePostsScreen> createState() => _MarriagePostsScreenState();
}

class _MarriagePostsScreenState extends State<MarriagePostsScreen> {
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];

  /// Ids the SERVER says this user has bookmarked.
  ///
  /// THE BUG THIS FIXES: this set used to be filled only by tapping the
  /// bookmark in this session. The toggle always reached the server and the
  /// server always stored it, but nothing ever read the stored list back, so
  /// leaving the screen and returning showed every card unsaved — the save
  /// looked like it "went nowhere". It is now seeded from GET /marriage/saved
  /// on every mount, which is what makes a save survive a remount and a
  /// restart.
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
    _loadSaved();
  }

  /// Seeds [_saved] from the server. Deliberately NOT part of the screen's
  /// load state: the feed is browsable by guests, whose bookmark list is
  /// empty or refused, and a supplementary list failing must never replace
  /// the profiles with an error banner. A failure just leaves the bookmarks
  /// unfilled, which is the state the screen would have had anyway.
  Future<void> _loadSaved() async {
    try {
      final rows = await widget.api.savedMarriageProfiles();
      if (!mounted) return;
      setState(() {
        _saved
          ..clear()
          ..addAll(rows.map((r) => (r['id'] as num).toInt()));
      });
    } catch (_) {
      // Intentionally silent — see the doc comment above.
    }
  }

  /// Opens the saved list and re-reads the bookmarks when it closes, so an
  /// unsave performed in there is reflected here. The two views are never
  /// allowed to disagree; the server is the single source of truth for both.
  Future<void> _openSaved() async {
    await Get.to(() => MarriageSavedScreen(api: widget.api));
    await _loadSaved();
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
      final rows = await widget.api.searchMarriage();
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
      final rows = await widget.api.searchMarriage(beforeId: lastId);
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

  /// Optimistic toggle: the bookmark fills the instant it is tapped, and
  /// rolls back VISIBLY (plus a message) if the server refuses — a save left
  /// on screen that the server rejected is a lie the user would only discover
  /// on their next visit.
  Future<void> _toggleSave(int id) async {
    final wasSaved = _saved.contains(id);
    setState(() => wasSaved ? _saved.remove(id) : _saved.add(id));
    try {
      final saved = await widget.api.toggleSaveMarriage(id);
      if (!mounted) return;
      // Trust the server's answer over our guess — they only differ if the
      // stored state had drifted from what this screen believed.
      setState(() => saved ? _saved.add(id) : _saved.remove(id));
    } catch (_) {
      if (!mounted) return;
      setState(() => wasSaved ? _saved.add(id) : _saved.remove(id));
      Get.snackbar('Saved'.tr, 'marriage_saved_toggle_failed'.tr);
    }
  }

  /// Optimistic like toggle; reconciles with the server response and reverts
  /// on failure. Same shape as MediaPostsController.toggleLike.
  Future<void> _toggleLike(Map<String, dynamic> profile) async {
    final id = int.tryParse('${profile['id']}') ?? 0;
    if (id == 0) return;
    final wasLiked = profile['liked_by_me'] == true;
    final count = (profile['like_count'] as num?)?.toInt() ?? 0;

    setState(() {
      profile['liked_by_me'] = !wasLiked;
      profile['like_count'] = wasLiked
          ? (count - 1).clamp(0, 1 << 31)
          : count + 1;
    });

    try {
      final res = await widget.api.likeMarriageProfile(id);
      if (!mounted) return;
      setState(() {
        profile['liked_by_me'] = res['liked'] == true;
        profile['like_count'] =
            (res['like_count'] as num?)?.toInt() ?? profile['like_count'];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        profile['liked_by_me'] = wasLiked;
        profile['like_count'] = count;
      });
    }
  }

  Future<void> _share(BuildContext context, Map<String, dynamic> profile) async {
    final id = int.tryParse('${profile['id']}') ?? 0;
    final code = (profile['profile_code'] ?? '').toString();
    final summary = (profile['social_summary'] ?? '').toString();
    final parts = <String>[if (code.isNotEmpty) code, if (summary.trim().isNotEmpty) summary];
    // #49-style app link, same convention as the News & Activities share.
    await Share.share(
      withAppLink(parts.isEmpty ? 'marriage_posts_title'.tr : parts.join('\n\n')),
      sharePositionOrigin: shareAnchor(context),
    );
    if (id == 0) return;
    try {
      final res = await widget.api.shareMarriageProfile(id);
      if (!mounted) return;
      setState(() {
        profile['share_count'] =
            (res['share_count'] as num?)?.toInt() ?? profile['share_count'];
      });
    } catch (_) {
      // Deliberately silent — same reasoning as the media-post share: the
      // system share sheet already opened, so a failed count bump has
      // nothing for the user to act on.
    }
  }

  void _bumpCommentCount(Map<String, dynamic> profile) {
    final count = (profile['comment_count'] as num?)?.toInt() ?? 0;
    setState(() => profile['comment_count'] = count + 1);
  }

  void _openComments(BuildContext context, Map<String, dynamic> profile) {
    final id = int.tryParse('${profile['id']}') ?? 0;
    if (id == 0) return;
    openMarriageComments(
      context,
      profileId: id,
      api: widget.api,
      onCommentPosted: () => _bumpCommentCount(profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_posts_title'.tr,
      subtitle: 'marriage_posts_subtitle'.tr,
      // The owner's "small button uptop". IconButton.filledTonal is the same
      // header affordance other sections use, and it sits in the header's
      // `trailing` slot, which is laid out with logical start/end — so it
      // lands on the correct side in Arabic and Kurdish without a single
      // directional constant.
      //
      // minimumSize + standard density are NOT decoration: this app's theme
      // sets a compact visual density, which shrinks a stock IconButton to
      // 40×40 — under the 44pt floor, and the exact mistake this repo already
      // has a live bug from. The glyph stays small; the tap area does not.
      trailing: IconButton.filledTonal(
        onPressed: _openSaved,
        icon: const Icon(Icons.bookmark_rounded, size: 20),
        tooltip: 'Saved'.tr,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          visualDensity: VisualDensity.standard,
        ),
      ),
      child: AppAsync<List<Map<String, dynamic>>>(
        // The gutter lives inside this screen's own list, so the skeleton
        // and the error banner would otherwise sit edge-to-edge while the
        // content that replaces them sits in a 20pt margin.
        gutter: const EdgeInsets.symmetric(horizontal: 20),
        loading: _loading,
        error: _error,
        onRetry: _loadFirstPage,
        data: _items,
        isEmpty: (list) => list.isEmpty,
        empty: AppEmpty(
          icon: Icons.diversity_1_rounded,
          title: 'marriage_posts_title'.tr,
          message: 'marriage_posts_empty'.tr,
        ),
        builder: (list) => RefreshIndicator(
          onRefresh: _loadFirstPage,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              for (final item in list) ...[
                MarriagePostCard(
                  profile: item,
                  saved: _saved.contains((item['id'] as num).toInt()),
                  onSave: () => _toggleSave((item['id'] as num).toInt()),
                  onMeet: () => startMarriageMeetingRequest(
                    context,
                    (item['id'] as num).toInt(),
                    api: widget.api,
                  ),
                  // #44-style guest gate, same as the News & Activities
                  // engagement bar.
                  onLike: () async {
                    if (await requireSignIn(context)) _toggleLike(item);
                  },
                  onComment: () => _openComments(context, item),
                  onShare: () => _share(context, item),
                ),
                const SizedBox(height: 14),
              ],
              // Pagination spinner, NOT a load state: this appends to a list
              // the user is already reading, so it belongs inside the content
              // rather than replacing it.
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

