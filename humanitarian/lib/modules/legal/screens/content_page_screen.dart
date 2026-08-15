import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/content_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

/// First-load placeholder for a long article of prose.
///
/// The default [AppSkeleton.rows] draws card-like title/meta/progress groups,
/// which is the wrong shape for this screen: what arrives is one heading
/// followed by unbroken paragraphs. These bones are paragraph LINES — full
/// width except for a short last line per paragraph, which is what makes a
/// block of ragged bars read as text rather than as a stack of cards.
/// #35 — Read-only app_content page (About / Contact / …). Fetches the
/// admin-editable content from /api/content/:slug and renders it in the current
/// locale (falling back to English). Works pre-login (no auth needed).
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

class _ContentPageScreenState extends State<ContentPageScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchContent(widget.slug);
  }

  void _retry() => setState(() => _future = fetchContent(widget.slug));

  String _pick(Map<String, dynamic> c, String base) {
    final lang = AppLocaleService.assistantLang(); // en | ar | ckb | kmr
    final v = (c['${base}_$lang'] ?? '').toString().trim();
    return v.isNotEmpty ? v : (c['${base}_en'] ?? '').toString().trim();
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
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _future,
                builder: (context, snap) {
                  // First (and only) load: this screen fetches once in
                  // initState and re-fetches only via _retry, so there is no
                  // background refresh that could flash this over a page the
                  // user is already reading.
                  if (snap.connectionState != ConnectionState.done) {
                    return AppSkeleton.paragraphs();
                  }
                  final data = snap.data;
                  // fetchContent() returns null for EVERY failure — non-200, an
                  // unexpected body shape, or a thrown request — so null here is
                  // always an error and never a "successfully empty" page.
                  // AppAsync is deliberately not used: its required `empty`
                  // branch would be a state this screen cannot reach.
                  //
                  // Behaviour is unchanged (same trigger, same _retry, same
                  // 'content_load_failed' string, which AppErrorState still
                  // resolves with .tr). Only the presentation moves to the
                  // shared error state. Scroll view rather than a bare Padding
                  // because the FutureBuilder sits inside an Expanded, whose
                  // tight height would stretch the banner's border down the page.
                  if (data == null) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      child: AppErrorState(
                        message: 'content_load_failed',
                        onRetry: _retry,
                      ),
                    );
                  }
                  final title = _pick(data, 'title');
                  final body = _pick(data, 'body');
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty) ...[
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppThemeConfig.text(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: AppThemeConfig.text(context),
                          ),
                        ),
                      ],
                    ),
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
