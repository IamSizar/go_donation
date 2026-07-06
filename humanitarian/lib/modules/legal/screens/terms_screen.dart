import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/content_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Read-only Terms & Conditions page. Fetches the admin-editable content from
/// the public /api/content/terms endpoint and renders it in the current locale
/// (falling back to English). Works pre-login (no auth needed).
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchTermsContent();
  }

  void _retry() => setState(() => _future = fetchTermsContent());

  // Pick the current-locale field (title/body), falling back to English.
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
            const PageTopBar(title: 'Terms & Conditions'),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snap.data;
                  if (data == null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load the Terms & Conditions.'.tr,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _retry,
                            child: Text('Retry'.tr),
                          ),
                        ],
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
