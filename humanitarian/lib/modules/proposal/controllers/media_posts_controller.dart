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
  /// Server-side deliberately. The feed is capped at 50 posts (`clampLimit`),
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

  Future<void> fetchPosts() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await const ModuleApi().mediaPosts(
        userId: _currentUserId,
        q: searchQuery.value,
        type: postType,
      );
      posts.assignAll(rows);
    } catch (_) {
      posts.clear();
      errorMessage.value = 'Unable to load news and activities.'.tr;
    } finally {
      isLoading.value = false;
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

  /// Posts after applying the active category filter (client-side; the feed is
  /// already capped, so no extra round-trip).
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
