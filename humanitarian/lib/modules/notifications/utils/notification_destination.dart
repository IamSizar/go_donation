// notification_destination.dart — the ONE place that decides where a
// notification leads.
//
// WHY THIS FILE EXISTS
// The client: "when I tap on a notification inside the app it should take me
// to the exact place of this notification". Two things were wrong. A tap on a
// TRAY push navigated nowhere at all (lib/main.dart only printed a debug line,
// and the cold-start tap was not handled), and a tap in the IN-APP list knew
// about three families only — support tickets, media posts and partners — so
// the other sixty-odd notification types the backend emits were dead taps.
//
// WHAT THIS IS
// A pure function from a notification's DATA to a destination. No Flutter
// navigation, no Firebase, no I/O — so every type can be pinned in a plain
// unit test (test/notifications/notification_destination_test.dart), and the
// four entry points that open a notification cannot drift apart:
//   • FirebaseMessaging.onMessageOpenedApp   (tray tap, app backgrounded)
//   • FirebaseMessaging.getInitialMessage()  (tray tap, app killed)
//   • the in-app notifications list          (NotificationsController)
//   • the notification detail dialog, which reuses the controller's answer.
// Turning a destination into navigation is notification_navigator.dart's job.
//
// THE DATA KEYS IT READS
// Push delivery is being changed in parallel (OPOS #26709), so this reads the
// keys that mirror the columns the backend ALREADY writes on every in-app row
// (notify.LocalizedMessage → app_notifications), and accepts the obvious
// aliases so either payload shape routes:
//   • type                 ← alias: notification_type
//   • related_entity_type  ← alias: entity_type
//   • related_entity_id    ← aliases: entity_id, thread_id, group_id
// `related_entity_type` is authoritative when present because it is the
// stabler half: the backend adds notification TYPES far faster than it adds
// entity kinds, and a type this app has never heard of on an entity it knows
// is still routable.
//
// THE RULE THAT OUTRANKS EVERYTHING
// Never a dead tap. Anything unknown, any missing or malformed id, and every
// chat notification that reaches a GUEST (#106, #113) resolves to the
// notifications list, which always exists.

import 'package:flutter/foundation.dart';

/// Every place a notification can send someone.
///
/// Deliberately a closed set, not "any screen": a notification may only land
/// on a screen that can be reached with what a notification actually carries
/// (a type and at most one id). Screens that need a fetched object to be
/// constructed — a campaign, a case, a partner, a marriage thread — are
/// represented by the list they are opened from, which is one tap away and
/// never a dead end.
enum NotificationDestinationKind {
  /// A staff-created group conversation. Carries the group id.
  groupChat,

  /// A 1:1 / staff-support conversation. Carries the thread id.
  directChat,

  /// A staff-mediated marriage conversation. Carries the thread id.
  marriageChat,

  /// Messages — where an incoming chat request is accepted or declined.
  chatRequests,

  /// The donor's own contribution history.
  myDonations,

  /// The buyer's marketplace orders.
  marketplaceOrders,

  /// Sponsorship (kafala) overview.
  sponsorships,

  /// The sponsorship payment schedule — due / overdue occurrences.
  sponsorshipSchedule,

  /// The beneficiary's own project requests.
  myProjectRequests,

  /// The services section, which lists beneficiary cases.
  beneficiaryCases,

  /// Technical support: the ticket history and any staff reply.
  supportTickets,

  /// News & activities — media posts.
  newsActivities,

  /// The partners directory.
  partners,

  /// The campaigns list.
  campaigns,

  /// The volunteer hub: open missions, my missions, my applications.
  volunteerHub,

  /// The user's own marriage profile.
  marriageProfile,

  /// The marriage subscription screen.
  marriageSubscription,

  /// The marriage hub.
  marriageHub,

  /// The user's own account / profile screen.
  profile,

  /// The notifications list itself — the universal, never-dead fallback.
  notificationsList,
}

/// Where a notification leads: a [kind] and, for the destinations that need
/// one, the id of the thing to open.
@immutable
class NotificationDestination {
  const NotificationDestination._(this.kind, [this.id]);

  /// What sort of place this is.
  final NotificationDestinationKind kind;

