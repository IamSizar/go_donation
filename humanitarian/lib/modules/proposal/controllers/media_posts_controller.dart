import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';

class MediaPostsController extends GetxController {
  /// Optional `post_type` filter, passed straight through to `?type=` (which
  /// accepts a comma-separated list, e.g. 'activity,news').
  ///
  /// null = the general News & Activities feed, which the server serves minus
  /// `marriage` posts. A filtered instance MUST be registered under a GetX tag
  /// so `Get.find<MediaPostsController>()` — the untagged lookup the News &
  /// Activities screen does — cannot pick it up and silently inherit the
  /// narrower feed.
  MediaPostsController({this.postType});

  final String? postType;

  final posts = <Map<String, dynamic>>[].obs;
  // #22 — "Our Work" categories + the active filter (null = All).
  final categories = <Map<String, dynamic>>[].obs;
  final selectedCategory = RxnString();
  final isLoading = false.obs;
  final errorMessage = RxnString();

  /// J8 — the in-list search term, sent to the server as `?q=`.
  ///
  /// Server-side deliberately. A page holds at most 50 posts (`clampLimit`),
  /// so a filter over [posts] would search the newest 50 and report an older
  /// activity as nonexistent. `GET /api/media` matches title, title_ar AND the
  /// post body in SQL, so searching for a word from inside a write-up finds it.
  final searchQuery = ''.obs;

  /// Whether a query is narrowing the feed right now. Drives the empty copy:
  /// "no posts published yet" is a claim about the organization's work.
  bool get hasActiveSearch => searchQuery.value.trim().isNotEmpty;

  /// Applies [query] and reloads from the server. A no-op when unchanged.
  Future<void> setSearchQuery(String query) async {
    final next = query.trim();
    if (next == searchQuery.value) return;
    searchQuery.value = next;
    await fetchPosts();
  }

  @override
  void onInit() {
    super.onInit();
    fetchPosts();
    fetchCategories();
  }

  int get _currentUserId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  /// Whether the archive has more posts beyond the ones already loaded.
  ///
  /// Starts true only so the first page may be asked for; it is set from the
  /// server's `next_cursor` from then on, and false is FINAL for the current
  /// query — that is what stops the feed asking for a page that is not there.
  final hasMorePosts = true.obs;

  /// A page-append is in flight. Distinct from [isLoading], which means "the
  /// screen has nothing to show yet": one draws a skeleton in place of the
  /// feed, the other a small spinner underneath a feed the user is reading.
  final isLoadingMore = false.obs;

  /// Cursor for the next page, or null at the end of the archive. Opaque.
  String? _nextCursor;

  /// Which query the in-flight requests belong to.
  ///
  /// THE BUG THIS PREVENTS: the user types a new search while page 2 of the
  /// OLD one is still on the wire. Without this counter the old page lands
  /// afterwards and is appended to the new results — page 2 of one query
  /// stitched onto page 1 of another, with its cursor left in place so every
  /// later page continues the wrong feed. Every load captures the generation
  /// it started in and drops its response if the generation has moved on.
  int _queryGeneration = 0;

  /// Loads the FIRST page, discarding anything loaded before.
  ///
  /// Every filter change funnels through here — a new search term or a pull to
  /// refresh restarts the archive walk from the newest post rather than
  /// continuing the previous query's cursor.
  Future<void> fetchPosts() async {
    final generation = ++_queryGeneration;
    isLoading.value = true;
    errorMessage.value = null;
    _nextCursor = null;
    hasMorePosts.value = true;
    try {
      final page = await const ModuleApi().mediaPostsPage(
        userId: _currentUserId,
        q: searchQuery.value,
        type: postType,
      );
      if (generation != _queryGeneration) return;
      posts.assignAll(page.items);
      _nextCursor = page.nextCursor;
      hasMorePosts.value = page.nextCursor != null;
    } catch (_) {
      if (generation != _queryGeneration) return;
      posts.clear();
      hasMorePosts.value = false;
      errorMessage.value = 'Unable to load news and activities.'.tr;
    } finally {
      if (generation == _queryGeneration) isLoading.value = false;
    }
  }

  /// Appends the next page of the archive. A no-op at the end of it, while a
  /// page is already in flight, or while the first page is still loading.
  Future<void> loadMorePosts() async {
    final cursor = _nextCursor;
    if (cursor == null ||
        !hasMorePosts.value ||
        isLoadingMore.value ||
        isLoading.value) {
      return;
    }
    final generation = _queryGeneration;
    isLoadingMore.value = true;
    try {
      final page = await const ModuleApi().mediaPostsPage(
        userId: _currentUserId,
        q: searchQuery.value,
        type: postType,
        cursor: cursor,
      );
      // The query changed under us — this page belongs to a feed that is no
      // longer on screen, so it is dropped rather than appended.
      if (generation != _queryGeneration) return;
      posts.addAll(page.items);
      _nextCursor = page.nextCursor;
      hasMorePosts.value = page.nextCursor != null;
    } catch (_) {
      // Deliberate: the posts already on screen stay, and the next scroll to
      // the tail retries. A snackbar over a readable feed would be noise, and
      // clearing it would punish the reader for a failed APPEND.
    } finally {
      if (generation == _queryGeneration) isLoadingMore.value = false;
    }
  }

