import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import 'event_service_request_screen.dart';
import 'marriage_chats_screen.dart';
import 'marriage_form_screen.dart';
import 'marriage_my_profile_screen.dart';
import 'marriage_posts_screen.dart';
import 'marriage_search_screen.dart';
import 'marriage_subscription_screen.dart';

/// Note #41 — the unified "Marriage" bottom-nav tab. Everyone (including a
/// guest, per Note #40's browsing scope) can browse profiles and read posts.
/// Note #43 — submitting/viewing "my profile" and Subscription used to be
/// restricted to the Beneficiary role only ("This action is not available
/// for your role" on submit); the client asked for every account category to
/// be able to use the Marriage section with no role-based restriction, so
/// these are now gated only on not-guest (guests still can't submit — POST
/// /marriage requires RequireNotGuest() same as Chats below).
class MarriageHubScreen extends StatelessWidget {
  const MarriageHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();

    // Title moved to the persistent top bar (dashboard_screen.dart).
    return SectionScaffold(
      title: '',
      subtitle: '',
      child: ListView(
        // Scaffold already reserves space above the bottom nav bar — this
        // only needs a small resting margin, not extra clearance for it.
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          const SectionLabel(title: 'Event services'),
          const SizedBox(height: 8),
          _MarriageTile(
            icon: Icons.villa_outlined,
            color: Colors.indigo,
            title: 'Hall booking',
            subtitle: 'Request a hall for your event',
            onTap: () => Get.to(
              () =>
                  const EventServiceRequestScreen(serviceLabel: 'Hall booking'),
            ),
          ),
          const SizedBox(height: 12),
          _MarriageTile(
            icon: Icons.camera_alt_outlined,
            color: Colors.brown,
            title: 'Photographer booking',
            subtitle: 'Request a photographer for your event',
            onTap: () => Get.to(
              () => const EventServiceRequestScreen(
                serviceLabel: 'Photographer booking',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _MarriageTile(
            icon: Icons.theater_comedy_outlined,
            color: Colors.indigoAccent,
            title: 'Wedding stage setup',
            subtitle: 'Request a stage setup for your event',
            onTap: () => Get.to(
              () => const EventServiceRequestScreen(
                serviceLabel: 'Wedding stage setup',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _MarriageTile(
            icon: Icons.local_florist_outlined,
            color: Colors.green,
            title: 'Decorations',
            subtitle: 'Request decorations for your event',
            onTap: () => Get.to(
              () =>
                  const EventServiceRequestScreen(serviceLabel: 'Decorations'),
            ),
          ),
          const SizedBox(height: 12),
          _MarriageTile(
            icon: Icons.other_houses_outlined,
            color: Colors.orange,
            title: 'Event tents and equipment',
            subtitle: 'Request tents and related equipment',
            onTap: () => Get.to(
              () => const EventServiceRequestScreen(
                serviceLabel: 'Event tents and equipment',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _MarriageTile(
            icon: Icons.add_circle_outline_rounded,
            color: Colors.blueGrey,
            title: 'Add another service',
            subtitle: 'Request a service not listed above',
            onTap: () => Get.to(
              () => const EventServiceRequestScreen(
                serviceLabel: 'Other service',
                customService: true,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel(title: 'Events section'),
          const SizedBox(height: 8),
          _MarriageTile(
            icon: Icons.search_rounded,
            color: Colors.pinkAccent,
            title: 'Browse profiles',
            subtitle: 'Search event profiles by name or gender',
            onTap: () => Get.to(() => const MarriageSearchScreen()),
          ),
          const SizedBox(height: 12),
          _MarriageTile(
            icon: Icons.article_outlined,
            color: Colors.deepPurple,
            title: 'Event posts',
            subtitle: 'News and stories from the events section',
            onTap: () => Get.to(() => const MarriagePostsScreen()),
          ),
          if (!guest) ...[
            const SizedBox(height: 12),
            _MarriageTile(
              icon: Icons.favorite_outline_rounded,
              color: Colors.pink,
              title: 'Create / edit my profile',
              subtitle: 'Submit or update your event profile',
              onTap: () => Get.to(() => const MarriageFormScreen()),
            ),
            const SizedBox(height: 12),
            _MarriageTile(
              icon: Icons.fact_check_outlined,
              color: Colors.deepOrange,
              title: 'My profile',
              subtitle: 'View your submitted profile and its status',
              onTap: () => Get.to(() => const MarriageMyProfileScreen()),
            ),
            const SizedBox(height: 12),
            _MarriageTile(
              icon: Icons.workspace_premium_rounded,
              color: Colors.pinkAccent,
              title: 'Subscription',
              subtitle: 'Upgrade your profile with a subscription package',
              onTap: () => Get.to(() => const MarriageSubscriptionScreen()),
            ),
          ],
          if (!guest) ...[
            const SizedBox(height: 12),
            _MarriageTile(
              icon: Icons.forum_outlined,
              color: Colors.purple,
              title: 'Chats',
              subtitle: 'Staff-mediated conversations for accepted meetings',
              onTap: () => Get.to(() => const MarriageChatsScreen()),
            ),
            const SizedBox(height: 12),
            _MarriageTile(
              icon: Icons.support_agent_rounded,
              color: Colors.teal,
              title: 'Message the staff team',
              subtitle: 'Questions or issues about the events section',
              onTap: () => ChatActions.startSupportChat(
                context,
                conversationTitle: 'Staff support'.tr,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarriageTile extends StatelessWidget {
  const _MarriageTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppThemeConfig.surface(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppThemeConfig.border(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeConfig.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppThemeConfig.mutedText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