  /// The id the destination opens, or null for destinations that take none.
  /// Always > 0 when present — a parsed 0 or negative is treated as missing.
  final int? id;

  /// True when landing here would put the user inside a chat. Guests must
  /// never reach one (#106, #113).
  bool get isChat =>
      kind == NotificationDestinationKind.groupChat ||
      kind == NotificationDestinationKind.directChat ||
      kind == NotificationDestinationKind.marriageChat ||
      kind == NotificationDestinationKind.chatRequests;

  static NotificationDestination groupChat(int id) =>
      NotificationDestination._(NotificationDestinationKind.groupChat, id);
  static NotificationDestination directChat(int id) =>
      NotificationDestination._(NotificationDestinationKind.directChat, id);
  static NotificationDestination marriageChat(int id) =>
      NotificationDestination._(NotificationDestinationKind.marriageChat, id);

  static const chatRequests = NotificationDestination._(
    NotificationDestinationKind.chatRequests,
  );
  static const myDonations = NotificationDestination._(
    NotificationDestinationKind.myDonations,
  );
  static const marketplaceOrders = NotificationDestination._(
    NotificationDestinationKind.marketplaceOrders,
  );
  static const sponsorships = NotificationDestination._(
    NotificationDestinationKind.sponsorships,
  );
  static const sponsorshipSchedule = NotificationDestination._(
    NotificationDestinationKind.sponsorshipSchedule,
  );
  static const myProjectRequests = NotificationDestination._(
    NotificationDestinationKind.myProjectRequests,
  );
  static const beneficiaryCases = NotificationDestination._(
    NotificationDestinationKind.beneficiaryCases,
  );
  static const supportTickets = NotificationDestination._(
    NotificationDestinationKind.supportTickets,
  );
  static const newsActivities = NotificationDestination._(
    NotificationDestinationKind.newsActivities,
  );
  static const partners = NotificationDestination._(
    NotificationDestinationKind.partners,
  );
  static const campaigns = NotificationDestination._(
    NotificationDestinationKind.campaigns,
  );

  /// The campaigns list, pre-selecting campaign [id] — DonationsSection takes
  /// an initialCampaignId, so this one entity CAN be opened exactly.
  static NotificationDestination campaign(int id) =>
      NotificationDestination._(NotificationDestinationKind.campaigns, id);
  static const volunteerHub = NotificationDestination._(
    NotificationDestinationKind.volunteerHub,
  );
  static const marriageProfile = NotificationDestination._(
    NotificationDestinationKind.marriageProfile,
  );
  static const marriageSubscription = NotificationDestination._(
    NotificationDestinationKind.marriageSubscription,
  );
  static const marriageHub = NotificationDestination._(
    NotificationDestinationKind.marriageHub,
  );
  static const profile = NotificationDestination._(
    NotificationDestinationKind.profile,
  );
  static const notificationsList = NotificationDestination._(
    NotificationDestinationKind.notificationsList,
  );

  @override
  bool operator ==(Object other) =>
      other is NotificationDestination &&
      other.kind == kind &&
      other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() =>
      'NotificationDestination(${kind.name}${id == null ? '' : ', $id'})';
}

// ─── The tables ──────────────────────────────────────────────────────────────

/// Chat entities, which need an id AND a guest check. Kept apart from the
/// table below because they are the only destinations a guest may not reach.
const _chatEntityTypes = <String>{
  'chat_thread',
  'chat_group_thread',
  'marriage_chat_thread',
  // staff_chat_thread is deliberately absent: internal staff chat is an
  // admin-web system and the app has no screen for it (grep staff_chat in
  // humanitarian/lib returns translation strings only), so it falls back.
};

