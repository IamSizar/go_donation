// The two group screens behind the Events hub's top-level grid (chunk 5).
//
// Everything that used to be the hub's "Event services" and "Events section"
// flat lists now lives one tap deeper, each as its own grid of cards. The
// hub only decides WHICH group to show; the destinations, guest-gating and
// subtitles below are carried over unchanged from marriage_hub_screen.dart's
// previous revision — nothing that used to be reachable from the flat lists
// was dropped, only regrouped.
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/chat_actions.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import 'event_service_request_screen.dart';
import 'marriage_chats_screen.dart';
import 'marriage_my_profile_screen.dart';
import 'marriage_posts_screen.dart';
import 'marriage_search_screen.dart';
import 'marriage_subscription_screen.dart';
import '../widgets/event_hub_cards.dart';

/// One entry in a group's item grid.
class _GroupItem {
  const _GroupItem({
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
}

/// Shared shell for both group screens: a header row carrying the Hero'd
/// icon badge handed off from the tapped hub card, then a 2-column grid of
/// [_GroupItem]s, staggered in on open.
class _EventGroupScreen extends StatelessWidget {
  const _EventGroupScreen({
    required this.heroTag,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String heroTag;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<_GroupItem> items;

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: title,
      subtitle: subtitle,
      // CardGrid over GridView — see its header comment. Item count here
      // varies (2 for a guest, up to 6 signed-in), and a content-sized row
      // is what keeps that from ever stretching two cards to fill the
      // screen or leaving dead space under six short ones.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: CardGrid(
          spacing: 12,
          children: [
            for (var index = 0; index < items.length; index++)
              StaggeredEntrance(
                index: index,
                child: EventHubCard(
                  icon: items[index].icon,
                  color: items[index].color,
                  title: items[index].title,
                  subtitle: items[index].subtitle,
                  onTap: items[index].onTap,
                  dense: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// خدمات الفعاليات — the six event-service request tiles, now a grid.
class EventServicesGroupScreen extends StatelessWidget {
  const EventServicesGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _EventGroupScreen(
      heroTag: 'events-hub-services',
      icon: Icons.celebration_outlined,
      color: AppThemeConfig.accent(context),
      title: 'Event services',
      subtitle: 'Book halls, photographers, and everything your event needs',
      items: [
        _GroupItem(
          icon: Icons.villa_outlined,
          color: AppThemeConfig.accent(context),
          title: 'Hall booking',
          subtitle: 'Request a hall for your event',
          onTap: () => Get.to(
            () =>
                const EventServiceRequestScreen(serviceLabel: 'Hall booking'),
          ),
        ),
        _GroupItem(
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
        _GroupItem(
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
        _GroupItem(
          icon: Icons.local_florist_outlined,
          color: AppThemeConfig.accent(context),
          title: 'Decorations',
          subtitle: 'Request decorations for your event',
          onTap: () => Get.to(
            () => const EventServiceRequestScreen(serviceLabel: 'Decorations'),
          ),
        ),
        _GroupItem(
          icon: Icons.other_houses_outlined,
          color: AppThemeConfig.pending(context),
          title: 'Event tents and equipment',
          subtitle: 'Request tents and related equipment',
          onTap: () => Get.to(
            () => const EventServiceRequestScreen(
              serviceLabel: 'Event tents and equipment',
            ),
          ),
        ),
        _GroupItem(
          icon: Icons.add_circle_outline_rounded,
          color: AppThemeConfig.subtleText(context),
          title: 'Add another service',
          subtitle: 'Request a service not listed above',
          onTap: () => Get.to(
            () => const EventServiceRequestScreen(
              serviceLabel: 'Other service',
              customService: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// قسم الفعاليات — profiles, posts, and (for non-guests) profile management,
/// subscription, chats and staff support, now a grid.
class EventsSectionGroupScreen extends StatelessWidget {
  const EventsSectionGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guest = isGuestMode();

    return _EventGroupScreen(
      heroTag: 'events-hub-section',
      icon: Icons.groups_outlined,
      color: AppThemeConfig.accent(context),
      title: 'Events section',
      subtitle: 'Profiles, posts, and support for the events community',
      items: [
        _GroupItem(
          icon: Icons.search_rounded,
          color: AppThemeConfig.accent(context),
          title: 'Browse profiles',
          subtitle: 'Search event profiles by name or gender',
          onTap: () => Get.to(() => const MarriageSearchScreen()),
        ),
        _GroupItem(
          icon: Icons.article_outlined,
          color: AppThemeConfig.accent(context),
          title: 'Event posts',
          subtitle: 'News and stories from the events section',
          onTap: () => Get.to(() => const MarriagePostsScreen()),
        ),
        if (!guest) ...[
          // Spec item 11 — one entry landing on the status view, which knows
          // the profile's state and offers the right next action itself
          // (there is no PATCH for your own profile — POST /api/marriage
          // always inserts a fresh row, so a separate "create/edit" tile
          // would offer a form that cannot edit anything).
          _GroupItem(
            icon: Icons.favorite_outline_rounded,
            color: AppThemeConfig.accent(context),
            title: 'My profile',
            subtitle: 'View your profile and its status, or create one',
            onTap: () => Get.to(() => const MarriageMyProfileScreen()),
          ),
          _GroupItem(
            icon: Icons.workspace_premium_rounded,
            color: AppThemeConfig.accent(context),
            title: 'Subscription',
            subtitle: 'Upgrade your profile with a subscription package',
            onTap: () => Get.to(() => const MarriageSubscriptionScreen()),
          ),
          _GroupItem(
            icon: Icons.forum_outlined,
            color: AppThemeConfig.accent(context),
            title: 'Chats',
            subtitle: 'Staff-mediated conversations for accepted meetings',
            onTap: () => Get.to(() => const MarriageChatsScreen()),
          ),
          _GroupItem(
            icon: Icons.support_agent_rounded,
            color: AppThemeConfig.accent(context),
            title: 'Message the staff team',
            subtitle: 'Questions or issues about the events section',
            onTap: () => ChatActions.startSupportChat(
              context,
              conversationTitle: 'Staff support'.tr,
            ),
          ),
        ],
      ],
    );
  }
}
