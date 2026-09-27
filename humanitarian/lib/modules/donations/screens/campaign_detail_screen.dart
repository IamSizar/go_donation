import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/localization/money.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_share.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/data/featured_campaigns.dart';
import 'package:flutter_application_1/modules/donations/widgets/campaign_engagement.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/shared/widgets/operation_status_badge.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

/// Full campaign details from the list API; opened when the user taps a featured card.
class CampaignDetailScreen extends StatefulWidget {
  const CampaignDetailScreen({super.key, required this.campaign});

  final FeaturedCampaignData campaign;

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  final _api = ModuleApi();

  // Client report 2026-09-22 — the screen used to show `campaign.likeCount` /
  // `commentCount` as dead numbers with no way to move them. Seeded from the
  // list payload, then updated locally as the viewer likes/comments so the
  // screen doesn't need a full reload to reflect their own action.
  late int _likeCount = widget.campaign.likeCount;
  late int _commentCount = widget.campaign.commentCount;
  bool _liked = false;

  // Client report — a spinner on every tap made a spammed like/unlike feel
  // laggy, even though the toggle itself is cheap. `_liked`/`_likeCount`
  // flip instantly on tap; the server call is debounced behind that so a
  // burst of taps produces exactly one request once the user stops, not one
  // per tap. `_likedSyncedWithServer` is the last state the server actually
  // confirmed — the debounced sync only fires the (toggle-only) API when the
  // user's current choice still disagrees with that, so it self-corrects
  // for the net effect of however many taps happened, not literally each one.
  bool _likedSyncedWithServer = false;
  bool _likeSyncInFlight = false;
  Timer? _likeSyncDebounce;

  @override
  void dispose() {
    _likeSyncDebounce?.cancel();
    _saveSyncDebounce?.cancel();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    if (!await requireSignIn(context)) return;
    if (!mounted) return;
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    AppHaptics.gentle();
    _likeSyncDebounce?.cancel();
    _likeSyncDebounce = Timer(
      const Duration(milliseconds: 700),
      _syncLikeWithServer,
    );
  }

  Future<void> _syncLikeWithServer() async {
    if (_likeSyncInFlight) return;
    if (_liked == _likedSyncedWithServer) return;
    _likeSyncInFlight = true;
    final target = _liked;
    try {
      final res = await _api.likeCampaign(widget.campaign.id);
      if (!mounted) return;
      _likedSyncedWithServer = res['liked'] == true;
      // Only adopt the server's count if the viewer's choice hasn't moved
      // on again while this request was in flight — otherwise the retry
      // below will catch the newer state on its own next pass.
      if (_liked == target) {
        setState(() {
          _likeCount = (res['like_count'] as num?)?.toInt() ?? _likeCount;
        });
      }
    } catch (_) {
      // Left as a local-only state; the next tap's debounce (or the retry
      // below finding _liked still != _likedSyncedWithServer) tries again.
    } finally {
      _likeSyncInFlight = false;
      if (mounted && _liked != _likedSyncedWithServer) {
        _syncLikeWithServer();
      }
    }
  }

  // Client report — save mirrors the like button's optimistic pattern
  // (instant flip, debounced single sync call) for the same reason: a
  // bookmark toggle is cheap, so there's no reason a tap should ever show
  // a spinner or wait on the network.
  bool _saved = false;
  bool _savedSyncedWithServer = false;
  bool _saveSyncInFlight = false;
  Timer? _saveSyncDebounce;

  Future<void> _toggleSave() async {
    if (!await requireSignIn(context)) return;
    if (!mounted) return;
    setState(() => _saved = !_saved);
    AppHaptics.gentle();
    _saveSyncDebounce?.cancel();
    _saveSyncDebounce = Timer(
      const Duration(milliseconds: 700),
      _syncSaveWithServer,
    );
  }