/// related_entity_type → where that entity is looked at in the app.
///
/// Every value here is a screen that exists and opens with no argument, so a
/// notification lands on it even when the payload carries no usable id. Where
/// the app has a DETAIL screen that needs a fetched object (a campaign needs
/// FeaturedCampaignData, a case and a partner need their row), the list the
/// detail is opened from is the destination — one tap short of the object,
/// never a dead end.
const _byEntityType = <String, NotificationDestination>{
  'donations': NotificationDestination.myDonations,
  'in_kind_donations': NotificationDestination.myDonations,
  'marketplace_orders': NotificationDestination.marketplaceOrders,
  'sponsorships': NotificationDestination.sponsorships,
  'sponsorship_schedule': NotificationDestination.sponsorshipSchedule,
  'beneficiary_project_requests': NotificationDestination.myProjectRequests,
  'beneficiary_cases': NotificationDestination.beneficiaryCases,
  'support_tickets': NotificationDestination.supportTickets,
  'media_posts': NotificationDestination.newsActivities,
  'partners': NotificationDestination.partners,
  'campaigns': NotificationDestination.campaigns,
  'volunteer_missions': NotificationDestination.volunteerHub,
  'volunteer_applications': NotificationDestination.volunteerHub,
  'volunteer_application_missions': NotificationDestination.volunteerHub,
  'volunteer_mission_signups': NotificationDestination.volunteerHub,
  'marriage_profiles': NotificationDestination.marriageProfile,
  'marriage_meeting_request': NotificationDestination.marriageHub,
  'users': NotificationDestination.profile,
};

/// notification type → destination, for the types whose entity is absent or
/// would send the user to the wrong place. Consulted BEFORE [_byEntityType].
const _byType = <String, NotificationDestination>{
  // Types whose name carries the whole meaning: the backend's "new X"
  // announcements name their entity only in related_entity_type, so a push
  // that ships the type alone still has to route.
  'new_campaign': NotificationDestination.campaigns,
  'new_media_post': NotificationDestination.newsActivities,
  'post_comment_received': NotificationDestination.newsActivities,
  'new_partner': NotificationDestination.partners,
  'new_volunteer_mission': NotificationDestination.volunteerHub,

  // Legacy singular types the in-app list has always handled. They are not in
  // internal/notify/templates.go — admin-composed rows use them — and they
  // carry no related entity, so they are matched by name.
  'media_post': NotificationDestination.newsActivities,
  'news': NotificationDestination.newsActivities,
  'activity': NotificationDestination.newsActivities,
  'partner': NotificationDestination.partners,

  // The marriage subscription templates carry no related entity at all.
  'marriage_subscription_activated':
      NotificationDestination.marriageSubscription,
  'marriage_subscription_pending': NotificationDestination.marriageSubscription,
  'marriage_subscription_rejected':
      NotificationDestination.marriageSubscription,

  // Admin-facing alerts. The recipient is staff, whose tools are the web
  // dashboard; the app has no screen for another person's registration,
  // guest account, case or project request, so these stay on the list rather
  // than opening the reader's OWN profile or cases, which would be a lie.
  'admin_new_registration': NotificationDestination.notificationsList,
  'admin_new_guest_account': NotificationDestination.notificationsList,
  'admin_new_beneficiary_case': NotificationDestination.notificationsList,
  'admin_new_project_request': NotificationDestination.notificationsList,
  'admin_new_marriage_profile': NotificationDestination.notificationsList,
  'marriage_subscription_pending_admin':
      NotificationDestination.notificationsList,
};

/// Type prefixes, for the families the backend builds by concatenation
/// (`"support_ticket_" + status`, `"volunteer_mission_" + status`). Only
/// consulted when the payload carries no usable related_entity_type.
const _byTypePrefix = <String, NotificationDestination>{
  // Chat prefixes are absent on purpose: a chat is resolved in step 1, which
  // is the only place that has the id and the guest gate.
  'support_ticket': NotificationDestination.supportTickets,
  'support_request': NotificationDestination.supportTickets,
  'donation_': NotificationDestination.myDonations,
  'in_kind_donation_': NotificationDestination.myDonations,
  'marketplace_order_': NotificationDestination.marketplaceOrders,
  'sponsorship_': NotificationDestination.sponsorships,
  'project_request_': NotificationDestination.myProjectRequests,
  'beneficiary_case_': NotificationDestination.beneficiaryCases,
  'volunteer_': NotificationDestination.volunteerHub,
  'registration_': NotificationDestination.profile,
  'marriage_': NotificationDestination.marriageProfile,
};

// ─── The decision ────────────────────────────────────────────────────────────

