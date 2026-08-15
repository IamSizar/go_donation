import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/content_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

/// #35 — Read-only app_content page (About / Contact / …). Fetches the
/// admin-editable content from /api/content/:slug and renders it in the current
/// locale (falling back to English). Works pre-login (no auth needed).
///
/// K12 — the page is drawn from its NAMED SUB-SECTIONS when it has any. The
/// client asked "من نحن" to carry three named parts (about the app, about the
/// organization, about its goals); migration 111 stores them, and this screen
/// renders each as its own titled block. `content.body_*` is the server's
/// composition of those same sub-sections, so exactly one of the two is drawn —
/// never both, which would print every word twice.
class ContentPageScreen extends StatefulWidget {
  const ContentPageScreen({
    super.key,
    required this.slug,
    required this.titleKey,
  });
  final String slug;
  final String titleKey;

  @override
  State<ContentPageScreen> createState() => _ContentPageScreenState();
}

/// One rendered part of a content page: a heading and the prose under it.
///
/// An EMPTY [title] is legal and expected — migration 111's backfill turned
/// every pre-K12 page into a single untitled sub-section, because the page
/// heading is `title_*` and repeating it here would double it.
typedef _Block = ({String title, String body});

class _ContentPageScreenState extends State<ContentPageScreen> {
  late Future<ContentPage?> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchContentPage(widget.slug);
  }

  void _retry() => setState(() => _future = fetchContentPage(widget.slug));

  // ─── What to draw ─────────────────────────────────────────────────────────

  /// The page's sub-sections, in order, as renderable blocks.
  ///
  /// A sub-section with nothing in this locale AND nothing in English is
  /// dropped rather than drawn as an empty box — the same rule the server's
  /// `composeBody` applies when it flattens them, so a half-translated page
  /// reads as the parts that exist instead of a run of gaps.
  List<_Block> _blocks(ContentPage page) {
    final out = <_Block>[];
    for (final section in page.sections) {
      final title = localizedAppContent(section, 'title');
      final body = localizedAppContent(section, 'body');
      if (title.isEmpty && body.isEmpty) continue;
      out.add((title: title, body: body));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(title: widget.titleKey.tr),
            Expanded(
              child: FutureBuilder<ContentPage?>(
                future: _future,
                builder: (context, snap) {
                  // First (and only) load: this screen fetches once in
                  // initState and re-fetches only via _retry, so there is no
                  // background refresh that could flash this over a page the
                  // user is already reading.
                  if (snap.connectionState != ConnectionState.done) {
                    return AppSkeleton.paragraphs();
                  }
                  final page = snap.data;
                  // fetchContentPage() returns null for EVERY failure — non-200,
                  // an unexpected body shape, or a thrown request — so null here
                  // is always an error and never a "successfully empty" page.
                  //
                  // Error is tested BEFORE empty, because a failed load also
                  // leaves nothing to render, and reporting that as "this page
                  // has not been filled in yet" would be a false claim about
                  // the organization's own content.
                  //
                  // Scroll view rather than a bare Padding because the
                  // FutureBuilder sits inside an Expanded, whose tight height
                  // would stretch the banner's border down the page.
                  if (page == null) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      child: AppErrorState(
                        message: 'content_load_failed',
                        onRetry: _retry,
                      ),
                    );
                  }
                  return _ContentBody(
                    page: page,
                    blocks: _blocks(page),
                    emptyTitleKey: widget.titleKey,
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

/// The loaded page: heading, then either its sub-sections or its plain body.
///
/// Split out of the screen so the state machine above stays readable and this
/// stays a pure function of what arrived.
class _ContentBody extends StatelessWidget {
  const _ContentBody({
    required this.page,
    required this.blocks,
    required this.emptyTitleKey,
  });

  final ContentPage page;
  final List<_Block> blocks;

  /// The page's own name, used as the empty state's heading so it says WHICH
  /// page has nothing on it.
  final String emptyTitleKey;

  @override
  Widget build(BuildContext context) {
    final heading = localizedAppContent(page.content, 'title');

    // `body_*` is drawn only when the sub-sections produced nothing. For a page
    // that has been split it IS the composition of them (see sections.go), so
    // drawing it alongside would repeat the whole page; for a page that has
    // not, it is the only content there is.
    final fallbackBody = blocks.isEmpty
        ? localizedAppContent(page.content, 'body')
        : '';

    // The heading alone is NOT content: the top bar already names the page, so
    // a lone repeat of it is a blank sheet with a title on it. Prose decides.
    if (blocks.isEmpty && fallbackBody.isEmpty) {
      return AppEmpty(
        icon: Icons.article_outlined,
        title: emptyTitleKey,
        message: 'content_page_empty',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading.isNotEmpty) ...[
            Text(
              heading,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (fallbackBody.isNotEmpty)
            Text(
              fallbackBody,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppThemeConfig.text(context),
              ),
            ),
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _SectionBlock(key: Key('content_section_$i'), block: blocks[i]),
          ],
        ],
      ),
    );
  }
}

/// One named sub-section, as its own card.
///
/// A card rather than a run of headings inside one column: the client's ask is
/// that these read as SEPARATE parts of the page, and grouping related content
/// in a container is how the rest of this app says "this is one thing".
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({super.key, required this.block});

  final _Block block;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.title.isNotEmpty) ...[
            Text(
              block.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.3,
                color: AppThemeConfig.text(context),
              ),
            ),
            if (block.body.isNotEmpty) const SizedBox(height: 10),
          ],
          if (block.body.isNotEmpty)
            Text(
              block.body,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppThemeConfig.text(context),
              ),
            ),
        ],
      ),
    );
  }
}
