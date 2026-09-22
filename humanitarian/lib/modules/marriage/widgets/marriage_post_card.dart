import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/id_privacy.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

// Marriage Posts — resolve a stored photo path to a full URL. Uploads are
// saved as relative paths (e.g. images/uploads/x.png); Image.network needs
// an absolute URL. Same pattern as aid_receipts_screen/marriage_form_screen.
String resolveMarriagePhotoUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final uri = Uri.tryParse(p);
  if (uri != null && uri.hasScheme) return p;
  return Uri.parse(
    publicBaseUrl,
  ).resolve(p.replaceFirst(RegExp(r'^/+'), '')).toString();
}

/// Marriage Posts — the feed IS the approved profiles themselves (photo +
/// age/city/gender + bio), not admin-authored articles. This card is the
/// photo-forward, full-width version used by the continuous feed; the
/// filtered Search screen keeps its own compact `_ProfileCard` unchanged.
class MarriagePostCard extends StatelessWidget {
  const MarriagePostCard({
    super.key,
    required this.profile,
    required this.saved,
    required this.onSave,
    required this.onMeet,
    // Client note 2026-09-22 — like/comment/share, confirmed with the owner
    // given the privacy angle on real people's profiles ("Yes, add all
    // three").
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  final Map<String, dynamic> profile;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onMeet;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final code = maskId((profile['profile_code'] ?? '').toString());
    final gender = (profile['gender'] ?? '').toString();
    final age = (profile['age'] ?? '').toString();
    final city = localizedCity(profile['city']);
    final summary = localizedContentFromMap(profile, 'social_summary');
    final photoUrl = (profile['photo_url'] ?? '').toString();
    final sub = [
      if (gender.isNotEmpty) gender.tr,
      if (age.isNotEmpty && age != '0') age,
      // Localised like the gender beside it; a governorate must not be the
      // one English word in an otherwise Arabic line. Anything that is not a
      // known governorate comes back unchanged, so free-text places survive.
      if (city.isNotEmpty) city,
    ].join(' · ');

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: photoUrl.isNotEmpty
                  ? Image.network(
                      resolveMarriagePhotoUrl(photoUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _placeholder(context, gender),
                    )
                  : _placeholder(context, gender),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: saved ? Colors.pink : null,
                      ),
                      onPressed: onSave,
                    ),
                  ],
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(color: AppThemeConfig.mutedText(context)),
                  ),
                if (summary.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // The bio is whatever the person typed, so it is laid out in
                  // its OWN direction rather than the screen's. An English bio
                  // on an Arabic screen otherwise renders its full stop at the
                  // wrong end: ".life's journey".
                  Text(
                    summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textDirection: contentDirection(
                      summary,
                      fallback: Directionality.of(context),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _EngagementRow(
                  liked: profile['liked_by_me'] == true,
                  likeCount: (profile['like_count'] as num?)?.toInt() ?? 0,
                  commentCount:
                      (profile['comment_count'] as num?)?.toInt() ?? 0,
                  shareCount: (profile['share_count'] as num?)?.toInt() ?? 0,
                  onLike: onLike,
                  onComment: onComment,
                  onShare: onShare,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onMeet,
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text('request_meeting'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, String gender) {
    final icon = gender.toLowerCase() == 'female'
        ? Icons.face_3_rounded
        : Icons.face_6_rounded;
    return Container(
      color: AppThemeConfig.softSurface(context),
      alignment: Alignment.center,
      child: Icon(icon, size: 56, color: AppThemeConfig.mutedText(context)),
    );
  }
}

/// Client note 2026-09-22 — like / comment / share row, same three-action
/// shape as the News & Activities feed's engagement bar
/// (news_activities_screen.dart's _EngagementBar), reused as its own small
/// widget here rather than imported: that one also draws a Save button and
/// is wired to MediaPostsController specifically, neither of which applies
/// to a marriage profile card (Save already has its own bookmark icon up in
/// the header row above).
class _EngagementRow extends StatelessWidget {
  const _EngagementRow({
    required this.liked,
    required this.likeCount,
    required this.commentCount,
    required this.shareCount,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  final bool liked;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EngageIcon(
            icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: liked ? Colors.red : null,
            label: likeCount > 0 ? '$likeCount' : 'Like'.tr,
            onTap: onLike,
          ),
        ),
        Expanded(
          child: _EngageIcon(
            icon: Icons.mode_comment_outlined,
            label: commentCount > 0 ? '$commentCount' : 'Comment'.tr,
            onTap: onComment,
          ),
        ),
        Expanded(
          child: _EngageIcon(
            icon: Icons.share_outlined,
            label: shareCount > 0 ? '$shareCount' : 'Share'.tr,
            onTap: onShare,
          ),
        ),
      ],
    );
  }
}

class _EngageIcon extends StatelessWidget {
  const _EngageIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppThemeConfig.mutedText(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the comments sheet for a marriage profile. Shared by
/// marriage_posts_screen.dart and marriage_saved_screen.dart — both render
/// [MarriagePostCard], so both need the same door into its comments.
void openMarriageComments(
  BuildContext context, {
  required int profileId,
  required ModuleApi api,
  required VoidCallback onCommentPosted,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MarriageCommentsSheet(
      profileId: profileId,
      api: api,
      onCommentPosted: onCommentPosted,
    ),
  );
}

/// Client note 2026-09-22 — comments on a marriage profile card. Same
/// bottom-sheet shape as news_activities_screen.dart's `_CommentsSheet`
/// (opaque draggable sheet, list + pill composer), rebuilt here rather than
/// imported because that one is wired to MediaPostsController specifically;
/// this one only needs to tell its caller a comment landed, via
/// [onCommentPosted].
class _MarriageCommentsSheet extends StatefulWidget {
  const _MarriageCommentsSheet({
    required this.profileId,
    required this.api,
    required this.onCommentPosted,
  });

  final int profileId;
  final ModuleApi api;
  final VoidCallback onCommentPosted;

  @override
  State<_MarriageCommentsSheet> createState() =>
      _MarriageCommentsSheetState();
}

class _MarriageCommentsSheetState extends State<_MarriageCommentsSheet> {
  final _input = TextEditingController();
  final _comments = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted && _error != null) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final rows = await widget.api.marriageComments(widget.profileId);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the comments.'.tr;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await widget.api.postMarriageComment(
        widget.profileId,
        text,
      );
      _input.clear();
      if (res['held'] == true) {
        Get.snackbar('Thanks'.tr, 'Your comment is awaiting review.'.tr);
      } else {
        final cmt = res['comment'];
        if (cmt is Map) {
          setState(() => _comments.insert(0, Map<String, dynamic>.from(cmt)));
        }
        widget.onCommentPosted();
      }
    } catch (_) {
      Get.snackbar('Error'.tr, 'Could not post your comment.'.tr);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppThemeConfig.elevatedSurface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: AppThemeConfig.border(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.mutedText(
                      context,
                    ).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 8, 12),
                  child: Row(
                    children: [
                      Text(
                        'Comments'.tr,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppThemeConfig.text(context),
                        ),
                      ),
                      if (_comments.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppThemeConfig.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_comments.length}',
                            style: TextStyle(
                              color: AppThemeConfig.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppThemeConfig.border(context)),
                Expanded(
                  child: _error != null
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: AppErrorState(
                            message: _error!,
                            onRetry: _load,
                          ),
                        )
                      : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _comments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mode_comment_outlined,
                                size: 40,
                                color: AppThemeConfig.mutedText(
                                  context,
                                ).withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No comments yet.'.tr,
                                style: TextStyle(
                                  color: AppThemeConfig.mutedText(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          itemCount: _comments.length,
                          separatorBuilder: (_, _) => const Divider(height: 20),
                          itemBuilder: (_, i) =>
                              _MarriageCommentTile(comment: _comments[i]),
                        ),
                ),
                Divider(height: 1, color: AppThemeConfig.border(context)),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submit(),
                            style: TextStyle(
                              color: AppThemeConfig.text(context),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Write a comment…'.tr,
                              filled: true,
                              fillColor: AppThemeConfig.softSurface(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(
                                  color: AppThemeConfig.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: _sending
                              ? AppThemeConfig.primary.withValues(alpha: 0.5)
                              : AppThemeConfig.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _sending ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MarriageCommentTile extends StatelessWidget {
  const _MarriageCommentTile({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final name = (comment['user_name'] ?? 'User').toString();
    final body = (comment['body'] ?? '').toString();
    final initial = name.trim().isNotEmpty
        ? name.trim().substring(0, 1).toUpperCase()
        : '?';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppThemeConfig.primary.withValues(alpha: 0.15),
          child: Text(
            initial,
            style: TextStyle(
              color: AppThemeConfig.primary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(color: AppThemeConfig.text(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