/// Where the notification described by [data] should take the reader.
///
/// [data] is a push payload (`RemoteMessage.data`, all values Strings) or the
/// equivalent map built from an in-app row. Unknown keys are ignored.
///
/// [isGuest] is a CALLBACK, not a bool, and is invoked only when the answer
/// would otherwise be a chat: the production implementation reads
/// SharedPreferences, which is not initialised in every caller, and a
/// notification about a donation has no business touching it.
///
/// Never returns null. The worst case is
/// [NotificationDestination.notificationsList].
NotificationDestination resolveNotificationDestination(
  Map<String, dynamic> data, {
  required bool Function() isGuest,
}) {
  final type = _string(data, const ['type', 'notification_type']);
  final entityType = _string(data, const [
    'related_entity_type',
    'entity_type',
  ]);
  final id = _id(data);

  // 1 — chats. Identified by entity first, then by the type family, because a
  // chat is the one destination that is useless without its id and forbidden
  // to a guest.
  final chatEntity = _chatEntityTypes.contains(entityType)
      ? entityType
      : _chatEntityForType(type);
  if (chatEntity != null) {
    final destination = _chatDestination(chatEntity, type, id);
    if (destination == null) return NotificationDestination.notificationsList;
    // Asked here and nowhere else — the last gate before a chat screen.
    if (isGuest()) return NotificationDestination.notificationsList;
    return destination;
  }

  // 2 — a campaign is the one non-chat entity the app can open EXACTLY
  // (DonationsSection takes an initialCampaignId), so its id is used when the
  // payload carries one. Ahead of the tables so neither can lose the id.
  if (entityType == 'campaigns' && id != null) {
    return NotificationDestination.campaign(id);
  }

  // 3 — a type with an opinion of its own outranks its entity.
  final byType = _byType[type];
  if (byType != null) return byType;

  // 4 — the entity the notification is about.
  final byEntity = _byEntityType[entityType];
  if (byEntity != null) return byEntity;

  // 5 — a type family, for payloads that carry no entity at all.
  for (final entry in _byTypePrefix.entries) {
    if (type.startsWith(entry.key)) return entry.value;
  }

  // 6 — nothing matched. The list always exists.
  return NotificationDestination.notificationsList;
}

/// The chat entity a type belongs to, or null when it is not a chat type.
/// Used only when the payload carries no related_entity_type.
String? _chatEntityForType(String type) {
  if (type.startsWith('marriage_chat')) return 'marriage_chat_thread';
  if (type.startsWith('chat_group')) return 'chat_group_thread';
  if (type.startsWith('chat_')) return 'chat_thread';
  // staff_chat_message falls through on purpose: internal staff chat has no
  // screen in this app, so it is not a chat destination here.
  return null;
}

/// The conversation for a chat entity, or null when it cannot be opened.
NotificationDestination? _chatDestination(
  String chatEntity,
  String type,
  int? id,
) {
  // A direct chat REQUEST is answered on Messages; there is no conversation
  // to open until it is accepted, so it needs no id.
  if (type == 'chat_request') return NotificationDestination.chatRequests;
  if (id == null) return null;
  return switch (chatEntity) {
    'chat_group_thread' => NotificationDestination.groupChat(id),
    'chat_thread' => NotificationDestination.directChat(id),
    // Marriage Accept/Decline lives INSIDE the conversation
    // (marriage_chat_conversation_screen.dart), so a request and a message
    // share one destination.
    'marriage_chat_thread' => NotificationDestination.marriageChat(id),
    _ => null,
  };
}

/// The first non-empty value among [keys], trimmed and lower-cased.
String _string(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final text = value.toString().trim().toLowerCase();
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// The entity id, or null when absent or malformed.
///
/// FCM delivers every value as a String, so '42' must parse; an in-app row may
/// hand over an int, so 42 must too. Anything else — '', 'abc', '1.5', '0',
/// '-4' — is treated as missing rather than guessed at, which is what turns a
/// broken payload into the notifications list instead of a crash or a wrong
/// conversation.
int? _id(Map<String, dynamic> data) {
  for (final key in const [
    'related_entity_id',
    'entity_id',
    'thread_id',
    'group_id',
  ]) {
    final value = data[key];
    if (value == null) continue;
    final parsed = value is int ? value : int.tryParse(value.toString().trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}