  Future<void> _syncSaveWithServer() async {
    if (_saveSyncInFlight) return;
    if (_saved == _savedSyncedWithServer) return;
    _saveSyncInFlight = true;
    try {
      final res = await _api.saveCampaign(widget.campaign.id);
      if (!mounted) return;
      _savedSyncedWithServer = res['saved'] == true;
    } catch (_) {
      // Same posture as _syncLikeWithServer: left local-only, retried below.
    } finally {
      _saveSyncInFlight = false;
      if (mounted && _saved != _savedSyncedWithServer) {
        _syncSaveWithServer();
      }
    }
  }

  Future<void> _shareCampaign(BuildContext context) async {
    final c = widget.campaign;
    final parts = <String>[c.title, if (c.summary.trim().isNotEmpty) c.summary];
    // Client report — this used to have no share action at all; deep links
    // straight back to this campaign (see app_share.dart's withEntityLink).
    await Share.share(
      withEntityLink(parts.join('\n\n'), 'campaigns', c.id),
      sharePositionOrigin: shareAnchor(context),
    );
  }

  Future<void> _openComments() async {
    if (!await requireSignIn(context)) return;
    if (!mounted) return;
    openCampaignComments(
      context,
      campaignId: widget.campaign.id,
      api: _api,
      onCommentPosted: () => setState(() => _commentCount++),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campaign;
    final accent = AppThemeConfig.accent(context);
    final summaryShort = c.summary.trim();
    final heroSummary = summaryShort.isNotEmpty
        ? summaryShort
        : c.descriptionLong;

    final hasLocationBlock =
        c.location.isNotEmpty ||
        c.beneficiaryCommunity.isNotEmpty ||
        c.peopleAffectedTotal > 0 ||
        c.maleCount > 0 ||
        c.femaleCount > 0;

    return GradientScreen(
      showBottomOrb: false,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: PageTopBar(title: 'Campaign details'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  _HeroSummaryCard(
                    campaign: c,
                    accent: accent,
                    summaryText: heroSummary,
                  ),
                  const SizedBox(height: 12),
                  _EngagementBar(
                    accent: accent,
                    liked: _liked,
                    saved: _saved,
                    likeCount: _likeCount,
                    commentCount: _commentCount,
                    onLike: _toggleLike,
                    onComment: _openComments,
                    onSave: _toggleSave,
                    onShare: () => _shareCampaign(context),
                  ),
                  const SizedBox(height: 18),
                  if (c.descriptionLong.isNotEmpty &&
                      c.descriptionLong.trim() != heroSummary.trim()) ...[
                    _DetailSection(
                      title: 'About this project',
                      child: Text(
                        c.descriptionLong,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.55,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _DetailSection(
                    title: 'Funding',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          label: 'Goal',
                          value:
                              '${c.displayAmountNeeded} ${localizedCurrency(c.currency.trim().isEmpty ? 'IQD' : c.currency)}',
                        ),
                        _DetailRow(
                          label: 'Raised',
                          value:
                              '${c.displayRaisedAmount} ${localizedCurrency(c.currency.trim().isEmpty ? 'IQD' : c.currency)}',
                        ),
                        if (c.fundingAmountsLine.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              c.fundingAmountsLine,
                              style: TextStyle(
                                color: AppThemeConfig.mutedText(context),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        // Spec item 13 — a LinearProgressIndicator of
                        // c.fundedProgress used to sit here, drawing the exact
                        // same fraction the hero pill states as a percentage
                        // and a word, on the same scroll. The Goal and Raised
                        // rows above already give the amounts behind it, so
                        // the bar was the third rendering of one status and is
                        // gone; the pill is the one that says it in words.
                      ],
                    ),
                  ),
                  if (hasLocationBlock) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Location & community',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            label: 'Location',
                            value: c.location,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'Beneficiary community'.tr,
                            value: c.beneficiaryCommunity,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'People affected',
                            value: c.peopleAffectedTotal > 0
                                ? '@n people'.trParams({
                                    'n': '${c.peopleAffectedTotal}',
                                  })
                                : '',
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'Men / women',
                            value: (c.maleCount > 0 || c.femaleCount > 0)
                                ? '@m men · @f women'.trParams({
                                    'm': '${c.maleCount}',
                                    'f': '${c.femaleCount}',
                                  })
                                : '',
                            hideIfEmpty: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_hasVolunteerBlock(c)) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Volunteers',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            label: 'Age profile',
                            value: c.volunteerAgeProfile,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'Skills & knowledge',
                            value: c.volunteerSkillsKnowledge,
                            hideIfEmpty: true,
                          ),
                          _DetailRow(
                            label: 'How volunteers help',
                            value: c.volunteersExtraDescription,
                            hideIfEmpty: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (c.timelineTarget.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Timeline',
                      child: Text(
                        c.timelineTarget,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (_hasContactBlock(c)) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Contact',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            label: 'Contact person',
                            value: c.contactPersonName,
                            hideIfEmpty: true,
                          ),
                          if (c.contactPhone.trim().isNotEmpty)
                            _SelectableDetailRow(
                              label: 'Phone',
                              value: c.contactPhone.trim(),
                            ),
                          if (c.contactEmail.trim().isNotEmpty)
                            _SelectableDetailRow(
                              label: 'Email',
                              value: c.contactEmail.trim(),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (c.otherNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DetailSection(
                      title: 'Notes',
                      child: Text(
                        c.otherNotes,
                        style: TextStyle(
                          color: AppThemeConfig.mutedText(context),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  // "Status & activity" section removed entirely (client
                  // request) — Status/Likes/Comments/Organizer user ID were
                  // internal-looking fields with no donor-facing value, and
                  // Likes/Comments duplicated the real _EngagementBar above.
                  const SizedBox(height: 100),
                ],
              ),
            ),
            // EVERY signed-in role sees this, not only role 1.
            //
            // It used to read `if (role_id == '1')`, so a volunteer or an
            // eligible recipient opening a campaign got the whole page —
            // funding, location, timeline, contact — and no way to give. The
            // client's report was exactly that: "when I tap on a campaign I
            // want to see a button here to donate", from an account that had
            // one hidden from it.
            //
            // Nothing was enforcing the restriction anyway. POST /donations
            // checks that the caller is signed in and not a guest, and says
            // nothing about role, so the gate was a UI opinion rather than a
            // rule — and one no screen stated, since the button simply was
            // not there. Guests are still handled: this pops back to the
            // donate flow, whose own action runs the upgrade prompt (#44 /
            // Note #40) before anything is charged.
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: () {
                    AppHaptics.success();
                    Get.back(result: true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: AppThemeConfig.onAccent(context),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text('Donate to this campaign'.tr),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _hasVolunteerBlock(FeaturedCampaignData c) {
    return c.volunteerAgeProfile.isNotEmpty ||
        c.volunteerSkillsKnowledge.isNotEmpty ||
        c.volunteersExtraDescription.isNotEmpty;
  }

  static bool _hasContactBlock(FeaturedCampaignData c) {
    return c.contactPersonName.isNotEmpty ||
        c.contactPhone.trim().isNotEmpty ||
        c.contactEmail.trim().isNotEmpty;
  }
}

/// Client report 2026-09-22 — a real like toggle + a "open the comments
/// sheet" button, replacing the dead like_count/comment_count display.
class _EngagementBar extends StatelessWidget {
  const _EngagementBar({
    required this.accent,
    required this.liked,
    required this.saved,
    required this.likeCount,
    required this.commentCount,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    required this.onShare,
  });

  final Color accent;
  final bool liked;
  final bool saved;
  final int likeCount;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _EngagementButton(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? accent : AppThemeConfig.mutedText(context),
          label: '$likeCount',
          onTap: onLike,
        ),
        const SizedBox(width: 10),
        _EngagementButton(
          icon: Icons.mode_comment_outlined,
          color: AppThemeConfig.mutedText(context),
          label: '$commentCount',
          onTap: onComment,
        ),
        const Spacer(),
        // Client report — Save/Share existed on marriage posts and news but
        // not here; same two icon-only buttons (no count — neither is a
        // tally the way likes/comments are), trailing rather than grouped
        // with like/comment since they're actions ON the card, not reactions
        // TO it.
        _EngagementButton(
          icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          color: saved ? accent : AppThemeConfig.mutedText(context),
          onTap: onSave,
        ),
        const SizedBox(width: 10),
        _EngagementButton(
          icon: Icons.share_outlined,
          color: AppThemeConfig.mutedText(context),
          onTap: onShare,
        ),
      ],
    );
  }
}

class _EngagementButton extends StatelessWidget {
  const _EngagementButton({
    required this.icon,
    required this.color,
    this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppThemeConfig.surface(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // THE BUG THIS FIXES: a spinner here on every tap made a
              // spammed like/unlike feel laggy even though the toggle is
              // cheap — the button now flips instantly (see _toggleLike's
              // comment) and the icon never shows a loading state.
              Icon(icon, size: 18, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSummaryCard extends StatelessWidget {
  const _HeroSummaryCard({
    required this.campaign,
    required this.accent,
    required this.summaryText,
  });

  final FeaturedCampaignData campaign;
  final Color accent;
  final String summaryText;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        // A flat, faintly accented surface. The 3-stop version washed an 18%
        // accent across the middle of the card, which fought the text sitting
        // on top of it for contrast.
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.06),
          AppThemeConfig.elevatedSurface(context),
        ),
        border: Border.all(color: AppThemeConfig.border(context)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileIcon(icon: c.icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // THE BUG THIS FIXES: title and pill used to share one
                    // Row, with the title in an Expanded fighting the pill
                    // for width. The pill (fixed-width, laid out first, per
                    // Row's flex rules) always got its full natural width —
                    // "X% Partially funded" is wide — leaving the title's
                    // Expanded only the leftover sliver. For a long title
                    // ("Medical Aid for Cancer Patients") that sliver was
                    // narrower than a single word at the title's font size,
                    // so every word wrapped onto its own line, turning the
                    // title into a tall single-word-per-line column. Giving
                    // the title its own full-width line first, with the
                    // pill on the line below, means the title always wraps
                    // against the card's full width instead of whatever the
                    // pill left over.
                    // THE BUG THIS FIXES: `c.title` is often the campaign's
                    // full descriptive sentence, not a short headline (seed/
                    // admin data quality, not a client fix) — at 22px/w800
                    // that read as a wall of shouting text spanning 6-7
                    // lines. Sized down to a normal-weight paragraph size so
                    // a long title reads as a title, not a cluttered block.
                    Text(
                      c.title,
                      style: TextStyle(
                        color: AppThemeConfig.text(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Spec item 13 — this was OperationStatusBadge, a
                    // coloured disc whose state ("delivered in full" /
                    // "partially received" / "not received yet") lived
                    // only in a tooltip, so on screen the meaning was
                    // carried by the colour alone. The pill variant of the
                    // same shared badge shows the percentage AND the word,
                    // which survives greyscale and colour-blindness.
                    // K5 — `fundedProgress` is money raised ÷ goal, so the
                    // pill must say funding. It previously read
                    // "Complete" / "Not received", which is a claim about
                    // delivery that this number cannot support.
                    OperationStatusPill(
                      progress: c.fundedProgress,
                      kind: OperationStatusKind.funding,
                    ),
                    if (c.category.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          c.category,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (summaryText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              summaryText,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                height: 1.5,
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.hideIfEmpty = false,
  });

  final String label;
  final String value;
  final bool hideIfEmpty;

  @override
  Widget build(BuildContext context) {
    if (hideIfEmpty && value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableDetailRow extends StatelessWidget {
  const _SelectableDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label.tr,
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
