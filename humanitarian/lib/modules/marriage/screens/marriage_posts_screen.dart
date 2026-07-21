import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart' show MediaPostCard;
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// Public marriage-section posts (post_type='marriage', kept out of the
/// general "Our Work" feed since migration 011). Visible to every role —
/// unlike submitting/browsing a profile, this is public content with no
/// backend role restriction, so any user can see program updates/stories.
///
/// Previously duplicated as a tab inside the now-removed
/// `MarriageProfileFormScreen` (modules/proposal); moved here as its own
/// screen so it isn't tied to the (beneficiary-only) submission form.
class MarriagePostsScreen extends StatefulWidget {
  const MarriagePostsScreen({super.key});

  @override
  State<MarriagePostsScreen> createState() => _MarriagePostsScreenState();
}

class _MarriagePostsScreenState extends State<MarriagePostsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = const ModuleApi().mediaPostsByType('marriage');
  }

  Future<void> _refresh() async {
    setState(() => _future = const ModuleApi().mediaPostsByType('marriage'));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'marriage_posts_title'.tr,
      subtitle: 'marriage_posts_subtitle'.tr,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                if (snapshot.hasError)
                  SectionTile(
                    icon: Icons.diversity_1_rounded,
                    title: 'marriage_posts_title'.tr,
                    subtitle: 'marriage_posts_load_failed'.tr,
                    color: Colors.deepPurple,
                    onTap: _refresh,
                  )
                else if (items.isEmpty)
                  SectionTile(
                    icon: Icons.diversity_1_rounded,
                    title: 'marriage_posts_title'.tr,
                    subtitle: 'marriage_posts_empty'.tr,
                    color: Colors.deepPurple,
                  )
                else
                  for (final item in items) ...[
                    MediaPostCard(item: item),
                    const SizedBox(height: 14),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}
