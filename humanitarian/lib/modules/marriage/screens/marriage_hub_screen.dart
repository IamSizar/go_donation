import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

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
class MarriageHubScreen extends StatelessWidget {
  const MarriageHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Title moved to the persistent top bar (dashboard_screen.dart).
    return SectionScaffold(
      title: '',
      subtitle: '',
      child: SingleChildScrollView(
        // Scaffold already reserves space above the bottom nav bar — this
        // only needs a small resting margin, not extra clearance for it.
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: CardGrid(
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
                onTap: () => Get.to(() => const EventServicesGroupScreen()),
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
                onTap: () => Get.to(() => const EventsSectionGroupScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
