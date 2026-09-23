import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_post_card.dart';
import 'package:flutter_application_1/modules/marriage/widgets/marriage_request_sheet.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import 'marriage_event_group_screen.dart';
import '../widgets/event_hub_cards.dart';

/// Note #41 — the unified "Marriage" bottom-nav tab. Everyone (including a
/// guest, per Note #40's browsing scope) can browse profiles and read posts.
/// Note #43 — submitting/viewing "my profile" and Subscription used to be
/// restricted to the Beneficiary role only ("This action is not available
/// for your role" on submit); the client asked for every account category to
/// be able to use the Marriage section with no role-based restriction, so
/// these are now gated only on not-guest (guests still can't submit — POST
/// /marriage requires RequireNotGuest() same as Chats in the section grid).
///
/// CHUNK 5 REDESIGN — what used to be here
/// This screen was three flat, full-width tile lists: "Event services" (6
/// tiles), "Events section" (up to 6, guest-gated), and "About & contact" (2
/// tiles). The owner asked for the two service groups to collapse into one
/// top-level grid of two cards — tapping either opens that group as its own
/// grid, in marriage_event_group_screen.dart — and for "About & contact" to
/// be removed from this hub entirely.
///
/// "About My Engagement" (slug `marriage-about`) and "Contact My Engagement"
/// (slug `marriage-contact`) were NOT deleted — only their doors here were.
/// They are now unreachable from the Events tab; nothing else in the app
/// links to those two `ContentPageScreen` slugs either; see the report for
/// this chunk. "Message the staff team" is a different destination (the
/// support chat) and stays in the Events-section grid — do not confuse the
/// two when re-adding an about/contact entry in the future.
///
/// OPOS #25858 — the general humanitarian news/activities feed that used to
/// render below the grid (`GET /api/media?type=activity,news`, the same
/// `media_posts` rows the general News & Activities screen shows) was removed
/// entirely: it mixed humanitarian-work posts into the Marriage section,
/// which the client flagged as a leak. That removal is unaffected by the
/// client report below — this is the MARRIAGE feed (approved profile
/// listings, `marriage_profiles`), never `media_posts`.
///
/// Client report — the marriage posts feed (previously its own screen,
/// `marriage_posts_screen.dart`, reached through "Events section" → a
/// second tile) should be right here instead: below this hub's two cards,
/// one tap closer. `marriage_posts_screen.dart` itself is UNTOUCHED and
/// still used by marriage_event_group_screen.dart / proposal_services_
/// section.dart — this is a second home for the same feed, not a move, so
/// nothing that already links to the standalone screen breaks.
class MarriageHubScreen extends StatefulWidget {
  const MarriageHubScreen({super.key, this.api = const ModuleApi()});

  /// A seam for tests — same reasoning as MarriagePostsScreen.api.
  final ModuleApi api;

  @override
  State<MarriageHubScreen> createState() => _MarriageHubScreenState();
}

class _MarriageHubScreenState extends State<MarriageHubScreen> {
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];

  /// Ids the SERVER says this user has bookmarked — same seeding reasoning
  /// as MarriagePostsScreen._saved.
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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
      // Intentionally silent — see MarriagePostsScreen._loadSaved's doc.
    }
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

  Future<void> _toggleSave(int id) async {
    final wasSaved = _saved.contains(id);
    setState(() => wasSaved ? _saved.remove(id) : _saved.add(id));
    try {
      final saved = await widget.api.toggleSaveMarriage(id);
      if (!mounted) return;
      setState(() => saved ? _saved.add(id) : _saved.remove(id));
    } catch (_) {
      if (!mounted) return;
      setState(() => wasSaved ? _saved.add(id) : _saved.remove(id));
      Get.snackbar('Saved'.tr, 'marriage_saved_toggle_failed'.tr);
    }
  }

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
    await Share.share(
      withEntityLink(
        parts.isEmpty ? 'marriage_posts_title'.tr : parts.join('\n\n'),
        'marriage_profiles',
        id == 0 ? null : id,
      ),
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
      // Deliberately silent — same reasoning as MarriagePostsScreen._share.
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
    // Title AND the Saved door both moved to the persistent top bar
    // (dashboard_screen.dart's DashboardTopBar/_TopBarActions) — client
    // feedback: rendered here as `trailing`, it sat in this screen's OWN
    // header row, a separate widget one row below the persistent bar's ⋯
    // toggle, reading as "below" it rather than beside it. The persistent
    // bar's button opens MarriageSavedScreen directly and does not refresh
    // this screen's `_saved` set on return the way the old in-page button
    // did — an acceptable trade, since a pull-to-refresh or the next visit
    // resyncs it anyway, and the bar has no reference to this State to call
    // back into.
    return SectionScaffold(
      title: '',
      subtitle: '',
      child: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: CustomScrollView(
          controller: _scroll,
          // THE BUG THIS FIXES: this stopped being true once the nav bar
          // redesign made it float OVER tab content (a Stack, not a
          // Scaffold-reserved bar) — see dashboard.dart's
          // _buildDonorDashboard for the full account. 130 matches the same
          // clearance used everywhere else the floating pill sits over a list.
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    CardGrid(
                      children: [
                        StaggeredEntrance(
                          index: 0,
                          child: EventHubCard(
                            heroTag: 'events-hub-services',
                            icon: Icons.celebration_outlined,
                            color: AppThemeConfig.accent(context),
                            title: 'Event services',
                            subtitle:
                                'Book halls, photographers, and everything your event needs',
                            onTap: () =>
                                Get.to(() => const EventServicesGroupScreen()),
                          ),
                        ),
                        StaggeredEntrance(
                          index: 1,
                          child: EventHubCard(
                            heroTag: 'events-hub-section',
                            icon: Icons.groups_outlined,
                            color: AppThemeConfig.accent(context),
                            title: 'Events section',
                            subtitle:
                                'Profiles, posts, and support for the events community',
                            onTap: () =>
                                Get.to(() => const EventsSectionGroupScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: AppThemeConfig.border(context)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AppErrorState(message: _error!, onRetry: _loadFirstPage),
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmpty(
                  icon: Icons.diversity_1_rounded,
                  title: 'marriage_posts_title'.tr,
                  message: 'marriage_posts_empty'.tr,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
                sliver: SliverList.separated(
                  itemCount: _items.length + (_loadingMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    if (i >= _items.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final item = _items[i];
                    return MarriagePostCard(
                      profile: item,
                      saved: _saved.contains((item['id'] as num).toInt()),
                      onSave: () => _toggleSave((item['id'] as num).toInt()),
                      onMeet: () => startMarriageMeetingRequest(
                        context,
                        (item['id'] as num).toInt(),
                        api: widget.api,
                      ),
                      onLike: () async {
                        if (await requireSignIn(context)) _toggleLike(item);
                      },
                      onComment: () async {
                        final signedIn = await requireSignIn(context);
                        if (signedIn && context.mounted) {
                          _openComments(context, item);
                        }
                      },
                      onShare: () => _share(context, item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
