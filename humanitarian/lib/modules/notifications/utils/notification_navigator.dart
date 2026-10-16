// notification_navigator.dart — turns a NotificationDestination into real
// navigation.
//
// The decision (notification_destination.dart) is pure and unit-tested; this
// file is the only part that touches GetX, and it deliberately holds no
// routing logic of its own — every `case` below is a one-line screen push, so
// there is nothing here that can disagree with the tested decision.
//
// HOW IT NAVIGATES, AND WHY THAT WAY
// The app has three named routes only (AppRoutes: splash, welcome, login…);
// screens are pushed as widgets with `Get.to`. That is also how the
// notification tiles already open things (NotificationsController.
// destinationFor), and how the assistant's own resolver works
// (modules/bot/bot_navigation.dart: switch the dashboard tab, pop back to the
// shell, then push the screen one frame later). This reuses that pattern
// rather than inventing a router.

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/chat/screens/chat_conversation_screen.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';
import 'package:flutter_application_1/modules/chatgroups/controllers/chat_groups_controller.dart';
import 'package:flutter_application_1/modules/chatgroups/models/chat_group_models.dart';
import 'package:flutter_application_1/modules/chatgroups/screens/chat_group_conversation_screen.dart';
import 'package:flutter_application_1/modules/chatgroups/utils/chat_group_title.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_orders_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_chat_conversation_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_chats_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_hub_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_my_profile_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_subscription_screen.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/news_activities_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/partners_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_my_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_overview_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_schedule_screen.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/modules/support/screens/technical_support_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/profile.dart';
import 'package:get/get.dart';

import 'notification_destination.dart';

/// Opens [destination].
///
/// Returns without navigating for [NotificationDestinationKind.notificationsList]
/// when [alreadyOnList] is true — tapping a row in the notifications list must
/// not push a second copy of the list on top of itself.
Future<void> openNotificationDestination(
  NotificationDestination destination, {
  bool alreadyOnList = false,
  ModuleApi api = const ModuleApi(),
}) async {
  switch (destination.kind) {
    case NotificationDestinationKind.groupChat:
      Get.to(
        () => ChatGroupConversationScreen(
          groupId: destination.id!,
          title: _groupTitle(destination.id!),
          api: api,
        ),
      );

    case NotificationDestinationKind.directChat:
      Get.to(
        () => ChatConversationScreen(
          threadId: destination.id!,
          title: 'Chat'.tr,
        ),
      );

    case NotificationDestinationKind.marriageChat:
      await _openMarriageChat(destination.id!, api);

    case NotificationDestinationKind.chatRequests:
      Get.to(() => const MessagesScreen());

    case NotificationDestinationKind.myDonations:
      Get.to(() => const MyDonationsPage());

    case NotificationDestinationKind.marketplaceOrders:
      Get.to(() => const MarketplaceOrdersScreen());

    case NotificationDestinationKind.sponsorships:
      Get.to(() => const SponsorshipOverviewScreen());

    case NotificationDestinationKind.sponsorshipSchedule:
      Get.to(() => SponsorshipScheduleScreen());

    case NotificationDestinationKind.myProjectRequests:
      Get.to(() => const BeneficiaryMyProjectsScreen());

    case NotificationDestinationKind.beneficiaryCases:
      Get.to(() => const ProposalServicesSection());

    case NotificationDestinationKind.supportTickets:
      Get.to(() => const TechnicalSupportScreen());

    case NotificationDestinationKind.newsActivities:
      Get.to(() => const NewsActivitiesScreen());

    case NotificationDestinationKind.partners:
      Get.to(() => const PartnersScreen());

    case NotificationDestinationKind.campaigns:
      // DonationsSection pre-selects a campaign when it is given one, so a
      // "new campaign" notification lands ON that campaign, not on the list.
      Get.to(() => DonationsSection(initialCampaignId: destination.id));

    case NotificationDestinationKind.volunteerHub:
      Get.to(() => const SupportSection());

    case NotificationDestinationKind.marriageProfile:
      Get.to(() => const MarriageMyProfileScreen());

    case NotificationDestinationKind.marriageSubscription:
      Get.to(() => const MarriageSubscriptionScreen());

    case NotificationDestinationKind.marriageHub:
      Get.to(() => const MarriageHubScreen());

    case NotificationDestinationKind.profile:
      Get.to(() => const ProfileSection());

    case NotificationDestinationKind.notificationsList:
      if (alreadyOnList) return;
      Get.to(() => const NotificationsScreen());
  }
}

/// The title group [groupId]'s conversation opens under.
///
/// Same rule, and the same reason, as MyConnectRequestsScreen._titleFor: a
/// notification carries neither the group's kind nor its title, so both come
/// from the Messages tab's ChatGroupsController when it is loaded. A group not
/// in that list opens as "Connection", which names no one and is therefore
/// safe for a masked group — chatGroupTitle is the only function allowed to
/// decide this, so no path can put a real name on a masked member's screen.
String _groupTitle(int groupId) {
  final groups = Get.isRegistered<ChatGroupsController>()
      ? Get.find<ChatGroupsController>().groups
      : const <ChatGroupSummary>[];
  for (final group in groups) {
    if (group.id == groupId) return chatGroupTitle(group);
  }
  return 'chat_groups_connection_title'.tr;
}

/// Opens marriage thread [threadId].
///
/// The conversation screen needs three values a push cannot carry — the
/// masked label of the other party, which side the reader is on, and the
/// thread's status — so they are fetched from the same endpoint the marriage
/// chats list reads (`GET /marriage-chats`) and the thread is found by id.
/// If the fetch fails, or the thread is not in the reader's list any more
/// (archived, deleted, or never theirs), the list itself is opened: it shows
/// its own loading, error-with-retry and empty states, so the tap still lands
/// somewhere honest.
Future<void> _openMarriageChat(int threadId, ModuleApi api) async {
  Map<String, dynamic>? thread;
  try {
    final threads = await api.marriageChats();
    for (final row in threads) {
      if (row['id'] == threadId) {
        thread = row;
        break;
      }
    }
  } catch (e) {
    debugPrint('[notification] marriage thread $threadId lookup failed: $e');
  }

  final row = thread;
  if (row == null) {
    Get.to(() => const MarriageChatsScreen());
    return;
  }

  final otherLabelRaw = (row['other_label'] ?? '').toString();
  Get.to(
    () => MarriageChatConversationScreen(
      threadId: threadId,
      // Same mapping the list tile uses: the placeholder is a translation
      // key, a profile code is already public text.
      otherLabel: otherLabelRaw == 'interested_member'
          ? 'marriage_chat_interested_member'.tr
          : otherLabelRaw,
      myRole: (row['my_role'] ?? '').toString(),
      initialStatus: (row['status'] ?? '').toString(),
    ),
  );
}

/// Switches the dashboard to Home and pops back to it before opening a
/// destination, so a notification opened from a tray tap lands on a screen
/// stacked over the app's shell rather than over whatever happened to be on
/// screen. Mirrors BotNavigation.go.
Future<void> openNotificationDestinationFromTray(
  NotificationDestination destination, {
  ModuleApi api = const ModuleApi(),
}) async {
  dashboardTabNotifier.value = 0;
  Get.until((route) => route.isFirst);
  // Defer one frame so the dashboard has rebuilt before the screen is stacked
  // on top of it.
  await WidgetsBinding.instance.endOfFrame;
  await openNotificationDestination(destination, api: api);
}