  /// #24 — optimistic like toggle; reconciles with the server response and
  /// reverts on failure.
  Future<void> toggleLike(Map<String, dynamic> post) async {
    final id = int.tryParse('${post['id']}') ?? 0;
    if (id == 0) return;
    final wasLiked = post['liked_by_me'] == true;
    final count = (post['like_count'] as num?)?.toInt() ?? 0;

    post['liked_by_me'] = !wasLiked;
    post['like_count'] = wasLiked ? (count - 1).clamp(0, 1 << 31) : count + 1;
    posts.refresh();

    try {
      final res = await const ModuleApi().likeMediaPost(id);
      post['liked_by_me'] = res['liked'] == true;
      post['like_count'] =
          (res['like_count'] as num?)?.toInt() ?? post['like_count'];
      posts.refresh();
    } catch (_) {
      // Deliberate: the rollback restores the exact pre-tap counts, so the card
      // never shows a like the server did not record. The heart visibly springing
      // back is the feedback; a snackbar per failed tap would be noise.
      post['liked_by_me'] = wasLiked;
      post['like_count'] = count;
      posts.refresh();
    }
  }

  /// Optimistic "save for later" toggle; reverts on failure, same as
  /// [toggleLike]. There is no counter to keep in step — a save is private to
  /// the user, so only their own flag changes.
  Future<void> toggleSaved(Map<String, dynamic> post) async {
    final id = int.tryParse('${post['id']}') ?? 0;
    if (id == 0) return;
    final wasSaved = post['saved_by_me'] == true;

    post['saved_by_me'] = !wasSaved;
    posts.refresh();

    try {
      final res = await const ModuleApi().saveMediaPost(id);
      post['saved_by_me'] = res['saved'] == true;
      posts.refresh();
    } catch (_) {
      // Deliberate: same optimistic rollback as [toggleLike] — the flag returns
      // to its true value, so nothing false is left on screen.
      post['saved_by_me'] = wasSaved;
      posts.refresh();
    }
  }

  /// #24 — bump a post's comment count locally after a comment is accepted.
  void bumpCommentCount(int postId) {
    for (final p in posts) {
      if ((int.tryParse('${p['id']}') ?? 0) == postId) {
        p['comment_count'] = ((p['comment_count'] as num?)?.toInt() ?? 0) + 1;
        posts.refresh();
        return;
      }
    }
  }

  /// #24 — bump a post's share count locally after a successful share.
  void bumpShareCount(int postId) {
    for (final p in posts) {
      if ((int.tryParse('${p['id']}') ?? 0) == postId) {
        p['share_count'] = ((p['share_count'] as num?)?.toInt() ?? 0) + 1;
        posts.refresh();
        return;
      }
    }
  }

  // Best-effort: on failure the feed just shows no filter chips.
  Future<void> fetchCategories() async {
    try {
      categories.assignAll(await const ModuleApi().mediaCategories());
    } catch (_) {
      // Deliberate: no chips is a NARROWER claim than a wrong chip row, and the
      // posts themselves (which carry their own error state) still load.
      categories.clear();
    }
  }

  void selectCategory(String? slug) => selectedCategory.value = slug;

  /// Posts after applying the active category filter.
  ///
  /// Still client-side, over the pages loaded so far — the API has no
  /// `?category=`, so a server-side version would be a new endpoint parameter
  /// rather than a rearrangement here. It composes with paging because the
  /// filter is re-applied to [posts] every time a page is appended: scrolling
  /// on keeps widening the pool this reads from, and switching category never
  /// touches the cursor, so no request is wasted re-fetching what is already
  /// loaded.
  List<Map<String, dynamic>> get visiblePosts {
    final slug = selectedCategory.value;
    if (slug == null || slug.isEmpty) return posts;
    return posts
        .where((p) => (p['category_slug'] ?? '').toString() == slug)
        .toList(growable: false);
  }

  /// Localized display name for a category map (CMS field convention
  /// name_en/name_ar/name_ckb/name_kmr), falling back to English.
  String localizedCategoryName(Map<String, dynamic> cat) {
    const byLang = {
      'en': 'name_en',
      'ar': 'name_ar',
      'ckb': 'name_ckb',
      'kmr': 'name_kmr',
    };
    final key = byLang[AppLocaleService.assistantLang()] ?? 'name_en';
    final v = (cat[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    return (cat['name_en'] ?? '').toString();
  }

  /// Localized name for a post's category_slug (empty if unknown/uncategorized).
  String categoryLabelForSlug(String? slug) {
    if (slug == null || slug.isEmpty) return '';
    for (final cat in categories) {
      if ((cat['slug'] ?? '').toString() == slug) {
        return localizedCategoryName(cat);
      }
    }
    return '';
  }
}
