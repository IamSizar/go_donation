// Client report 2026-09-22 — the campaign detail screen showed "Likes" /
// "Comments" counts with no way to ever generate one (campaigns.go's list
// query hardcoded both to 0). This gives the screen a real like toggle and a
// comments sheet, backed by internal/campaigns/engagement.go on the backend.
//
// Rebuilt here rather than imported, same reasoning as
// marriage_post_card.dart's `_MarriageCommentsSheet`: that one is wired to a
// marriage profile id specifically. Visual shape is copied on purpose
// (draggable sheet, list + pill composer) so the moderation/comment mental
// model reads the same across every feed in the app.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:get/get.dart';

void openCampaignComments(
  BuildContext context, {
  required int campaignId,
  required ModuleApi api,
  required VoidCallback onCommentPosted,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CampaignCommentsSheet(
      campaignId: campaignId,
      api: api,
      onCommentPosted: onCommentPosted,
    ),
  );
}

class _CampaignCommentsSheet extends StatefulWidget {
  const _CampaignCommentsSheet({
    required this.campaignId,
    required this.api,
    required this.onCommentPosted,
  });

  final int campaignId;
  final ModuleApi api;
  final VoidCallback onCommentPosted;

  @override
  State<_CampaignCommentsSheet> createState() =>
      _CampaignCommentsSheetState();
}

class _CampaignCommentsSheetState extends State<_CampaignCommentsSheet> {
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
      final rows = await widget.api.campaignComments(widget.campaignId);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (_) {
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
      final res = await widget.api.postCampaignComment(
        widget.campaignId,
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
                              _CampaignCommentTile(comment: _comments[i]),
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

class _CampaignCommentTile extends StatelessWidget {
  const _CampaignCommentTile({required this.comment});

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
                  color: AppThemeConfig.text(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  color: AppThemeConfig.mutedText(context),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
